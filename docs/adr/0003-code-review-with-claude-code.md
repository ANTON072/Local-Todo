---
status: accepted（初回のレビューを `make review` で行う部分だけ superseded by ADR-0012。再レビューは今も `make re-review`）
---
# コードレビューは手元の Claude Code で行い、PR への投稿はスクリプトが行う

PR のレビューには GitHub Copilot を使わず、Mac 上の Claude Code を `make review` から呼んで行う。Copilot のクレジットはほかのプロジェクトとも分け合っていて、PR ごとの自動レビューは1回で約100クレジットを使うため、月の途中で上限に届いた。レビューの再確認（`make re-review`）も Copilot CLI をやめ、同じ Claude Code のレビュアーを使う。

レビュアー（`.claude/agents/code-reviewer.md`）は、コードを書いたセッションとは別の新しいセッションで、`claude -p` で動かす。書いた側の文脈を持ち込まず、別の目で見るためである。レビュアーには `git show` などの読むためのコマンドだけを許し、指摘は JSON で返させる。PR への投稿は、その JSON を受け取ったスクリプトが `gh api` で行う。書き込みの権限をレビュアーに渡さずに済み、どの行にどう投稿するかもスクリプトの側で確実に決められる。

## Considered Options

- Copilot の自動レビューを続ける：クレジットの上限に届き、レビューが走らない PR が出た。
- CI（GitHub Actions）で Claude Code にレビューさせる：API キーの管理と Actions の分数が要る。1人で作るアプリでは、手元で走らせれば足りる。
- レビュアーに `gh` での投稿もさせる：レビュアーに PR への書き込み権限を渡すことになる。差分の外の行を指定して投稿に失敗したときの扱いも、レビュアー任せになる。
- 再レビューで、レビューしたときのセッションを `--resume` で続ける：PR ごとにセッションIDを覚えておく仕組みが要る。指摘1件と差分を見せれば判定できるので、毎回新しいセッションにした。

## Consequences

レビューはユーザーのアカウントから投稿されるので、承認や変更の要求はできず、種類は「コメント」だけになる。手で書いたコメントと見分けるため、レビュー本文の1行目に「Claude Code（code-reviewer）のレビュー」と書く。PR を出しただけではレビューは走らないので、PR を出したセッションが、そのあとに `make review` を呼ぶ（docs/adr/0006-one-skill-from-implementation-to-review.md）。
