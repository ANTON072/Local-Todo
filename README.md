# Local Todo

Macで動作する外部通信はしないTodoアプリケーション。

## 環境のセットアップ

macOS 14 以上の Mac が必要。

1. App Store から Xcode を入れて一度起動し、追加コンポーネントの導入と利用規約への同意を済ませる。
2. コマンドラインのツールが Xcode を使うように切り替える（パスワードを聞かれる）。

   ```bash
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   ```

   `xcodebuild -version` で Xcode のバージョンが出れば済んでいる。
3. XcodeGen を入れる。`LocalTodo.xcodeproj` は `project.yml` から生成するもので、リポジトリには入れていない。

   ```bash
   brew install xcodegen
   ```

4. リポジトリのルートで `LocalTodo.xcodeproj` を生成する。

   ```bash
   make generate
   ```

5. テストが通ることを確かめる。

   ```bash
   make test
   ```

アプリを起動するときは、`LocalTodo.xcodeproj` を Xcode で開いて実行（⌘R）する。`project.yml` を変えたら `make generate` で生成し直す。

## 開発で使うコマンド

| コマンド | 内容 |
|---|---|
| `make check` | フォーマット → リント → テストを順に実行する。PR を出す前に使う |
| `make format` | Swift のファイルを `.swift-format` の規則で書き換える |
| `make lint` | Swift のファイルが規則に合っているか調べる |
| `make test` | `LocalTodo.xcodeproj` を生成し直してから単体テストを実行する |
| `make generate` | `project.yml` から `LocalTodo.xcodeproj` を生成する |
