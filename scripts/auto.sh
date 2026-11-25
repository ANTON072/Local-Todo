#!/usr/bin/env bash
# ready の Issue を1件ずつ、実装 → PR → レビュー → レビュー対応 → マージまで進める。
# 判断の理由は docs/adr/0005-auto-run.md。
# 組織の設定で make や git push には確認が要るので、スキルは対話の claude で開く。人はその場で確認に答え、
# スキルが「終わりました」と言ったら /exit で閉じる。閉じると、このスクリプトが次へ進む。
# 使い方: scripts/auto.sh（LIMIT=<数> で、手をつける Issue の数の上限を決める）
#
# macOS の /bin/bash（3.2）で動くように書く。連想配列や mapfile は使わない。
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

# 途中で Mac がスリープすると止まるので、caffeinate の下で動かし直す。
if [[ -z "${LOCAL_TODO_CAFFEINATED:-}" ]]; then
	exec env LOCAL_TODO_CAFFEINATED=1 caffeinate -i "$0" "$@"
fi

limit="${LIMIT:-}"
if [[ -n "$limit" && ! "$limit" =~ ^[0-9]+$ ]]; then
	echo "LIMIT には数を指定してください: ${limit}" >&2
	exit 1
fi

log_dir=".auto-logs"
mkdir -p "$log_dir"

# 処理した Issue ごとの結果。最後に一覧で出す。
results=()
add_result() { results+=("$1"); }

finish() {
	local status="$1"
	echo
	echo "== make auto の結果"
	if [[ ${#results[@]} -eq 0 ]]; then
		echo "処理した Issue はありません。"
	else
		printf '%s\n' "${results[@]}"
	fi
	local message="処理した Issue: ${#results[@]} 件"
	if [[ "$status" -ne 0 ]]; then
		message="途中で止まりました（${message}）"
	fi
	osascript -e "display notification \"${message}\" with title \"make auto\"" >/dev/null 2>&1 || true
	exit "$status"
}

# --- ラベル ---------------------------------------------------------------

ensure_label() {
	local name="$1" color="$2" description="$3"
	if ! gh label list --limit 200 --json name --jq '.[].name' | grep -qxF "$name"; then
		gh label create "$name" --color "$color" --description "$description" >/dev/null
		echo "ラベル ${name} を作りました。" >&2
	fi
}

ensure_label ready 0e8a16 "詰め終わった。実装してよい"
ensure_label auto-merge 1d76db "レビューの指摘にすべて対応したら、自動でマージしてよい"
ensure_label in-progress fbca04 "自動実行で処理中"
ensure_label ready-to-merge 5319e7 "レビューの指摘にすべて対応した。人がマージするだけ"
ensure_label needs-human d93f0b "自動では決められないことがある"

# --- Issue を選ぶ ----------------------------------------------------------

# 「## 先に終わっている必要がある Issue」の節に書かれた #<番号> がすべて閉じていれば 0 を返す。
# 節がない Issue はテンプレートどおりでないので取らない（1 を返す）。
prerequisites_closed() {
	local number="$1" body section ref
	body="$(gh issue view "$number" --json body --jq '.body')"
	if ! grep -q '^## 先に終わっている必要がある Issue' <<<"$body"; then
		echo "Issue #${number} には「先に終わっている必要がある Issue」の節がないので、取りません。" >&2
		return 1
	fi
	section="$(awk '/^## 先に終わっている必要がある Issue/ { inside = 1; next } /^## / { inside = 0 } inside' <<<"$body")"
	for ref in $(grep -oE '#[0-9]+' <<<"$section" | tr -d '#' || true); do
		if [[ "$(gh issue view "$ref" --json state --jq '.state')" != "CLOSED" ]]; then
			return 1
		fi
	done
	return 0
}

next_issue() {
	local number
	for number in $(gh issue list --state open --label ready --limit 200 --json number,labels \
		--jq 'map(select([.labels[].name] | index("needs-human") | not)) | sort_by(.number) | .[].number'); do
		if prerequisites_closed "$number"; then
			echo "$number"
			return 0
		fi
	done
	return 0
}

# --- claude ----------------------------------------------------------------

# スキルは、自動実行のとき、最後に {status, pr_url, summary} を LOCAL_TODO_RESULT のファイルに書く。
# status は 完了・needs-human・中断 のどれか。

# 自動実行のときだけ効く許可。対話のセッションには効かせないので、.claude/settings.json には入れない。
# ここにないコマンドと、組織の設定で確認が要るコマンド（make・git push・git pull など）は、その場で人に確認が出る。
# gh は、スキルが使う形だけにする。gh pr merge と gh api は許可しない。gh api を許すと、REST でのマージや
# GraphQL でのスレッドの resolve ができ、マージとレビューの関門（このスクリプトが握る）を通り抜けられるため。
# レビューコメントの読み書きは make comment・make reply・make unresolved、resolve は make resolve に限る。
# make は、スキルが使うものだけにする。make review と make auto は、書いたセッションには呼ばせない。
# 変数を展開するコマンド（echo "$X" など）は、許可に挙げても確認が出る。スキルが使う
# printenv LOCAL_TODO_AUTO・printenv LOCAL_TODO_RESULT は、展開を含まないので許可できる。
allowed_tools=(
	"Read" "Edit" "Write" "Glob" "Grep" "Agent" "Skill"
	"Bash(printenv LOCAL_TODO_AUTO)" "Bash(printenv LOCAL_TODO_RESULT)"
	"Bash(echo:*)" "Bash(cat:*)" "Bash(ls:*)" "Bash(cp:*)" "Bash(diff:*)"
	"Bash(git:*)"
	"Bash(gh issue view:*)" "Bash(gh issue comment:*)" "Bash(gh issue edit:*)"
	"Bash(gh pr create:*)" "Bash(gh pr view:*)" "Bash(gh pr edit:*)" "Bash(gh pr diff:*)" "Bash(gh pr list:*)"
	"Bash(make check)" "Bash(make format)" "Bash(make lint)" "Bash(make test)" "Bash(make generate)"
	"Bash(make re-review:*)" "Bash(make resolve:*)"
	"Bash(make comment:*)" "Bash(make reply:*)" "Bash(make unresolved:*)"
	"Bash(swift format:*)" "Bash(xcodegen:*)" "Bash(xcodebuild:*)"
)

# 許可の一覧より強く、はっきり拒否するもの。
# main への直接の push は、GitHub のルールセット（protect-main の pull_request）でも拒否される。
disallowed_tools=("Bash(gh pr merge:*)" "Bash(gh api:*)" "Bash(git push origin main:*)" "Bash(git push origin HEAD:main:*)")

# スキルを対話の claude で自動実行として開き、閉じたあとで結果を RESULT_FILE に読み込む。
# 結果のファイルがない（途中で閉じたなど）ときは 1 を返す。
# claude は画面を使うので、$(…) の中では呼ばない。
run_skill() {
	local number="$1" step="$2" prompt="$3"
	RESULT_FILE="${PWD}/${log_dir}/$(date +%Y%m%d-%H%M%S)-${number}-${step}.json"
	echo
	echo "== Issue #${number}: ${step} を開きます。確認が出たら答え、「終わりました」と出たら /exit で閉じてください。" >&2
	# プロンプトは先頭に置く。--allowedTools などは値をいくつも取るので、うしろに置くとツールとして読まれる。
	# --setting-sources project：手元の .claude/settings.local.json やユーザーの設定の許可
	# （gh pr * や gh api * など）が、上の一覧に足されないようにする。
	if ! LOCAL_TODO_AUTO=1 LOCAL_TODO_RESULT="$RESULT_FILE" claude "$prompt" \
		--setting-sources project \
		--allowedTools "${allowed_tools[@]}" \
		--disallowedTools "${disallowed_tools[@]}"; then
		echo "Issue #${number}: ${step} の claude が失敗しました。" >&2
		return 1
	fi
	if ! jq -e '.status | IN("完了", "needs-human", "中断")' "$RESULT_FILE" >/dev/null 2>&1; then
		echo "Issue #${number}: ${step} の結果（${RESULT_FILE}）を受け取れませんでした。" >&2
		return 1
	fi
}

# --- PR の状態 -------------------------------------------------------------

unresolved_threads() {
	local pr_number="$1"
	gh api graphql --field owner='{owner}' --field repo='{repo}' --field number="$pr_number" \
		--raw-field query='
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      reviewThreads(first: 100) { nodes { isResolved } }
    }
  }
}' --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved | not)] | length'
}

# code-reviewer の最新のレビュー本文を出す。レビューがなければ空。取れなければ 1 を返す。
latest_review_body() {
	local pr_number="$1"
	gh api "repos/{owner}/{repo}/pulls/${pr_number}/reviews" \
		--jq '[.[] | select(.body | startswith("Claude Code（code-reviewer）のレビュー"))] | last | .body // ""'
}

# マージの関門になる判定は、読めなかったときに「問題なし」と読まないよう、読めなければその場で止める。
# [[ ]] の中のコマンド置換には set -e が効かず、失敗すると空の文字列が 0 として比べられてしまうため。

# 未解決のスレッドの数を UNRESOLVED に入れる。読めなければ、in-progress のまま止まる。
read_unresolved() {
	local number="$1" pr_number="$2" pr_url="$3"
	if ! UNRESOLVED="$(unresolved_threads "$pr_number")" || [[ ! "$UNRESOLVED" =~ ^[0-9]+$ ]]; then
		add_result "#${number}: 未解決のスレッドの数を読めずに止まりました（${pr_url}、in-progress のまま）"
		finish 1
	fi
}

# code-reviewer の最新のレビュー本文に「差分の外の指摘」があれば OUTSIDE_FINDINGS を yes にする。
# 差分の外の指摘はスレッドにならず、address-review-comment では対応できない。読めなければ、in-progress のまま止まる。
read_outside_findings() {
	local number="$1" pr_number="$2" pr_url="$3" body
	if ! body="$(latest_review_body "$pr_number")"; then
		add_result "#${number}: レビュー本文を読めずに止まりました（${pr_url}、in-progress のまま）"
		finish 1
	fi
	OUTSIDE_FINDINGS=""
	if grep -q '^## 差分の外の指摘' <<<"$body"; then
		OUTSIDE_FINDINGS="yes"
	fi
}

# mergeable は、GitHub が計算し終えるまで UNKNOWN になるので、少し待って読み直す。
pr_mergeable() {
	local pr_number="$1" state="" try
	for try in 1 2 3 4 5 6; do
		state="$(gh pr view "$pr_number" --json mergeable --jq '.mergeable')"
		[[ "$state" != "UNKNOWN" ]] && break
		sleep 5
	done
	echo "$state"
}

# スクリプトが自分で needs-human にするとき、理由を Issue か PR にコメントする。
# 形はスキルのコメント（implement-issue・address-review-comment）にそろえ、1行目で手書きのコメントと見分ける。
# 使い方: comment_stop <issue|pr> <番号> <止まった理由> <決めてほしいこと>
comment_stop() {
	local kind="$1" target="$2" reason="$3" decide="$4"
	printf '自動実行で止まりました（make auto）\n\n## 止まった理由\n\n%s\n\n## 決めてほしいこと\n\n%s\n' "$reason" "$decide" |
		gh "$kind" comment "$target" --body-file - >/dev/null
}

# --- 1件ずつ処理する -------------------------------------------------------

stuck="$(gh issue list --state open --label in-progress --json number --jq '.[].number' | tr '\n' ' ')"
if [[ -n "${stuck// /}" ]]; then
	echo "in-progress の Issue が残っています: ${stuck}" >&2
	echo "前の make auto が途中で止まったようです。どこまで進んだかを確かめて、in-progress を外してから実行し直してください。" >&2
	finish 1
fi

count=0
while true; do
	if [[ -n "$limit" && "$count" -ge "$limit" ]]; then
		echo "LIMIT（${limit} 件）に達しました。" >&2
		break
	fi

	number="$(next_issue)"
	if [[ -z "$number" ]]; then
		echo "取れる Issue はもうありません。" >&2
		break
	fi
	count=$((count + 1))

	# auto-merge は、書いたセッションを動かす前に読んでおく。書いたセッションは gh issue edit を使えるので、
	# あとから auto-merge を付けても、マージの判定に効かないようにするため。
	if gh issue view "$number" --json labels --jq '.labels[].name' | grep -qxF auto-merge; then
		auto_merge="yes"
	else
		auto_merge=""
	fi
	gh issue edit "$number" --remove-label ready --add-label in-progress >/dev/null

	# 実装して PR を出す。
	if run_skill "$number" implement "implement-issue スキルで、Issue #${number} を実装してください。"; then
		result="$(jq -c . "$RESULT_FILE")"
	else
		add_result "#${number}: implement-issue の結果を受け取れずに止まりました（in-progress のまま）"
		finish 1
	fi
	status="$(jq -r '.status' <<<"$result")"
	case "$status" in
	中断)
		# 手元の状態の問題なので、Issue は詰め直さずに、そのまま次の実行で取れるよう戻す。
		gh issue edit "$number" --remove-label in-progress --add-label ready >/dev/null
		add_result "#${number}: 中断（$(jq -r '.summary' <<<"$result")）"
		finish 1
		;;
	needs-human)
		gh issue edit "$number" --remove-label in-progress >/dev/null
		add_result "#${number}: needs-human（implement-issue）"
		continue
		;;
	esac

	# スキルから受け取った PR の URL は、その Issue を閉じる PR であることを確かめてから使う。
	pr_url="$(jq -r '.pr_url // ""' <<<"$result")"
	pr_number=""
	if [[ -n "$pr_url" ]]; then
		# GitHub は closingIssuesReferences を PR の本文から作る。本文の書き方がずれても見落とさないよう、
		# 本文の「Closes #<番号>」も見る。
		pr_number="$(gh pr view "$pr_url" --json number,state,body,closingIssuesReferences 2>/dev/null |
			jq -r --argjson issue "$number" '
				select(.state == "OPEN")
				| select(([.closingIssuesReferences[].number] | index($issue))
					or (.body | test("(?i)\\b(close[sd]?|fix(e[sd])?|resolve[sd]?) #\($issue)\\b")))
				| .number' || true)"
	fi
	if [[ -z "$pr_number" ]]; then
		comment_stop issue "$number" \
			"implement-issue は完了と報告したが、この Issue を閉じる開いた PR が見つからなかった（報告された PR: ${pr_url:-なし}）。PR の本文に Closes #${number} がないか、PR が出ていない。" \
			"PR を出し直すか本文に Closes #${number} を足したうえで、make auto で続けるか手で進めるかを決めてください。"
		gh issue edit "$number" --remove-label in-progress --add-label needs-human >/dev/null
		add_result "#${number}: 完了と報告されたが、この Issue を閉じる PR が見つからない（${pr_url:-URL なし}）"
		continue
	fi
	pr_url="$(gh pr view "$pr_number" --json url --jq '.url')"

	# レビューは1つの PR につき1回だけ。書いたセッションではなく、このスクリプトが呼ぶ。
	if ! make --no-print-directory review PR="$pr_url"; then
		add_result "#${number}: make review が失敗して止まりました（${pr_url}、in-progress のまま）"
		finish 1
	fi

	# レビューコメントに対応する。
	read_unresolved "$number" "$pr_number" "$pr_url"
	if [[ "$UNRESOLVED" -gt 0 ]]; then
		if run_skill "$number" address "address-review-comment スキルで、${pr_url} の未解決のレビューコメントに対応してください。"; then
			result="$(jq -c . "$RESULT_FILE")"
		else
			add_result "#${number}: address-review-comment の結果を受け取れずに止まりました（${pr_url}、in-progress のまま）"
			finish 1
		fi
		if [[ "$(jq -r '.status' <<<"$result")" == "中断" ]]; then
			# PR はもう出ているので、ready に戻すと実装し直しになる。in-progress のまま人に任せる。
			add_result "#${number}: address-review-comment が中断（${pr_url}、in-progress のまま。$(jq -r '.summary' <<<"$result")）"
			finish 1
		fi
	fi

	# 指摘にすべて対応できたか。
	read_unresolved "$number" "$pr_number" "$pr_url"
	if [[ "$UNRESOLVED" -gt 0 ]]; then
		gh pr edit "$pr_number" --add-label needs-human >/dev/null
		gh issue edit "$number" --remove-label in-progress >/dev/null
		add_result "#${number}: needs-human（未解決のレビューコメントが残った: ${pr_url}）"
		continue
	fi
	read_outside_findings "$number" "$pr_number" "$pr_url"
	if [[ -n "$OUTSIDE_FINDINGS" ]]; then
		comment_stop pr "$pr_number" \
			"code-reviewer のレビュー本文に「差分の外の指摘」がある。差分の外の指摘はスレッドにならないので、address-review-comment では対応できない。" \
			"レビュー本文の「差分の外の指摘」を読み、直すかどうかを決めてください。"
		gh pr edit "$pr_number" --add-label needs-human >/dev/null
		gh issue edit "$number" --remove-label in-progress >/dev/null
		add_result "#${number}: needs-human（レビュー本文に差分の外の指摘がある: ${pr_url}）"
		continue
	fi
	# コンフリクトしていれば、人がマージするだけの PR ではないので、ready-to-merge は付けない。
	# auto-merge でない PR も同じ。
	mergeable="$(pr_mergeable "$pr_number")"
	if [[ "$mergeable" == "CONFLICTING" ]]; then
		comment_stop pr "$pr_number" \
			"レビューの指摘にはすべて対応したが、main とコンフリクトしている。make auto は rebase しない。" \
			"main を取り込んでコンフリクトを解消し、マージしてください。"
		gh pr edit "$pr_number" --add-label needs-human >/dev/null
		gh issue edit "$number" --remove-label in-progress >/dev/null
		add_result "#${number}: needs-human（コンフリクトしている: ${pr_url}）"
		continue
	fi
	gh pr edit "$pr_number" --add-label ready-to-merge >/dev/null

	# auto-merge の Issue だけ、自動でマージする。
	merged=""
	reason=""
	if [[ -z "$auto_merge" ]]; then
		reason="auto-merge が付いていない"
	elif gh pr view "$pr_number" --json body --jq '.body' | grep -qF '画面の確認はしていない'; then
		reason="画面の確認をしていない"
	elif [[ "$mergeable" != "MERGEABLE" ]]; then
		reason="マージできるか GitHub が判定できなかった"
	else
		head="$(gh pr view "$pr_number" --json headRefName --jq '.headRefName')"
		gh pr merge "$pr_number" --squash >/dev/null
		git switch -q main
		git pull -q --ff-only
		git branch -D "$head" >/dev/null 2>&1 || true
		merged="yes"
	fi

	gh issue edit "$number" --remove-label in-progress >/dev/null
	if [[ -n "$merged" ]]; then
		add_result "#${number}: マージした（${pr_url}）"
	else
		add_result "#${number}: ready-to-merge（${reason}: ${pr_url}）"
	fi
done

finish 0
