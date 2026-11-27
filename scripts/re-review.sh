#!/usr/bin/env bash
# PR についたレビューコメント1件に対して、コミット前の修正を、
# 手元の Claude Code（.claude/agents/code-reviewer.md）に再レビューさせる。
# セッションは毎回新しく作り、指摘1件と今回の差分だけを見せる。結果を表示するだけで、PR には何も書かない。
# 使い方: scripts/re-review.sh <コメントの URL か ID>
set -euo pipefail

comment_ref="${1:?使い方: make re-review COMMENT=<コメントの URL か ID>}"
# コメントの URL（…#discussion_r<数字> か …#r<数字>）と、数字の ID のどちらも受け付ける。
if [[ "$comment_ref" =~ \#(discussion_)?r([0-9]+)$ ]]; then
	comment_id="${BASH_REMATCH[2]}"
elif [[ "$comment_ref" =~ ^[0-9]+$ ]]; then
	comment_id="$comment_ref"
else
	echo "コメントの URL か、数字の ID を指定してください: ${comment_ref}" >&2
	exit 1
fi

# レビュアーは .claude/agents/ の定義を読み、リポジトリのルートでコマンドを実行する。
cd "$(git rev-parse --show-toplevel)"

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

- resolved: 指摘が解決していれば true、していなければ false。
- reason: そう判断した理由を日本語で短く。未解決なら、何が足りないかも書いてください。

修正はまだコミットしていません。修正後のファイル全体は、HEAD の版（\`git show HEAD:<パス>\`）に上の差分を当てたものです。
EOF
)"

schema='{
  "type": "object",
  "properties": {
    "resolved": {"type": "boolean"},
    "reason": {"type": "string"}
  },
  "required": ["resolved", "reason"]
}'

# --allowedTools は複数の値を取るので、プロンプトは標準入力から渡す。
result="$(
	claude -p --agent code-reviewer --no-session-persistence \
		--output-format json --json-schema "$schema" \
		--permission-mode dontAsk \
		--allowedTools "Bash(git show:*)" "Bash(git grep:*)" "Bash(git log:*)" "Bash(git diff:*)" \
		<<<"$prompt"
)"
answer="$(jq -c '.structured_output // empty' <<<"$result")"
if [[ -z "$answer" ]]; then
	echo "再レビューの結果を受け取れませんでした。" >&2
	jq -r '.result // .' <<<"$result" >&2
	exit 1
fi

# 1行目を「解決」か「未解決」にする（address-review-comment スキルがこの形で読む）。
jq -r 'if .resolved then "解決" else "未解決" end, .reason' <<<"$answer"
