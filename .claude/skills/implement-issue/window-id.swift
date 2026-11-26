// LocalTodo のウィンドウの ID を出す。`screencapture -l <ID>` でウィンドウだけを撮るために使う。
import CoreGraphics

let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
    as? [[String: Any]] ?? []
for window in windows
where window[kCGWindowOwnerName as String] as? String == "LocalTodo"
    && window[kCGWindowLayer as String] as? Int == 0
{
    print(window[kCGWindowNumber as String]!)
}
