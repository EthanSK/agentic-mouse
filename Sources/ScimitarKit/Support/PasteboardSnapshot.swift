#if canImport(AppKit)
import AppKit

/// An eager, in-memory copy of every pasteboard item representation.
///
/// A temporary paste lease can restore this snapshot only while it still owns
/// the pasteboard. Capturing the bytes eagerly avoids depending on an original
/// application's lazy data provider after its item has been replaced.
public struct PasteboardSnapshot {
    private typealias Item = [(NSPasteboard.PasteboardType, Data)]

    public let sourceChangeCount: Int
    private let items: [Item]

    public init(capturing pasteboard: NSPasteboard) {
        sourceChangeCount = pasteboard.changeCount
        items = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            }
        }
    }

    @discardableResult
    public func restore(to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        guard !items.isEmpty else { return true }
        return pasteboard.writeObjects(items.map { itemSnapshot in
            let item = NSPasteboardItem()
            for (type, data) in itemSnapshot {
                item.setData(data, forType: type)
            }
            return item
        })
    }
}
#endif
