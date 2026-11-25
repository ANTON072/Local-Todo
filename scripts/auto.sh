#!/usr/bin/env bash
# ready の Issue を、人の手を介さずに、実装 → PR → レビュー → レビュー対応 → マージまで進める。
# 判断の理由は docs/adr/0005-auto-run.md。
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

# --- claude -p -------------------------------------------------------------

schema='{
  "type": "object",
  "properties": {
    "status": {"type": "string", "enum": ["完了", "needs-human", "中断"]},
    "pr_url": {"type": "string"},
    "summary": {"type": "string"}
  },
  "required": ["status", "summary"]
}'

# 自動実行のときだけ効く許可。対話のセッションには効かせないので、.claude/settings.json には入れない。
# make は、スキルが使うものだけにする。make review と make auto は、書いたセッションには呼ばせない。
# 変数を展開するコマンド（echo "$X" など）は、許可に挙げても dontAsk では拒否される。スキルが自動実行かどうかを
# 見分けるのに使う printenv LOCAL_TODO_AUTO は、展開を含まないので許可できる。
allowed_tools=(
	"Read" "Edit" "Write" "Glob" "Grep" "Agent" "Skill"
	"Bash(printenv LOCAL_TODO_AUTO)"
	"Bash(echo:*)" "Bash(cat:*)" "Bash(ls:*)" "Bash(cp:*)" "Bash(diff:*)"
	"Bash(git:*)" "Bash(gh:*)"
	"Bash(make check)" "Bash(make format)" "Bash(make lint)" "Bash(make test)" "Bash(make generate)"
	"Bash(make re-review:*)" "Bash(make resolve:*)"
	"Bash(swift format:*)" "Bash(xcodegen:*)" "Bash(xcodebuild:*)"
)

# スキルを自動実行で呼び、結果の JSON（status・pr_url・summary）を標準出力に出す。
# 受け取れなかったときは 1 を返す。
run_skill() {
	local number="$1" step="$2" prompt="$3" log result
	log="${log_dir}/$(date +%Y%m%d-%H%M%S)-${number}-${step}.json"
	echo "Issue #${number}: ${step} を動かしています…（ログ: ${log}）" >&2
	# --allowedTools は複数の値を取るので、プロンプトは標準入力から渡す。
	if ! LOCAL_TODO_AUTO=1 claude -p --no-session-persistence \
		--output-format json --json-schema "$schema" \
		--permission-mode dontAsk \
		--allowedTools "${allowed_tools[@]}" \
		<<<"$prompt" >"$log"; then
		echo "Issue #${number}: ${step} の claude -p が失敗しました。" >&2
		return 1
	fi
	# 拒否された操作があれば、足りない許可に気づけるよう知らせる。
	jq -r '.permission_denials[]? | "注意: 拒否されました: \(.tool_input.command // .tool_name)"' "$log" >&2
	result="$(jq -c '.structured_output // empty' "$log")"
	if [[ -z "$result" ]]; then
		echo "Issue #${number}: ${step} の結果を受け取れませんでした。" >&2
		return 1
	fi
	echo "$result"
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

# code-reviewer の最新のレビュー本文に「差分の外の指摘」があれば 0 を返す。
# 差分の外の指摘はスレッドにならず、address-review-comment では対応できない。
has_outside_findings() {
	local pr_number="$1"
	gh api "repos/{owner}/{repo}/pulls/${pr_number}/reviews" \
		--jq '[.[] | select(.body | startswith("Claude Code（code-reviewer）のレビュー"))] | last | .body // ""' |
		grep -q '^## 差分の外の指摘'
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

	gh issue edit "$number" --remove-label ready --add-label in-progress >/dev/null

	# 実装して PR を出す。
	if ! result="$(run_skill "$number" implement "implement-issue スキルで、Issue #${number} を実装してください。")"; then
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
		gh issue edit "$number" --remove-label in-progress >/dev/null
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
	if [[ "$(unresolved_threads "$pr_number")" -gt 0 ]]; then
		if ! result="$(run_skill "$number" address "address-review-comment スキルで、${pr_url} の未解決のレビューコメントに対応してください。")"; then
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
	if [[ "$(unresolved_threads "$pr_number")" -gt 0 ]]; then
		gh pr edit "$pr_number" --add-label needs-human >/dev/null
		gh issue edit "$number" --remove-label in-progress >/dev/null
		add_result "#${number}: needs-human（未解決のレビューコメントが残った: ${pr_url}）"
		continue
	fi
	if has_outside_findings "$pr_number"; then
		gh pr edit "$pr_number" --add-label needs-human >/dev/null
		gh issue edit "$number" --remove-label in-progress >/dev/null
		add_result "#${number}: needs-human（レビュー本文に差分の外の指摘がある: ${pr_url}）"
		continue
	fi
	gh pr edit "$pr_number" --add-label ready-to-merge >/dev/null

	# auto-merge の Issue だけ、自動でマージする。
	merged=""
	reason=""
	if ! gh issue view "$number" --json labels --jq '.labels[].name' | grep -qxF auto-merge; then
		reason="auto-merge が付いていない"
	elif gh pr view "$pr_number" --json body --jq '.body' | grep -qF '画面の確認はしていない'; then
		reason="画面の確認をしていない"
	else
		case "$(pr_mergeable "$pr_number")" in
		MERGEABLE)
			head="$(gh pr view "$pr_number" --json headRefName --jq '.headRefName')"
			gh pr merge "$pr_number" --squash >/dev/null
			git switch -q main
			git pull -q --ff-only
			git branch -D "$head" >/dev/null 2>&1 || true
			merged="yes"
			;;
		CONFLICTING)
			gh pr edit "$pr_number" --add-label needs-human >/dev/null
			reason="コンフリクトしている（needs-human）"
			;;
		*)
			reason="マージできるか GitHub が判定できなかった"
			;;
		esac
	fi

	gh issue edit "$number" --remove-label in-progress >/dev/null
	if [[ -n "$merged" ]]; then
		add_result "#${number}: マージした（${pr_url}）"
	else
		add_result "#${number}: ready-to-merge（${reason}: ${pr_url}）"
	fi
done

finish 0
