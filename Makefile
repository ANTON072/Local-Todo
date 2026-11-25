.PHONY: re-review resolve

# Copilot のレビューコメント1件に対するコミット前の修正を、ローカルの Copilot CLI で再レビューする。
re-review:
	@scripts/re-review.sh "$(COMMENT)"

# 修正をプッシュしたあと、Copilot のレビューコメント1件に返信して resolve する。
resolve:
	@scripts/resolve.sh "$(COMMENT)"
