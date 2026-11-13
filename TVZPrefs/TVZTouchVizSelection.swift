import Combine

/// Publishes a whole selection together; a callback never reads back an older AppStorage value.
struct TVZTouchVizSelectionSnapshot<Image> {
    let name: String
    let emoji: String
    let image: Image?
}

final class TVZTouchVizSelection<Image>: ObservableObject {
    @Published private(set) var current: TVZTouchVizSelectionSnapshot<Image>
    private let load: (String) -> Image?
    private let persist: (String, String) -> Void

    init(name: String, emoji: String, load: @escaping (String) -> Image?,
         persist: @escaping (String, String) -> Void) {
        self.load = load
        self.persist = persist
        current = TVZTouchVizSelectionSnapshot(name: name, emoji: emoji, image: load(name))
    }

    @discardableResult
    func select(_ name: String, emoji: String = "") -> Bool {
        guard !name.isEmpty, let image = load(name) else { return false }
        persist(name, emoji)
        current = TVZTouchVizSelectionSnapshot(name: name, emoji: emoji, image: image)
        return true
    }

    func restore(_ name: String, emoji: String) {
        current = TVZTouchVizSelectionSnapshot(name: name, emoji: emoji, image: load(name))
    }
}
