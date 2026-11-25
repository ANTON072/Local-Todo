---
name: address-review-comment
description: PR のレビューコメント1件に対応する。修正し、make re-review で code-reviewer が「解決」と言うまで直し、make check、コミット、push、make resolve までを通して行う。「このコメントを対応して <URL>」「このレビューコメントに対応して」のように、PR のレビューコメントの URL（#discussion_r<数字>）を渡されたときに使う。
---

# レビューコメントへの対応

PR のレビューコメント1件を、修正から resolve まで通して片づける。このスキルを呼ばれたこと自体を、コミット・push・コメントへの返信と resolve の依頼として扱う。

コメントが複数あるときは、1件ずつこの手順を最後まで回してから次に進む。

## 自動実行のとき

最初に `echo "${LOCAL_TODO_AUTO:-}"` を実行する。`1` が出れば自動実行（`make auto` から呼ばれた）、それ以外は対話（ユーザーが呼んだ）とする。プロンプトの言葉では見分けない。たまたまその言葉を含む依頼で取り違えないため。

対話のときは、各手順に書いたとおりにユーザーに聞いて止まる。自動実行のときは答える人がいないので、ユーザーに聞く場面では、次のどちらかで止まる。どちらで止まるかは、各手順の「自動実行のとき」に書く。

- **needs-human**：指摘の中身の問題で、そのコメントだけ止まる。そのコメントに下の形で返信し（`gh api --method POST "repos/{owner}/{repo}/pulls/<PR の番号>/comments/<コメントID>/replies" --field body=@<ファイル>`）、resolve せずに残す。残りのコメントは続ける。直せる指摘まで止める理由はないため。
- **中断**：手元の状態の問題で止まる。PR には何もせずに終わる。`make auto` はそこで止まる。

返信の形。1行目は決まった書き方にして、手で書いたコメントと見分ける。

```
自動実行で止まりました（address-review-comment / 手順 <番号>）

## 止まった理由

## 決めてほしいこと

## 途中までの変更
（あれば。stash の名前）
```

自動実行のときは、PR の未解決のコメントをすべて、1件ずつこの手順で回す。未解決のコメントは、PR の未解決のスレッドの最初のコメントとして探す。

```bash
gh api graphql --field owner='{owner}' --field repo='{repo}' --field number=<PR の番号> --raw-field query='
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      reviewThreads(first: 100) { nodes { isResolved comments(first: 1) { nodes { url } } } }
    }
  }
}' --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved | not) | .comments.nodes[0].url'
```

すべて回し終えたら、needs-human で残したコメントが1件でもあれば、`gh pr edit <PR の番号> --add-label needs-human` で PR に `needs-human` を付ける。

## 0. コメントを読む

- URL の `#discussion_r` の後ろの数字がコメントID。`pull/<番号>` が PR の番号。
- 内容を読む：`gh api "repos/{owner}/{repo}/pulls/comments/<コメントID>" --jq '{user:.user.login,path,line,body,diff_hunk}'`
- 今のブランチが PR のブランチ（`gh pr view <番号> --json headRefName`）であることを確かめる。違えば、そのブランチに切り替えてよいかユーザーに聞く。
  - 自動実行のとき：コミット前の変更がないことを確かめてから、聞かずに PR のブランチに切り替えて（`git switch <ブランチ>`、`git pull --ff-only`）続ける。
- コミット前の変更が残っていないことを確かめる（`git status --short`）。残っていれば、どうするかユーザーに聞く。ほかの変更が混ざると、make re-review の差分に入ってしまうため。
  - 自動実行のとき：中断する。

## 1. 直すかどうかを決める

修正の前に、指摘が正しいかを、コード・CLAUDE.md・CONTEXT.md・docs/adr・Issue の決めごとと照らして判断する。

- 指摘が正しい：2 に進む。
- 指摘が決めごとと食い違う、または直さないほうがよいと考える：直さずに止まる。理由と選択肢（直す／理由を返して resolve する）をユーザーに示し、決めてもらう。このスキルの中で勝手に却下しない。
  - 自動実行のとき：needs-human で、このコメントを残す。返信の「止まった理由」に、直さないほうがよいと考えた理由を書く。

## 2. 直す

- 指摘を直す。挙動を変える修正なら、指摘の症状を再現するテストも足す。できれば、修正を外すとそのテストが落ちることも確かめる。
- 新しく作ったファイルは `git add -N <ファイル>` を実行しておく。make re-review は `git diff HEAD` を見るので、追加していないファイルは差分に入らない。
- まだコミットしない。

## 3. code-reviewer に再レビューさせる

```bash
make re-review COMMENT=<コメントの URL>
```

レビュアー（`.claude/agents/code-reviewer.md`）は、このセッションとは別の新しいセッションで動く。結果の1行目が「解決」か「未解決」になる。

- 解決：4 に進む。
- 未解決：理由を読む。
  - 理由が正しい：2 に戻って直し、もう一度 make re-review を実行する。
  - 理由が指摘の範囲を超えている、または 1 でユーザーと決めた方針（直さない部分）を未解決と言っている：ループを止め、結果をユーザーに見せて判断を仰ぐ。
    - 自動実行のとき：理由が指摘の範囲を超えているなら、needs-human で、このコメントを残す（下の「直しかけの変更」を先に行う）。
- 2 → 3 を3回くり返しても解決にならないときは、止めてユーザーに報告する。そのときは、何を直したかと、code-reviewer の最後の指摘を伝える。
  - 自動実行のとき：needs-human で、このコメントを残す（下の「直しかけの変更」を先に行う）。返信に、何を直したかと、code-reviewer の最後の指摘を書く。

**直しかけの変更**（自動実行のとき）：次のコメントに進めるよう、コミット前の修正を `git stash push --include-untracked -m "自動実行：コメント <コメントID> の途中までの修正"` に入れる。コミットすると、直しきれていない修正が PR に入ってしまうため。返信の「途中までの変更」に、この stash の名前を書く。

## 4. make check

```bash
make check
```

- フォーマットでファイルが書き換わるのは問題ない。
- リントの指摘やテストの失敗があれば直す。直した結果、3 で見せた差分から中身が変わったときは、3 に戻ってもう一度 make re-review を実行する。

## 5. コミット

- 変えたファイルだけを `git add` する。
- メッセージは日本語で、1行目に何を直したか、本文になぜそう直したかを書く（この指摘で何が起きていたか）。末尾の署名は、セッションの指示に従う。

## 6. push

```bash
git push
```

## 7. resolve

```bash
make resolve COMMENT=<コメントの URL>
```

コメントに修正コミットへのリンクを返信し、スレッドを resolve する。手元の最新コミットが PR の最新コミットと違うと失敗するので、push を済ませてから実行する。

## 最後の報告

自動実行のときは、1行目を次のどれかにし、続けてコメントごとの結果（resolve した／needs-human で残した）を書く。

- `完了`：すべてのコメントを resolve した
- `needs-human`：needs-human で残したコメントがある
- `中断`：手元の状態の問題で止まった

ユーザーには次を伝える。

- 指摘の内容と、どう直したか
- make re-review を何回回したか、最後の判定
- make check の結果（テストの件数）
- コミットのハッシュと、resolve したこと
