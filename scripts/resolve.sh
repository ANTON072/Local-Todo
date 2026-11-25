#!/usr/bin/env bash
# 修正をプッシュしたあとに、Copilot のレビューコメント1件へ修正コミットのリンクを返信し、
# そのスレッドを resolve する。
# 使い方: scripts/resolve.sh <コメントID>
set -euo pipefail

comment_id="${1:?使い方: make resolve COMMENT=<コメントID>}"
if [[ ! "$comment_id" =~ ^[0-9]+$ ]]; then
	echo "コメントIDは数字で指定してください: ${comment_id}" >&2
	exit 1
fi

comment="$(gh api "repos/{owner}/{repo}/pulls/comments/${comment_id}")"
pr_number="$(jq -r '.pull_request_url | split("/") | last' <<<"$comment")"
repo_url="$(gh repo view --json url --jq '.url')"
commit="$(git rev-parse HEAD)"

# 返信に手元の最新コミットへのリンクを書くので、それがコメントのついた PR の最新コミットと
# 同じであることを確かめる。別のブランチにいるときや、まだプッシュしていないときに、
# 修正の入っていない PR のスレッドを resolve しないため。
pr_head="$(gh api "repos/{owner}/{repo}/pulls/${pr_number}" --jq '.head.sha')"
if [[ "$commit" != "$pr_head" ]]; then
	echo "手元の最新コミット（${commit:0:7}）が PR #${pr_number} の最新コミット（${pr_head:0:7}）と違います。" >&2
	echo "PR のブランチにいるか、git push 済みかを確かめてください。" >&2
	exit 1
fi

# REST API ではスレッドを resolve できないので、GraphQL でコメントの属するスレッドを探す。
# PR は小さく切るのでスレッドが100件を超えることはなく、最初の100件だけを見る。
# 見つからないときに返信だけが残らないよう、返信より先に探す。
thread_id="$(
	gh api graphql \
		--field owner='{owner}' --field repo='{repo}' --field number="$pr_number" \
		--raw-field query='
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      reviewThreads(first: 100) {
        nodes { id comments(first: 1) { nodes { databaseId } } }
      }
    }
  }
}' \
		--jq ".data.repository.pullRequest.reviewThreads.nodes[]
			| select(.comments.nodes[0].databaseId == ${comment_id}) | .id"
)"
if [[ -z "$thread_id" ]]; then
	echo "コメント ${comment_id} のスレッドが見つかりません。スレッドの最初のコメントのIDを指定してください。" >&2
	exit 1
fi

gh api --method POST "repos/{owner}/{repo}/pulls/${pr_number}/comments/${comment_id}/replies" \
	--field body="修正しました: ${repo_url}/commit/${commit}" >/dev/null

gh api graphql --field threadId="$thread_id" --raw-field query='
mutation($threadId: ID!) {
  resolveReviewThread(input: {threadId: $threadId}) { thread { isResolved } }
}' >/dev/null

echo "コメント ${comment_id} に返信して resolve しました。"
