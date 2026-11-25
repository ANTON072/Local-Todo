import Foundation
import os

/// Todo の全件を JSON ファイル1つに読み書きする（DB を使わない理由は docs/adr/0003-json-file-storage.md）。
///
/// `load`・`scheduleSave`・`saveNow` はメインスレッドから呼ぶ。書き込みは直列のキュー1本に並べるので、
/// 古い内容の書き込みが新しい内容のあとに終わって上書きすることはない。
final class Persistence {
    /// 起動時にどこから読んだか。
    enum LoadSource: Equatable {
        /// todos.json から読んだ。
        case file
        /// todos.json が読めないかなかったので、todos.backup.json から読んだ。
        case backup
        /// どちらのファイルもなかった（初回起動）。0件で始める。
        case noFile
        /// ファイルはあったが、todos.json もバックアップも読めなかった。0件で始める。
        case unreadable
    }

    struct LoadResult {
        let todos: [Todo]
        let source: LoadSource
    }

    static let currentVersion = 1
    static let defaultSaveDelay: TimeInterval = 0.5

    let fileURL: URL
    let backupURL: URL

    private let directory: URL
    private let saveDelay: TimeInterval
    private let onSaveError: (Error) -> Void
    private let queue = DispatchQueue(label: "LocalTodo.Persistence")
    private let logger = Logger(subsystem: "LocalTodo", category: "Persistence")

    /// メインスレッドからだけ触る。
    private var pendingSave: DispatchWorkItem?
    /// キューの中からだけ触る。
    private var hasBackedUpThisLaunch = false

    /// - Parameters:
    ///   - directory: todos.json を置くフォルダ。なければ最初の保存で作る。
    ///   - saveDelay: `scheduleSave` から書き込みまでの待ち時間。
    ///   - onSaveError: 保存に失敗したときに、メインスレッドで呼ばれる。
    init(
        directory: URL,
        saveDelay: TimeInterval = Persistence.defaultSaveDelay,
        onSaveError: @escaping (Error) -> Void = { _ in }
    ) {
        self.directory = directory
        self.saveDelay = saveDelay
        self.onSaveError = onSaveError
        fileURL = directory.appendingPathComponent("todos.json")
        backupURL = directory.appendingPathComponent("todos.backup.json")
    }

    /// アプリで使う保存先。サンドボックスではアプリのコンテナの中の Application Support になる。
    static func applicationSupportDirectory() throws -> URL {
        try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("LocalTodo", isDirectory: true)
    }

    // MARK: - 読み込み

    func load() -> LoadResult {
        queue.sync {
            let fileManager = FileManager.default
            var fileWasUnreadable = false
            if fileManager.fileExists(atPath: fileURL.path) {
                do {
                    return LoadResult(todos: try Self.decode(Data(contentsOf: fileURL)), source: .file)
                } catch {
                    logger.error("todos.json を読めない: \(error.localizedDescription, privacy: .public)")
                    // 読めないファイルを、このあとの保存で上書きして失わないよう、名前を変えて残す
                    moveAsideUnreadableFile()
                    fileWasUnreadable = true
                }
            }
            // todos.json がないときもバックアップを見る。退避したあと保存する前に落ちた場合などに、
            // 0件で始めて最初の保存でバックアップを空にしてしまわないため。
            if fileManager.fileExists(atPath: backupURL.path) {
                do {
                    return LoadResult(todos: try Self.decode(Data(contentsOf: backupURL)), source: .backup)
                } catch {
                    logger.error("todos.backup.json を読めない: \(error.localizedDescription, privacy: .public)")
                    return LoadResult(todos: [], source: .unreadable)
                }
            }
            return LoadResult(todos: [], source: fileWasUnreadable ? .unreadable : .noFile)
        }
    }

    private func moveAsideUnreadableFile() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let destination = directory.appendingPathComponent("todos.corrupt-\(formatter.string(from: .now)).json")
        do {
            try FileManager.default.moveItem(at: fileURL, to: destination)
        } catch {
            logger.error("読めない todos.json を退避できない: \(error.localizedDescription, privacy: .public)")
            // 読めないファイルが残るので、最初の保存でそれをバックアップに上書きしないようにする
            hasBackedUpThisLaunch = true
        }
    }

    // MARK: - 保存

    /// 待ち時間のあとに保存する。待っている間にまた呼ばれたら、前の予約を取り消して入れ直す（まとめて1回にする）。
    func scheduleSave(_ todos: [Todo]) {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.write(todos)
        }
        pendingSave = work
        queue.asyncAfter(deadline: .now() + saveDelay, execute: work)
    }

    /// すぐに保存し、終わるまで待つ。アプリの終了時に使う。
    /// 予約中の保存は取り消し、実行中の書き込みがあればそれが終わってから最新の内容を書く。
    func saveNow(_ todos: [Todo]) {
        pendingSave?.cancel()
        pendingSave = nil
        queue.sync {
            write(todos)
        }
    }

    /// キューの中で呼ぶ。
    private func write(_ todos: [Todo]) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // バックアップは起動して最初の書き込みのときだけ取る。書くたびに取ると、バックアップが
            // 「0.5 秒前の状態」にしかならず、完全削除の誤操作にあとから気づいても戻せないため。
            if !hasBackedUpThisLaunch {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try Data(contentsOf: fileURL).write(to: backupURL, options: .atomic)
                }
                hasBackedUpThisLaunch = true
            }
            try Self.encode(todos).write(to: fileURL, options: .atomic)
        } catch {
            logger.error("保存できない: \(error.localizedDescription, privacy: .public)")
            DispatchQueue.main.async { [onSaveError] in
                onSaveError(error)
            }
        }
    }

    // MARK: - JSON

    private struct FileContents: Codable {
        let version: Int
        let todos: [Todo]
    }

    private struct VersionOnly: Decodable {
        let version: Int
    }

    struct UnsupportedVersionError: Error {
        let version: Int
    }

    private static let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    static func encode(_ todos: [Todo]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(dateStyle))
        }
        return try encoder.encode(FileContents(version: currentVersion, todos: todos))
    }

    static func decode(_ data: Data) throws -> [Todo] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            return try dateStyle.parse(try container.decode(String.self))
        }
        // 知らない版のファイルは、中身を読む前に弾く（読めないファイルと同じ扱いにする）
        let version = try decoder.decode(VersionOnly.self, from: data).version
        guard version == currentVersion else {
            throw UnsupportedVersionError(version: version)
        }
        return try decoder.decode(FileContents.self, from: data).todos
    }
}
