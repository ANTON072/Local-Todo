.PHONY: format lint test check generate re-review resolve

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

# Copilot のレビューコメント1件に対するコミット前の修正を、ローカルの Copilot CLI で再レビューする。
re-review:
	@scripts/re-review.sh "$(COMMENT)"

# 修正をプッシュしたあと、Copilot のレビューコメント1件に返信して resolve する。
resolve:
	@scripts/resolve.sh "$(COMMENT)"
