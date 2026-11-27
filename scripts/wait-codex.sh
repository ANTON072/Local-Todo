#!/usr/bin/env bash
# PR に投稿した「@codex review」への Codex のレビューが、つくまで待つ。
# 「@codex review」の投稿より後に、Codex の bot が投稿したレビューか通常コメントを、一定間隔で確かめる。
# 見つかったら結果を出して終わり、上限までに見つからなければ失敗して終わる（docs/adr/0012-first-review-by-codex.md）。
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

# 最後に「@codex review」と投稿した時刻。これより後の Codex の投稿を、今回のレビューとして扱う。
since="$(
	gh api --paginate "repos/{owner}/{repo}/issues/${number}/comments" \
		--jq '.[] | select(.body | test("@codex review")) | .created_at' | sort | tail -n 1
)"
if [[ -z "$since" ]]; then
	echo "PR #${number} に「@codex review」のコメントがありません。先に投稿してください。" >&2
	exit 1
fi

# Codex の bot の投稿だけを、since より後のものに絞る。
bot_filter='select(.user.type == "Bot" and (.user.login | test($login; "i")))'

echo "PR #${number} への Codex のレビューを待っています（${since} 以降、上限 ${timeout} 秒）…" >&2

waited=0
while :; do
	reviews="$(
		gh api --paginate "repos/{owner}/{repo}/pulls/${number}/reviews" |
			jq -s --arg login "$login_pattern" --arg since "$since" \
				"add | map(${bot_filter} | select(.submitted_at > \$since))"
	)"
	comments="$(
		gh api --paginate "repos/{owner}/{repo}/issues/${number}/comments" |
			jq -s --arg login "$login_pattern" --arg since "$since" \
				"add | map(${bot_filter} | select(.created_at > \$since))"
	)"
	if [[ "$(jq 'length' <<<"$reviews")" -gt 0 || "$(jq 'length' <<<"$comments")" -gt 0 ]]; then
		break
	fi
	if ((waited >= timeout)); then
		echo "時間切れ: ${timeout} 秒待っても、Codex のレビューがつきませんでした。" >&2
		exit 1
	fi
	sleep "$interval"
	waited=$((waited + interval))
done

# 行コメントの数。スレッドになった指摘は、address-review-comment で1件ずつ扱う。
inline_count="$(
	gh api --paginate "repos/{owner}/{repo}/pulls/${number}/comments" |
		jq -s --arg login "$login_pattern" --arg since "$since" \
			"add | map(${bot_filter} | select(.created_at > \$since)) | length"
)"

if [[ "$inline_count" -gt 0 ]]; then
	echo "結果: 指摘あり（行コメント ${inline_count} 件）"
	echo "未解決のスレッドは make unresolved PR=${number} で出せる。"
else
	echo "結果: 指摘なし（行コメントなし）"
fi

# スレッドにならない投稿（レビューの本文と通常コメント）は、中身をそのまま出す。
# ユーザーに見せ、直すかどうかを聞くため。
jq -r '.[] | select(.body != null and .body != "") | "--- レビューの本文（\(.user.login)）\n\(.body)"' <<<"$reviews"
jq -r '.[] | "--- 通常コメント（\(.user.login)）\n\(.body)"' <<<"$comments"
