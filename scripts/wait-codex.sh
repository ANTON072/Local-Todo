#!/usr/bin/env bash
# PR に投稿した「@codex review」への Codex のレビューが、つくまで待つ。
# Codex は PR に「Codex Review Summary」のコメントを1つ作り、レビューが終わるとその中の状態を completed に書き換える。
# 「@codex review」の投稿より後に、このコメントが今の PR のコミットについて completed になるのを、一定間隔で確かめる。
# なったら結果を出して終わり、上限までにならなければ失敗して終わる（docs/adr/0012-first-review-by-codex.md）。
# 使い方: scripts/wait-codex.sh <PR の URL か番号>
# 環境変数:
#   WAIT_INTERVAL  確かめる間隔（秒）。既定は 60
#   WAIT_TIMEOUT   待つ上限（秒）。既定は 900（15分）
#   CODEX_LOGIN    Codex の bot のログイン名にあてはめる正規表現（大文字・小文字は区別しない）。既定は codex
set -euo pipefail

pr_ref="${1:?使い方: make wait-codex PR=<PR の URL か番号>}"
interval="${WAIT_INTERVAL:-60}"
timeout="${WAIT_TIMEOUT:-900}"
login_pattern="${CODEX_LOGIN:-codex}"

number="$(gh pr view "$pr_ref" --json number --jq '.number')"
head="$(gh pr view "$pr_ref" --json headRefOid --jq '.headRefOid')"

# 最後に人が「@codex review」と投稿した時刻。これより後の Codex の投稿を、今回のレビューとして扱う。
# Codex も完了時のコメントに「@codex review」と書くので、bot の投稿は除く。
since="$(
	gh api --paginate "repos/{owner}/{repo}/issues/${number}/comments" \
		--jq '.[] | select(.user.type != "Bot" and (.body | test("@codex review"))) | .created_at' | sort | tail -n 1
)"
if [[ -z "$since" ]]; then
	echo "PR #${number} に「@codex review」のコメントがありません。先に投稿してください。" >&2
	exit 1
fi

# Codex の bot の通常コメントを、since より後に作られたか更新されたものに絞る。
codex_comments() {
	gh api --paginate "repos/{owner}/{repo}/issues/${number}/comments" |
		jq -s --arg login "$login_pattern" --arg since "$since" \
			'add | map(select(.user.type == "Bot" and (.user.login | test($login; "i")) and .updated_at > $since))'
}

# サマリーのコメントに埋め込まれた状態（codex-review-state）を取り出す。
# 今のコミットについてレビューが終わっていれば、その状態の JSON を出す。
completed_state() {
	jq -c --arg head "$head" '
		map(select(.body | contains("codex-pull-request-review-summary")))
		| map(.body | capture("codex-review-state:v1 (?<state>\\{.*\\}) -->").state | fromjson)
		| map(select(.code_review.status == "completed" and .code_review.commit_sha == $head))
		| last // empty'
}

echo "PR #${number} への Codex のレビューを待っています（${since} 以降、上限 ${timeout} 秒）…" >&2

waited=0
while :; do
	comments="$(codex_comments)"
	state="$(completed_state <<<"$comments")"
	if [[ -n "$state" ]]; then
		break
	fi
	if ((waited >= timeout)); then
		echo "時間切れ: ${timeout} 秒待っても、Codex のレビューが終わりませんでした。" >&2
		exit 1
	fi
	sleep "$interval"
	waited=$((waited + interval))
done

# 行コメントの数。スレッドになった指摘は、address-review-comment で1件ずつ扱う。
inline_count="$(
	gh api --paginate "repos/{owner}/{repo}/pulls/${number}/comments" |
		jq -s --arg login "$login_pattern" --arg since "$since" \
			'add | map(select(.user.type == "Bot" and (.user.login | test($login; "i")) and .created_at > $since)) | length'
)"

if [[ "$(jq -r '.code_review.has_any_findings' <<<"$state")" == "true" || "$inline_count" -gt 0 ]]; then
	echo "結果: 指摘あり（行コメント ${inline_count} 件）"
	echo "未解決のスレッドは make unresolved PR=${number} で出せる。"
else
	echo "結果: 指摘なし"
fi

# スレッドにならない投稿は、中身をそのまま出す。ユーザーに見せ、直すかどうかを聞くため。
# サマリーと、指摘なしの受領コメント、環境の案内は、指摘ではないので除く。
jq -r '.[]
	| select(.body | contains("codex-pull-request-review-summary") or contains("codex-review-receipt") or contains("create an environment") | not)
	| "--- 通常コメント（\(.user.login)）\n\(.body)"' <<<"$comments"
