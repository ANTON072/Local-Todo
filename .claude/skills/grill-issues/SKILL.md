---
name: grill-issues
description: 実装する前の Issue を、ユーザーへの質問を重ねて詰める。決めたことを Issue の本文・ADR・CONTEXT.md に書き、ドキュメントだけの PR を出し、マージされたら Issue に ready ラベルを付ける。「Issue #<番号> を詰めたい」「この Issue を grilling して」のように、詰める Issue を渡されたときに使う。
disable-model-invocation: true
---

# Issue を詰める

実装する前の Issue を、ユーザーと詰めて `ready` にする。このスキルを呼ばれたこと自体を、ブランチの作成・コミット・push・PR の作成・Issue の本文の編集・ラベルの付け外しの依頼として扱う。

## なぜこの手順にするか

- **`ready` は「詰め終わって、決めたことが main に入った」という意味にする**：自動の実装は `ready` の Issue だけを取る。implement-issue のブランチも test-writer の worktree も main から切るので、main に入っていない ADR や CONTEXT.md は実装からもテストからも見えない。
- **ドキュメントは実装の PR に混ぜない**：1回で複数の Issue を詰めると、ADR がどの実装の PR に入るのかが決まらなくなる。また、決めたことが PR として残るので、あとから「いつ、なぜこう決めたか」をたどれる。
- **答えるのはユーザー**：Claude が自分で答えると、決めたのではなく推測したことになる。迷ったら質問を増やし、Claude の案で埋めない。

## 1. ブランチを切る

- 詰める Issue を、ラベルとコメントもあわせて読む。Issue が複数なら、すべて読む。ラベルは 2 で `needs-human` を、6 で外すかどうかを判断するのに使う。コメントには、自動の実装が止まった理由が書かれている。

  ```bash
  gh issue view <番号> --json title,body,labels,comments --jq '"\(.title)\nラベル：\([.labels[].name] | join(", "))\n\n\(.body)\n\n## コメント\n\(.comments | map("### \(.author.login)\n\(.body)") | join("\n\n"))"'
  ```
- コミット前の変更が残っていないことを確かめる（`git status --short`）。残っていれば、どうするかユーザーに聞く。
- main を最新にして、ブランチを切る：`git switch main`、`git pull --ff-only`、`git switch -c docs/<短い英語の名前>`
  - Issue が1件なら `docs/<番号>-<短い英語の名前>` にする。

## 2. 詰める

Skill ツールで `grilling` と `domain-modeling` を呼び、その手順に沿って詰める。

- 質問の範囲は、渡された Issue の「なぜやるか」「やること」「やらないこと」「先に終わっている必要がある Issue」。test-writer がテストを書ける程度まで、ケースと期待値がはっきりしているかを確かめる。
- Issue が `needs-human` なら、付いているコメント（自動の実装が止まった理由）から先に片づける。
- その Issue の途中までのブランチ（`feature/<番号>-*`）が、手元（`git branch --list 'feature/<番号>-*'`）か origin（`git ls-remote --heads origin 'refs/heads/feature/<番号>-*'`）に残っていれば、消すか手で仕上げるかをユーザーに聞く。残したまま `ready` にすると、implement-issue は自動実行のときに中断する。
- 自動でマージしてよいかをユーザーに聞く。よければ 6 で `auto-merge` を付ける。`make auto` は、レビューの指摘にすべて対応した PR を、`auto-merge` の Issue だけ自動でマージする。画面にかかわる Issue は、自動でマージしない（自動実行では画面を確かめないため、マージするときに人が確かめる）。
- 詰めている途中で、別の Issue に分けるべきことや、未決のまま残すことが出てきたら、ユーザーに確かめてから扱う。
  - 別の Issue にする：.github/ISSUE_TEMPLATE/task.md の形で作ってよいかユーザーに聞く。
  - 未決のまま残す：TODO.md に書く（CLAUDE.md の「ドキュメントの書き分け」）。その Issue は `ready` にしない。

## 3. 決めたことを書く

- **Issue の本文**：決めたことを反映する。`gh issue edit <番号> --body-file <ファイル>` で書き換える。書き換える前に、変える箇所をユーザーに見せる。
- **ADR・CONTEXT.md**：domain-modeling の手順に沿って書く。ADR の扱い（消さない、superseded の本文は書き換えない）は CLAUDE.md の「設計および実装方針」に従う。
- **変えてよいのはドキュメントだけ**：`docs/`、`CONTEXT.md`、`TODO.md` 以外のファイルを変える必要が出てきたら、止まってユーザーに聞く。Swift のファイルは変えない。

ADR・CONTEXT.md・TODO.md のどれも変わらなかったときは、4・5 を飛ばして 6 に進む（Issue の本文は GitHub の上ですでに反映されている）。

## 4. PR を出す

- 変えたファイルだけを `git add` してコミットする。メッセージは日本語で、1行目に何を決めたか、本文になぜそう決めたかを書く。末尾の署名は、セッションの指示に従う。
- `git push -u origin <ブランチ>` のあと、`gh pr create` で PR を出す。本文には次を書く。
  - 決めたこと
  - 対象の Issue：`Refs #<番号>` の形で1行ずつ。`Closes` は使わない（Issue は実装の PR で閉じる）
  - TODO.md に残した未決事項（あれば）
- PR を出したら、`make review PR=<PR の URL>` の実行をユーザーに案内する（CLAUDE.md の「コードレビュー」）。自分では実行しない。
- マージはユーザーがする。自分ではマージしない。

## 5. マージを待つ

ユーザーから「マージした」と言われたら、`gh pr view <PR の URL> --json state --jq .state` が `MERGED` であることを確かめる。`MERGED` でなければ、`ready` を付けずにユーザーに知らせる。

## 6. ready を付ける

- 対象の Issue ごとに、`ready` を付け、`needs-human` が付いていれば外す：`gh issue edit <番号> --add-label ready --remove-label needs-human`
  - `needs-human` が付いていなければ `--remove-label` は付けない。
  - `ready` か `needs-human` のラベルがリポジトリにまだなければ、`gh label create` で作ってよいかユーザーに聞く。
- TODO.md に未決事項を残した Issue には付けない。
- 2 で自動でマージしてよいと決めた Issue には、`--add-label auto-merge` もあわせて付ける。よくないと決めた Issue に `auto-merge` が付いていれば外す。

## 最後の報告

ユーザーには次を伝える。

- 詰めた Issue と、決めたことの主なもの
- 書き換えた Issue の本文、ADR、CONTEXT.md、TODO.md
- PR の URL と、`make review` の案内（4 のあと）
- `ready` を付けた Issue と、付けなかった Issue とその理由（6 のあと）
- `auto-merge` を付けた Issue（6 のあと）
