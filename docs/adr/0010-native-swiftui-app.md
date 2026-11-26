# macOS ネイティブアプリとして SwiftUI で作る

アプリは macOS ネイティブアプリとして SwiftUI で作り、SwiftUI でできない部分だけ AppKit を使う。このアプリが一番大事にするのは「きびきび動く」ことで、ネイティブアプリなら起動も操作も最速になるため。

## Considered Options

- Electron などの Web 技術のアプリ：起動も操作も重くなる。Mac で自分だけが使うので、ほかの OS でも動くことの利点がない。
