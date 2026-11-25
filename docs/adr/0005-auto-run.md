# ready の Issue は make auto で自動実行し、レビューはスクリプトが呼ぶ

`ready` の Issue は、`make auto`（`scripts/auto.sh`）で、人の手を介さずに実装 → PR → レビュー → レビュー対応まで進める。1人で作るアプリで、Issue ごとに implement-issue を呼び、`make review` を打ち、コメントを1件ずつ渡す手間を省くためである。人が決めることは、Issue を詰めるとき（grill-issues）に前倒しし、自動実行の途中では止まらない。決められないことが出たら、聞く代わりに `needs-human` を付けて次の Issue に進む。

- **`make review` はスクリプトが呼ぶ**：書いたセッション（implement-issue を動かす `claude -p`）には `make review` を許可しない。スクリプトが別のプロセスで呼ぶので、ADR-0003 の「書いたのとは別のセッションでレビューする」はそのまま守れる。書いたセッションが、気に入らないレビューをやり直すこともできない。
- **レビューは1つの PR につき1回**：直したあとの確かめは、コメントごとの `make re-review` に任せる。PR 全体をもう一度レビューすると、新しい指摘が出て終わらなくなるおそれがあるため。
- **`auto-merge` の Issue だけ自動でマージする**：マージをすべて人がすると、依存のある Issue が前の PR のマージ待ちで止まる。すべて自動でマージすると、自動実行では確かめない画面の変更が、確かめられないまま main に入る（CI もない）。そこで、自動でマージしてよいかを Issue を詰めるときに人が決め、`auto-merge` ラベルで残す。`auto-merge` があっても、PR の本文に「画面の確認はしていない」とあれば、マージせずに `ready-to-merge` で止める。
- **権限はスクリプトが渡す**：`claude -p` に `--permission-mode dontAsk --allowedTools …` を渡す。`.claude/settings.json` に入れると、対話のセッションにも同じ許可が効いてしまうため。

## Considered Options

- 書いたセッションに `make review` を呼ばせる：別のプロセスで動くのでレビューの独立性は保てるが、書いた側がレビューをやり直せてしまう。
- Agent ツールのサブエージェントで code-reviewer を呼ぶ：プロンプトを書いたセッションが書くので、書いた側の文脈が入る。コマンドの制限や答えの形の強制も、`claude -p` より弱い。
- 前の PR のブランチから次のブランチを切る（スタック）：マージを待たずに進めるが、前の PR が直されるたびに、うしろのブランチを rebase し直すことになる。
- GitHub Actions で動かす：xcodebuild に macOS の runner が要り、高くつく（ADR-0003 と同じ理由）。

## Consequences

- Mac の上で、手で `make auto` を打って動かす。並行しては進めない。
- `in-progress` が残っていれば、前の実行が途中で落ちたとみなし、何もせずに止まる。どこまで進んだかの判断は人に任せる。
- 書いたセッションにも `git push` や `gh issue edit` は許可するので、マージの関門は、書いたセッションが変えられないものに置く。main への直接の push は、GitHub のルールセット（`protect-main` の pull_request）が拒否する。`auto-merge` は、書いたセッションを動かす前にスクリプトが読んでおく。`gh pr merge` と `gh api` は許可しない。
- 許可していないコマンドは、聞かずに拒否される。変数を展開するコマンド（`echo "$X"` など）も拒否されるので、スキルは `printenv LOCAL_TODO_AUTO` で自動実行かどうかを見分ける。
