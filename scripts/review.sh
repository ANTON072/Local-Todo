#!/usr/bin/env bash
# PR 全体を、手元の Claude Code（.claude/agents/code-reviewer.md）にレビューさせ、
# 指摘を PR のソースコードの行につけたレビューとして投稿する。
# レビュアーは読むだけで指摘を JSON で返し、投稿はこのスクリプトが行う（docs/adr/0003-code-review-with-claude-code.md）。
# 使い方: scripts/review.sh <PR の URL か番号>
# DRY_RUN=1 をつけると、投稿せずに投稿する内容を表示する。
set -euo pipefail

pr_ref="${1:?使い方: make review PR=<PR の URL か番号>}"
cd "$(git rev-parse --show-toplevel)"

pr="$(gh pr view "$pr_ref" --json number,title,body,headRefOid,closingIssuesReferences)"
number="$(jq -r '.number' <<<"$pr")"
title="$(jq -r '.title' <<<"$pr")"
pr_body="$(jq -r '.body' <<<"$pr")"
head="$(jq -r '.headRefOid' <<<"$pr")"

# レビュアーが git show <コミット>:<パス> で PR の時点のファイルを読めるよう、PR のコミットを取ってくる。
git fetch --quiet origin "pull/${number}/head"

diff="$(gh pr diff "$number")"

issues=""
for issue in $(jq -r '.closingIssuesReferences[].number' <<<"$pr"); do
	issue_text="$(gh issue view "$issue" --json title,body --jq '"\(.title)\n\n\(.body)"')"
	issues+="### Issue #${issue}: ${issue_text}"$'\n\n'
done
if [[ -z "$issues" ]]; then
	issues="（この PR が閉じる Issue はありません）"
fi

prompt="$(
	cat <<EOF
次のプルリクエストをレビューしてください。

- PR の最新コミット: ${head}
- ファイルを読むときは \`git show ${head}:<パス>\`、探すときは \`git grep <パターン> ${head}\` を使ってください。

## PR #${number}: ${title}

${pr_body}

## この PR が閉じる Issue

${issues}

## 差分

\`\`\`diff
${diff}
\`\`\`

## 答え方

- summary: レビュー全体のまとめを日本語で1〜3文。指摘がなければ、そう書いてください。
- findings: 指摘1件ごとに、ファイルのパス（リポジトリのルートからの相対パス）、変更後のファイルでの行番号、指摘の本文。
  行番号は、できるだけ差分に含まれる行（追加した行か、その前後に表示されている行）を選んでください。
EOF
)"

schema='{
  "type": "object",
  "properties": {
    "summary": {"type": "string"},
    "findings": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "path": {"type": "string"},
          "line": {"type": "integer"},
          "body": {"type": "string"}
        },
        "required": ["path", "line", "body"]
      }
    }
  },
  "required": ["summary", "findings"]
}'

echo "PR #${number} をレビューしています…" >&2

# --allowedTools は複数の値を取るので、プロンプトは標準入力から渡す。
result="$(
	claude -p --agent code-reviewer --no-session-persistence \
		--output-format json --json-schema "$schema" \
		--permission-mode dontAsk \
		--allowedTools "Bash(git show:*)" "Bash(git grep:*)" "Bash(git log:*)" "Bash(git diff:*)" \
		<<<"$prompt"
)"
# 読むためのコマンドが拒否されると、レビュアーは差分だけで判断する。気づけるように知らせる。
jq -r '.permission_denials[]? | "注意: レビュアーのコマンドが拒否されました: \(.tool_input.command // .tool_name)"' <<<"$result" >&2
review="$(jq -c '.structured_output // empty' <<<"$result")"
if [[ -z "$review" ]]; then
	echo "レビューの結果を受け取れませんでした。" >&2
	jq -r '.result // .' <<<"$result" >&2
	exit 1
fi

# GitHub では、差分に含まれる行（変更後のファイルの追加行と前後の行）にしか行のコメントをつけられない。
# 差分から「パス:行番号」の一覧を作り、外れた指摘はレビュー本文に回す。
commentable="$(
	awk '
		/^diff --git / { header = 1; path = ""; next }
		header && /^\+\+\+ / { path = ($0 == "+++ /dev/null") ? "" : substr($0, 7); next }
		/^@@ / {
			header = 0
			match($0, /\+[0-9]+/)
			line = substr($0, RSTART + 1, RLENGTH - 1) + 0
			next
		}
		header { next }
		path != "" && /^[ +]/ { print path ":" line; line++ }
	' <<<"$diff"
)"

payload="$(
	jq -n \
		--argjson review "$review" \
		--arg commentable "$commentable" \
		--arg commit "$head" '
		($commentable | split("\n") | map(select(. != ""))) as $lines
		| ($review.findings | map(select(("\(.path):\(.line)") as $key | $lines | index($key)))) as $inline
		| ($review.findings | map(select(("\(.path):\(.line)") as $key | $lines | index($key) | not))) as $outside
		| {
			commit_id: $commit,
			event: "COMMENT",
			body: (
				"Claude Code（code-reviewer）のレビュー\n\n\($review.summary)"
				+ (if ($outside | length) > 0
					then "\n\n## 差分の外の指摘\n\n" + ($outside | map("- `\(.path):\(.line)` \(.body)") | join("\n"))
					else "" end)
			),
			comments: ($inline | map({path, line, side: "RIGHT", body}))
		}'
)"

if [[ "${DRY_RUN:-}" == "1" ]]; then
	jq . <<<"$payload"
	exit 0
fi

url="$(gh api --method POST "repos/{owner}/{repo}/pulls/${number}/reviews" --input - --jq '.html_url' <<<"$payload")"
echo "指摘 $(jq '.findings | length' <<<"$review") 件のレビューを投稿しました: ${url}"
