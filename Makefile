.PHONY: format lint test check generate review re-review resolve comment reply unresolved auto

SWIFT_DIRS := LocalTodo LocalTodoTests

# Swift のファイルを .swift-format の規則で書き換える。
format:
	swift format -i -r $(SWIFT_DIRS)

# Swift のファイルが .swift-format の規則に合っているか調べる。指摘があれば失敗する。
lint:
	swift format lint --strict -r $(SWIFT_DIRS)

# project.yml から LocalTodo.xcodeproj を作り直してから、単体テストを実行する。
test: generate
	xcodebuild test -scheme LocalTodo -destination 'platform=macOS'

# PR を出す前に実行する。フォーマット → リント → テストの順に行う。
# 依存ターゲットに並べると make -j で同時に走るので、レシピの中で1つずつ呼ぶ。
check:
	@$(MAKE) --no-print-directory format
	@$(MAKE) --no-print-directory lint
	@$(MAKE) --no-print-directory test

# project.yml から LocalTodo.xcodeproj を生成する。
generate:
	xcodegen generate

# PR 全体を手元の Claude Code（code-reviewer）にレビューさせ、指摘を PR の行につけて投稿する。
# PR には URL か番号を渡す。
review:
	@scripts/review.sh "$(PR)"

# レビューコメント1件に対するコミット前の修正を、手元の Claude Code（code-reviewer）で再レビューする。
# COMMENT にはコメントの URL か ID を渡す。
re-review:
	@scripts/re-review.sh "$(COMMENT)"

# 修正をプッシュしたあと、レビューコメント1件に返信して resolve する。
resolve:
	@scripts/resolve.sh "$(COMMENT)"

# レビューコメント1件の中身を出す。COMMENT にはコメントの URL か ID を渡す。
comment:
	@scripts/comment.sh show "$(COMMENT)"

# レビューコメント1件に、BODY のファイルの中身で返信する（resolve はしない）。
reply:
	@scripts/comment.sh reply "$(COMMENT)" "$(BODY)"

# PR の未解決のスレッドの、最初のコメントの URL を出す。PR には URL か番号を渡す。
unresolved:
	@scripts/comment.sh unresolved "$(PR)"

# ready の Issue を1件ずつ、実装 → PR → レビュー → レビュー対応 → マージまで進める。
# 手順ごとに対話の claude が開くので、確認に答え、終わったら /exit で閉じる。
# LIMIT には、手をつける Issue の数の上限を渡す（省略すると、取れるだけ処理する）。
auto:
	@LIMIT="$(LIMIT)" scripts/auto.sh
