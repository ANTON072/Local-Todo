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

## データの場所とバックアップ

Todo は次のフォルダの `todos.json` に保存する。アプリはサンドボックスで動くので、`~/Library/Application Support` ではなく、アプリのコンテナの中になる。

```
~/Library/Containers/com.anton072.LocalTodo/Data/Library/Application Support/LocalTodo/
```

同じフォルダの `todos.backup.json` は、アプリを起動して最初に保存したときの、前回までの状態。アーカイブの完全削除などを間違えたときは、ここから戻せる。

1. アプリを終了する
2. Finder で上のフォルダを開き（Finder で ⇧⌘G を押してパスを貼る）、`todos.json` を別の場所に移す
3. `todos.backup.json` を複製し、名前を `todos.json` に変える
4. アプリを起動する

間違えたあとにアプリを起動し直して何か操作すると、その時点の状態でバックアップが取り直され、間違える前の状態は残らない。間違いに気づいたら、起動し直す前に戻すこと。

`todos.corrupt-<日時>.json` は、起動時に読めなかった `todos.json` を退避したもの。このときアプリは `todos.backup.json` から読み込んで起動する。
