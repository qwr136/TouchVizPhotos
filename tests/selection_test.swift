import Combine
import Foundation

@main
struct TVZTouchVizSelectionTests {
    static func main() {
        let images = ["default.png": 0, "emoji-a.png": 1, "photo-a.png": 2,
                      "animated.gif": 3, "emoji-a-again.png": 4, "photo-b.png": 5]
        var writes: [(String, String)] = []
        let model = TVZTouchVizSelection<Int>(name: "default.png", emoji: "", load: { images[$0] },
            persist: { writes.append(($0, $1)) })
        var observed: [(String, String, Int?)] = []
        let subscription = model.$current.sink { observed.append(($0.name, $0.emoji, $0.image)) }
        func check(_ name: String, _ emoji: String, _ value: Int) {
            precondition(model.current.name == name && model.current.emoji == emoji && model.current.image == value)
            precondition(observed.last?.0 == name && observed.last?.1 == emoji && observed.last?.2 == value)
        }
        check("default.png", "", 0)
        precondition(model.select("emoji-a.png", emoji: "😀")); check("emoji-a.png", "😀", 1)
        precondition(model.select("photo-a.png")); check("photo-a.png", "", 2)
        precondition(model.select("animated.gif")); check("animated.gif", "", 3)
        // Re-select the same Emoji that was used before a photo/GIF, once only.
        precondition(model.select("emoji-a-again.png", emoji: "😀")); check("emoji-a-again.png", "😀", 4)
        for _ in 0..<50 {
            precondition(model.select("photo-b.png")); check("photo-b.png", "", 5)
            precondition(model.select("animated.gif")); check("animated.gif", "", 3)
        }
        let oldWrites = writes.count, oldEvents = observed.count
        precondition(!model.select("damaged.gif")); check("animated.gif", "", 3)
        precondition(!model.select("")); check("animated.gif", "", 3)
        precondition(oldWrites == writes.count && oldEvents == observed.count)
        // A recreated settings page restores the last file/image together.
        let reopened = TVZTouchVizSelection<Int>(name: model.current.name, emoji: model.current.emoji,
                                               load: { images[$0] }, persist: { _,_ in })
        precondition(reopened.current.name == "animated.gif" && reopened.current.image == 3)
        model.restore("default.png", emoji: ""); check("default.png", "", 0)
        precondition(writes.last?.0 == "animated.gif") // Restore does not rewrite defaults.
        withExtendedLifetime(subscription) {}
        print("PASS production selection model: first-choice publication, Emoji/photo/GIF, repeated Emoji, 100 switches, invalid file and restoration")
    }
}
