---
name: implement-issue
description: GitHub の Issue 1件を実装する。テストは実装より先に test-writer エージェントに別の worktree で書かせ、その間に実装を進め、make check を通して PR を出し、make review でレビューさせ、レビューコメントに対応するまでを行う。「この Issue を実装して <URL>」「Issue #<番号> を実装して」のように、実装する Issue を渡されたときに使う。
---

# Issue の実装

Issue 1件を、ブランチを切るところから、レビューコメントへの対応を終えるところまで進める。マージは人がする。このスキルを呼ばれたこと自体を、ブランチの作成・コミット・push・PR の作成・`make review` の実行・レビューコメントへの対応（返信と resolve を含む）の依頼として扱う。

## なぜこの手順にするか

- **テストを別のエージェントに、実装より先に書かせる**：実装したのと同じセッションでテストを書くと、実装を知っているために「このコードが通るケース」を書いてしまい、実装の見落としをテストも一緒に見落とす。
- **test-writer は別の worktree で動かす**：同じ作業ツリーだと、書きかけの実装を読んでしまうおそれがある。指示に頼らず、見えないようにする。
- **渡すのは Issue の番号だけ**：プロンプトに実装の案などを書くと、そこから実装の文脈が漏れる。Issue と決めごとは test-writer が自分で読む。
- **PR 全体のレビュー（`make review`）は1つの PR につき1回だけ**：レビュアーは別のプロセスで動くが、呼ぶのはこのセッションなので、気に入らないレビューをやり直せてしまう。それを決まりで防ぐ。直したあとの確かめは、コメントごとの `make re-review` に任せる（docs/adr/0006-one-skill-from-implementation-to-review.md）。

## 1. ブランチを切る

- Issue を読む：`gh issue view <番号> --json title,body --jq '"\(.title)\n\n\(.body)"'`
- 「先に終わっている必要がある Issue」が閉じているかを確かめる。閉じていなければ、進めてよいかユーザーに聞く。
- コミット前の変更を確かめる（`git status --short`）。
  - `docs/`・`CONTEXT.md`・`TODO.md` の変更は、Issue を詰めたとき（grill-with-docs）に書いたものとして、そのまま持っていく。この Issue を詰めたときのものか分からなければ、ユーザーに聞く。
  - それ以外の変更が残っていれば、どうするかユーザーに聞く。
- その Issue のブランチ（`feature/<番号>-*`）が、手元（`git branch --list 'feature/<番号>-*'`）にも origin（`git ls-remote --heads origin 'refs/heads/feature/<番号>-*'`）にもないことを確かめる。あれば、前に途中で止まった実装が残っているので、どうするかユーザーに聞く。そのブランチから続けると、test-writer の worktree が途中までの実装を含むコミットから切られてしまう。
- main を最新にして、ブランチを切る：`git switch main`、`git pull --ff-only`、`git switch -c feature/<番号>-<短い英語の名前>`
- 詰めたときのドキュメントの変更があれば、そのファイルだけを `git add` して、先にコミットする。メッセージの1行目は、何を決めたかにする。test-writer の worktree はコミット済みの状態から切られるので、コミットしないと、決めたことが test-writer から見えないため。

## 2. test-writer を呼ぶ

Issue の「やること」に `LocalTodoTests/` のテストファイルが挙がっているときだけ呼ぶ。

- Agent ツールで、`subagent_type: "test-writer"`、`isolation: "worktree"` を指定して呼ぶ。
- プロンプトは「Issue #<番号> のテストを書いてください。」だけにする。実装の案、型の中身、注意点などを付け足さない。
- フォーク（`subagent_type: "fork"`）は使わない。会話を引き継ぐので、別のセッションにする意味がなくなる。
- worktree は、呼んだ時点のコミットから切られる。実装は、test-writer を呼んだあとまでコミットしない。

テストファイルが挙がっていなければ呼ばない。PR の本文に「テストの対象なし」と書く。実装の途中で、テストを書くべきロジックが出てきたら、止まってユーザーに聞く。

## 3. 並行して実装する

- test-writer がテストを書いている間に、Issue の「やること」に沿って実装を進める。まだコミットしない。
- test-writer の結果を待たずに、実装を見てテストを自分で書かない。テストは test-writer の分だけにする。

## 4. test-writer の報告を読む

報告には、ケースの一覧、推測で決めた名前、Issue の曖昧なところが書かれている。

- 曖昧なところが挙がっていれば、ユーザーに確かめる。決まった内容が Issue と違えば、Issue の本文も直してよいかユーザーに聞く。
- 推測で決めた名前は、5・6 で実装と合わせるときの手がかりにする。

## 5. テストを取り込む

Agent ツールの結果に、test-writer の worktree のパスとブランチが出る。test-writer はコミットしないので、テストは worktree の中にコミット前の変更として残っている。ブランチからは取り込めない（`git checkout <ブランチ> -- <パス>` では何も取れない）。

次の順に進める。片づけは必ず最後にする。先に消すと、何が変わっていたかを確かめられなくなる。

1. **確かめる**：`git -C <worktree のパス> status --porcelain --untracked-files=all` で、変わったファイルを見る。`LocalTodoTests/` 以外のファイルが変わっていたら、取り込まずにユーザーに知らせて止まる（test-writer の決まりに反しているため）。worktree は片づけずに残しておく。
2. **取り込む**：`LocalTodoTests/` の中の、追加・変更されたファイルを、worktree のパスからこちらの同じ場所にコピーする：`cp <worktree のパス>/LocalTodoTests/<ファイル> LocalTodoTests/`。worktree は、こちらのブランチの同じコミットから切られているので、既存のテストファイルもファイルごとコピーしてよい。
3. **取り込めたことを確かめる**：1 で見たファイルごとに `diff <worktree のパス>/LocalTodoTests/<ファイル> LocalTodoTests/<ファイル>` を実行し、何も出ないことを確かめる。`git status --short LocalTodoTests/` にも、そのファイルがすべて出ていることを確かめる。
4. **片づける**：worktree にはコミット前の変更が残っているので、`git worktree remove` は `--force` を付けないと失敗する。`git worktree remove --force <worktree のパス>` で消し、`git branch -D <worktree のブランチ>` を実行する。

## 6. テストと実装を合わせる

- ビルドを通すための直しだけはしてよい：型・メソッド・引数・エラーの型の名前、テストのヘルパーの呼び方など。
- 何を確かめるか（ケースと期待値）は変えない。ケースを消す、期待値を変える、境目をずらす必要があると思ったら、止まってユーザーに聞く。テストが Issue と食い違っているのか、実装が間違っているのかは、ユーザーが決める。
- テストに合わせて実装を直すのはかまわない。
- テストを直したら、何をどう直したかを控えておく（8 で PR の本文に書く）。

## 7. make check

```bash
make check
```

フォーマット・リント・テストがすべて通るまで直す。画面にかかわる変更なら、アプリを起動して動きも確かめる。

## 8. PR を出す

- 変えたファイルだけを `git add` してコミットする。`git add -A` や `git add .` は使わない。test-writer の worktree はリポジトリの中（`.claude/worktrees/…`）に作られる。.gitignore に入れてあるが、まとめて追加すると、入れ忘れたときなどに埋め込みリポジトリとしてコミットされてしまう。
- メッセージは日本語で、1行目に何をしたか、本文になぜそうしたかを書き、`Closes #<番号>` を入れる。末尾の署名は、セッションの指示に従う。
- `git push -u origin <ブランチ>` のあと、`gh pr create` で PR を出す。本文には次を書く。
  - `Closes #<番号>`（1行目）。GitHub は、PR がどの Issue を閉じるか（`closingIssuesReferences`）を PR の本文から読む。コミットメッセージに書くだけでは読まれず、`make review` もこれで Issue を見つけるため
  - やったこと
  - テストを書いたのは test-writer であること。テストの対象がなければ「テストの対象なし」
  - テストの名前を直したときは、何をどう直したか（code-reviewer が、ケースや期待値を変えていないか確かめられるように）
  - Issue の決めごとから外れた点

## 9. レビューさせる

```bash
make review PR=<PR の URL>
```

- 1つの PR につき1回だけ呼ぶ（「なぜこの手順にするか」）。もう一度呼んでよいのは、失敗してレビューが投稿されなかったときだけ。
- 指摘が0件なら、11 に進む。

## 10. レビューに対応する

### スレッドになった指摘

- 未解決のスレッドの、最初のコメントの URL を出す：`make unresolved PR=<PR の URL>`
- 1件ずつ、Skill ツールで address-review-comment を呼び、その手順を最後まで回してから次に進む。直さないと決めたコメントの扱いも、address-review-comment の手順に従う。

### 差分の外の指摘

`make review` は、差分に含まれない行への指摘をスレッドにできないので、レビュー本文の「差分の外の指摘」に書く。スレッドがないので、address-review-comment では扱えない。

- レビュー本文を読む：`gh pr view <PR の番号> --json reviews --jq '.reviews | map(select(.body | startswith("Claude Code（code-reviewer）のレビュー"))) | last | .body'`
- 「差分の外の指摘」があれば、1件ずつユーザーに見せ、直すかどうかを聞く。
- 直すと決めたものは、address-review-comment の 2・4〜6 と同じ流れ（直す → `make check` → コミット → push）で片づける。スレッドがないので、`make re-review` と `make resolve` は使わない。
- 直したら、どの指摘をどのコミットで直したかを、PR へのコメントで知らせる：`gh pr comment <PR の番号> --body-file <ファイル>`

## 11. 終わる

マージはしない。人が中身を見てマージする。

ユーザーには次を伝える。

- 何を実装したか
- test-writer が書いたテストの件数と、自分で足したケースの主なもの
- テストの名前を直したか、直したなら何を
- make check の結果（テストの件数）
- PR の URL
- レビューの指摘の件数と、それぞれをどうしたか（resolve した／直さずに残した／差分の外の指摘を直した）
- 残っている未解決のスレッドがあれば、その URL
