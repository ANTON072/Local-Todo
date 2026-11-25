#!/usr/bin/env bash
# PR についた Copilot のレビューコメント1件に対して、コミット前の修正を
# ローカルの Copilot CLI に再レビューさせる。結果を表示するだけで、PR には何も書かない。
# 使い方: scripts/re-review.sh <コメントID>
set -euo pipefail

comment_id="${1:?使い方: make re-review COMMENT=<コメントID>}"
if [[ ! "$comment_id" =~ ^[0-9]+$ ]]; then
	echo "コメントIDは数字で指定してください: ${comment_id}" >&2
	exit 1
fi

comment="$(gh api "repos/{owner}/{repo}/pulls/comments/${comment_id}")"
path="$(jq -r '.path' <<<"$comment")"
line="$(jq -r '.line // .original_line' <<<"$comment")"
body="$(jq -r '.body' <<<"$comment")"
diff_hunk="$(jq -r '.diff_hunk' <<<"$comment")"

# ステージ済みとまだステージしていない変更をまとめて見せる。
diff="$(git diff HEAD)"
if [[ -z "$diff" ]]; then
	echo "コミット前の変更がありません。指摘を直してから実行してください。" >&2
	exit 1
fi

# git diff HEAD は新しく作ったファイルを含まないので、知らせておく。
untracked="$(git ls-files --others --exclude-standard)"
if [[ -n "$untracked" ]]; then
	echo "注意: 次のファイルは git に追加されていないため、再レビューに含まれません。" >&2
	echo "含めるには git add -N <ファイル> を実行してください。" >&2
	echo "$untracked" >&2
	echo >&2
fi

prompt="$(
	cat <<EOF
あなたはコードレビュアーです。プルリクエストについた次のレビューコメントに対して、
下の差分の修正で指摘が解決したかだけを判断してください。指摘と関係のない点には触れないでください。

## レビューコメント（${path} の ${line} 行目）

${body}

## コメントがついた時点のコード

\`\`\`diff
${diff_hunk}
\`\`\`

## 今回の修正（コミット前の差分）

\`\`\`diff
${diff}
\`\`\`

## 答え方

1行目に「解決」か「未解決」のどちらかだけを書いてください。
2行目以降に、そう判断した理由を日本語で短く書いてください。未解決なら、何が足りないかも書いてください。
EOF
)"

# 再レビューではファイルを書き換えさせない。
copilot --silent --no-ask-user --deny-tool write --prompt "$prompt"
