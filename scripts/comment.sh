#!/usr/bin/env bash
# PR のレビューコメントを読む・返信する・未解決のものを挙げる。
# address-review-comment スキルが使う。make auto で動く書いたセッションには gh api を許可しないので
# （gh api を許すと、マージやスレッドの resolve もできてしまう。docs/adr/0005-auto-run.md）、
# スキルが gh api でしていたことを、決まった動きだけのこのスクリプトにまとめる。
# 使い方:
#   scripts/comment.sh show <コメントの URL か ID>          コメント1件の中身を出す
#   scripts/comment.sh reply <コメントの URL か ID> <ファイル>  コメントに、ファイルの中身で返信する
#   scripts/comment.sh unresolved <PR の URL か番号>         未解決のスレッドの最初のコメントの URL を出す
set -euo pipefail

usage() {
	echo "使い方: scripts/comment.sh show <コメント> | reply <コメント> <ファイル> | unresolved <PR>" >&2
	exit 1
}

# コメントの URL（…#discussion_r<数字> か …#r<数字>）と、数字の ID のどちらも受け付ける。
comment_id() {
	local ref="$1"
	if [[ "$ref" =~ \#(discussion_)?r([0-9]+)$ ]]; then
		echo "${BASH_REMATCH[2]}"
	elif [[ "$ref" =~ ^[0-9]+$ ]]; then
		echo "$ref"
	else
		echo "コメントの URL か、数字の ID を指定してください: ${ref}" >&2
		exit 1
	fi
}

command="${1:-}"
case "$command" in
show)
	[[ $# -eq 2 ]] || usage
	id="$(comment_id "$2")"
	gh api "repos/{owner}/{repo}/pulls/comments/${id}" \
		--jq '{user: .user.login, path, line, body, diff_hunk}'
	;;
reply)
	[[ $# -eq 3 ]] || usage
	id="$(comment_id "$2")"
	file="$3"
	if [[ ! -s "$file" ]]; then
		echo "返信の中身のファイルがないか、空です: ${file}" >&2
		exit 1
	fi
	pr_number="$(gh api "repos/{owner}/{repo}/pulls/comments/${id}" --jq '.pull_request_url | split("/") | last')"
	url="$(gh api --method POST "repos/{owner}/{repo}/pulls/${pr_number}/comments/${id}/replies" \
		--field body=@"$file" --jq '.html_url')"
	echo "コメント ${id} に返信しました: ${url}"
	;;
unresolved)
	[[ $# -eq 2 ]] || usage
	pr_number="$(gh pr view "$2" --json number --jq '.number')"
	# PR は小さく切るのでスレッドが100件を超えることはなく、最初の100件だけを見る（resolve.sh と同じ）。
	gh api graphql --field owner='{owner}' --field repo='{repo}' --field number="$pr_number" \
		--raw-field query='
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      reviewThreads(first: 100) { nodes { isResolved comments(first: 1) { nodes { url } } } }
    }
  }
}' --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved | not) | .comments.nodes[0].url'
	;;
*)
	usage
	;;
esac
