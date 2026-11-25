# コードの検査は swift-format だけで行い、CLAUDE.md の指示で実行する

フォーマットとリントには、Xcode のツールチェーンに入っている swift-format（`swift format`）だけを使う。SwiftLint は入れない。swift-format は1つのツールと1つの設定ファイル（`.swift-format`）でフォーマットとリントの両方ができ、追加でインストールするものもない。SwiftLint はリントの規則が多いが、フォーマッタとは規則が食い違うことがあり、2つの設定を管理することになる。1人で作る小さなアプリでは、swift-format の規則で足りる。足りなくなったら SwiftLint を考える。

CI はまだ置かない。リポジトリは private で、GitHub Actions の macOS ランナーは Linux の10倍の分数を消費する。PR ごとにビルドとテストを走らせると、無料枠をすぐに使い切る。CI を置くかどうかは TODO.md で未決事項として扱う。

検査の実行は、Claude Code の hook ではなく CLAUDE.md の指示で行う。この環境では hook を使えないためである。自動では実行されないので、Swift のファイルを編集したら PR を出す前に必ず実行する、と CLAUDE.md に書いておく。
