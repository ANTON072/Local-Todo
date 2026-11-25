# Local Todo

## 設計および実装方針

- 基本的にコードベース自体を設計および仕様書とする。docs/ARCHITECTRE.md は初期実装時は利用するが、実装後は廃棄し、ドキュメントの二重管理を防ぐ。
- docs/ARCHITECTRE.md を廃棄する前に、コードベースから読み解けない判断（なぜそう作ったか）をADRかCONTEXT.mdに移す。
- コードベースから読み解けない事項はADRやCONTEXT.mdにまとめる。簡単な内容であればソースコードにコメントとして残す。
- ADRのファイルは削除しない。新しいADRで置き換えたときは、古いADRの先頭のstatusをsuperseded by ADR-XXXXに変えて残す。
- supersededのADRは本文を書き換えない。昔の判断とその理由の記録なので、今のコードと合わなくてよい。
- それ以外のADRは、コードベースから読み解ける記述を消すために本文を書き換えてよい。書き換えて本文に残す記述がなくなったADRは、ファイルを残してstatusをdeprecatedにする。

## ドキュメントの書き分け

- docs/PRD.md には「何を・なぜ作るか」だけを書く。「どう作るか」は docs/design かコードに書く。
- 未決事項はPRDに書かず、TODO.md に書く。
- 実装のタスクは GitHub の Issue に書き、本文は .github/ISSUE_TEMPLATE/task.md の形にする。1つの PR が5ファイル程度の変更で済む大きさに切る。

## Issue を詰める

実装する前の Issue は grill-issues スキルでユーザーと詰める。決めたことを Issue の本文・ADR・CONTEXT.md に書き、ドキュメントだけの PR がマージされたら、Issue に `ready` ラベルを付ける。`ready` は「詰め終わって、決めたことが main に入った」という意味で付ける。

## Issue の実装

Issue を実装するときは implement-issue スキルを使う。テストは実装より先に、test-writer エージェント（`.claude/agents/test-writer.md`）が別の worktree で書く。理由と手順はスキルに書いてある。

implement-issue と address-review-comment は、環境変数 `LOCAL_TODO_AUTO=1` があるとき（`make auto` から呼ばれたとき）を自動実行、それ以外を対話とする。自動実行のときは、ユーザーに聞く場面で聞かずに止まる。Issue や PR の中身の問題なら、理由をコメントして `needs-human` ラベルを付ける。手元の状態の問題なら、何もせずに中断する。

## コードの検査

Swift のファイルを編集したら、PR を出す前に `make check` を実行し、リントの指摘をなくしてテストを通す。hook では自動実行しないので、毎回自分で実行する（理由は docs/adr/0001-code-checks.md）。

`make check` はフォーマット → リント → テストの順に実行する。1つずつ実行するときは次を使う。

- フォーマット：`make format`（`swift format -i -r LocalTodo LocalTodoTests`）
- リント：`make lint`（`swift format lint --strict -r LocalTodo LocalTodoTests`。警告があっても失敗にする）
- テスト：`make test`（`xcodegen generate` で `LocalTodo.xcodeproj` を作り直してから `xcodebuild test -scheme LocalTodo -destination 'platform=macOS'`）

フォーマットの規則は `.swift-format` に書く。

## コードレビュー

PR のレビューは、手元の Claude Code（`.claude/agents/code-reviewer.md`）が、コードを書いたセッションとは別のセッションで行う（理由は docs/adr/0003-code-review-with-claude-code.md）。

- PR を出したら、`make review PR=<PR の URL>` の実行をユーザーに案内する。自分では実行しない。
- レビューコメントへの対応は、1件ずつ address-review-comment スキルで行う。修正の確認は `make re-review COMMENT=<コメントの URL>`、push したあとの返信と resolve は `make resolve COMMENT=<コメントの URL>` で行う。
- 自動実行のときは、`make review` の案内を出さない。`make review` は `make auto` が呼ぶ（理由は docs/adr/0005-auto-run.md）。address-review-comment は、PR の未解決のコメントをすべて1件ずつ回し、決められないコメントは返信して resolve せずに残す。

## 自動実行（make auto）

`make auto` は、`ready` の Issue を1件ずつ、実装 → PR → `make review` → レビュー対応まで進め、`auto-merge` の Issue はマージまで進める（理由は docs/adr/0005-auto-run.md）。`make auto LIMIT=<数>` で、手をつける Issue の数の上限を決める。

組織の設定で `make` や `git push` に確認が要るので、完全に人の手は離さない。`make auto` は手順ごとに対話の `claude` を開く。人はその場で確認に答え、スキルが「終わりました」と言ったら `/exit` で閉じる。スキルは設計の判断をその場で聞かず、決められなければ `needs-human` で止まる。

ラベルの意味：

- `ready`（Issue）：詰め終わった。実装してよい。grill-issues が付ける
- `auto-merge`（Issue）：レビューの指摘にすべて対応したら、自動でマージしてよい。画面にかかわる Issue には付けない。grill-issues が付ける
- `in-progress`（Issue）：`make auto` が処理中。`make auto` が付け外しする。残っていれば、前の実行が途中で落ちている
- `ready-to-merge`（PR）：レビューの指摘にすべて対応した。人がマージするだけ
- `needs-human`（Issue か PR）：自動では決められないことがある。理由はコメントに書いてある

## 用語

- CONTEXT.mdの用語を使う。Avoid に挙がった言葉（書類、配布物など）は使わない。

## 破ってはいけない制約

検討中
