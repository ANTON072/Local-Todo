---
status: superseded by ADR-0006
---

# ready の Issue は make auto で順に進め、レビューはスクリプトが呼ぶ

`ready` の Issue は、`make auto`（`scripts/auto.sh`）で1件ずつ、実装 → PR → レビュー → レビュー対応まで進める。1人で作るアプリで、Issue ごとに implement-issue を呼び、`make review` を打ち、コメントを1件ずつ渡す手間を省くためである。

完全に人の手を離すことはしない。組織の設定で `make`・`git push`・`git pull` などに確認が要り、画面なしの `claude -p` ではそれに答えられず、拒否されるだけになるため。スクリプトは手順ごとに対話の `claude` を開き、人はその場で確認に答え、終わったら `/exit` で閉じる。人に任せるのは確認に答えることだけにし、設計の判断は Issue を詰めるとき（grill-issues）に前倒しする。スキルは、決められないことが出ても聞かずに、`needs-human` を付けて次の Issue に進む。

- **`make review` はスクリプトが呼ぶ**：書いたセッション（implement-issue を動かす `claude`）には `make review` を許可しない。スクリプトが別のプロセスで呼ぶので、ADR-0003 の「書いたのとは別のセッションでレビューする」はそのまま守れる。書いたセッションが、気に入らないレビューをやり直すこともできない。
- **レビューは1つの PR につき1回**：直したあとの確かめは、コメントごとの `make re-review` に任せる。PR 全体をもう一度レビューすると、新しい指摘が出て終わらなくなるおそれがあるため。
- **`auto-merge` の Issue だけ自動でマージする**：マージをすべて人がすると、依存のある Issue が前の PR のマージ待ちで止まる。すべて自動でマージすると、自動実行では確かめない画面の変更が、確かめられないまま main に入る（CI もない）。そこで、自動でマージしてよいかを Issue を詰めるときに人が決め、`auto-merge` ラベルで残す。`auto-merge` があっても、PR の本文に「画面の確認はしていない」とあれば、マージせずに `ready-to-merge` で止める。
- **権限はスクリプトが渡す**：`claude` に `--allowedTools`・`--disallowedTools`・`--setting-sources project` を渡す。`.claude/settings.json` に入れると、対話のセッションにも同じ許可が効いてしまうため。`--setting-sources project` は、手元の `.claude/settings.local.json` やユーザーの設定の許可が足されないようにするため。

## Considered Options

- `claude -p --permission-mode dontAsk` で、人の手を完全に離す：組織の設定で確認が要るコマンドは拒否され、`make check` も `git push` もできない。組織の設定は `--allowedTools` より強い。
- 書いたセッションはコミットまでにし、`make check` や push を外のスクリプトが行う：Claude が確認なしに push できないようにしている組織の設定を、スクリプトで迂回することになる。
- `claude -p` のまま、`--permission-prompt-tool` で確認を受けるツールを作る：仕組みが大きくなる。
- 書いたセッションに `make review` を呼ばせる：別のプロセスで動くのでレビューの独立性は保てるが、書いた側がレビューをやり直せてしまう。
- Agent ツールのサブエージェントで code-reviewer を呼ぶ：プロンプトを書いたセッションが書くので、書いた側の文脈が入る。コマンドの制限や答えの形の強制も、`claude -p` より弱い。
- 前の PR のブランチから次のブランチを切る（スタック）：マージを待たずに進めるが、前の PR が直されるたびに、うしろのブランチを rebase し直すことになる。
- GitHub Actions で動かす：xcodebuild に macOS の runner が要り、高くつく（ADR-0003 と同じ理由）。

## Consequences

- Mac の前で、手で `make auto` を打って動かす。Issue 1件につき、確認に答え、`/exit` を2回打つ（実装とレビュー対応）。並行しては進めない。
- 対話の `claude` には `--json-schema` が使えないので、スキルは結果（`status`・`pr_url`・`summary`）を、スクリプトが `LOCAL_TODO_RESULT` で渡したファイルに書く。ファイルがなければ（途中で閉じたなど）、`in-progress` のまま止まる。
- `in-progress` が残っていれば、前の実行が途中で落ちたとみなし、何もせずに止まる。どこまで進んだかの判断は人に任せる。
- 書いたセッションにも `git push` や `gh issue edit` は許可するので、マージの関門は、書いたセッションが変えられないものに置く。main への直接の push は、GitHub のルールセット（`protect-main` の pull_request）が拒否する。`auto-merge` は、書いたセッションを動かす前にスクリプトが読んでおく。`gh pr merge` と `gh api` は拒否する。
- 変数を展開するコマンド（`echo "$X"` など）は、許可の一覧にあっても確認が出る。スキルは `printenv LOCAL_TODO_AUTO`・`printenv LOCAL_TODO_RESULT` で環境変数を読む。
