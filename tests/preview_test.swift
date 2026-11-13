import Combine
import SwiftUI
import UIKit

private final class TVZPreviewTestDriver: ObservableObject {
    @Published var visible = true
}

private struct TVZPreviewTestRoot: View {
    @ObservedObject var selection: TVZTouchVizSelection<UIImage>
    @ObservedObject var driver: TVZPreviewTestDriver
    var body: some View {
        ZStack {
            Color.white
            if driver.visible {
                TVZTouchVizImagePreview(image: selection.current.image)
                    .id(selection.current.name)
            }
        }
        .ignoresSafeArea()
    }
}

@main
final class TVZPreviewTestApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Task { @MainActor in await runChecks() }
        return true
    }

    @MainActor private func runChecks() async {
        func solid(_ color: UIColor) -> UIImage {
            UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).image { context in
                color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
            }
        }
        let red = solid(.red), green = solid(.green), blue = solid(.blue)
        let gif = UIImage.animatedImage(with: [blue, blue], duration: 0.2)!
        let images = ["emoji-a": red, "photo-b": green, "gif-c": gif, "emoji-a-again": red]
        let selection = TVZTouchVizSelection<UIImage>(name: "emoji-a", emoji: "😀",
                                                     load: { images[$0] }, persist: { _,_ in })
        let driver = TVZPreviewTestDriver()
        let host = UIHostingController(rootView: TVZPreviewTestRoot(selection: selection, driver: driver))
        let newWindow = UIWindow(frame: UIScreen.main.bounds)
        window = newWindow
        newWindow.rootViewController = host
        newWindow.makeKeyAndVisible()
        // Allow SwiftUI's real display transaction to complete after each single selection.
        func settle() async { try? await Task.sleep(nanoseconds: 200_000_000) }
        await settle()
        var failure: String?
        func checkPixel(_ expected: Int, _ scenario: String) {
            guard failure == nil else { return }
            host.view.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let screenshot = UIGraphicsImageRenderer(bounds: host.view.bounds, format: format).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let bounds = host.view.bounds
            guard let center = screenshot.cgImage?.cropping(to: CGRect(x: bounds.midX, y: bounds.midY,
                                                                        width: 1, height: 1)) else {
                failure = scenario + ": screenshot unavailable"; return
            }
            var pixel = [UInt8](repeating: 0, count: 4)
            let ok = pixel.withUnsafeMutableBytes { bytes -> Bool in
                guard let context = CGContext(data: bytes.baseAddress, width: 1, height: 1,
                    bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
                context.draw(center, in: CGRect(x: 0, y: 0, width: 1, height: 1)); return true
            }
            if !ok || pixel[expected] < 200 || pixel[(expected + 1) % 3] > 80 || pixel[(expected + 2) % 3] > 80 {
                failure = scenario + ": wrong first-choice preview pixel " + pixel.description
            }
        }
        checkPixel(0, "initial Emoji")
        for (name, emoji, color) in [("photo-b", "", 1), ("gif-c", "", 2), ("emoji-a-again", "😀", 0)] {
            if !selection.select(name, emoji: emoji) { failure = "selection rejected: " + name }
            await settle(); checkPixel(color, "first select " + name)
        }
        // Remove/reinsert the row without changing the selected material.
        for i in 0..<10 {
            driver.visible = false; await settle()
            driver.visible = true; await settle(); checkPixel(0, "row reinsert \(i)")
        }
        let message = failure.map { "FAIL " + $0 } ?? "PASS production SwiftUI preview pixels: Emoji to photo to GIF to same Emoji, first selection and 10 row reinserts"
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("preview-result.txt")
        try? message.write(to: url, atomically: true, encoding: .utf8)
        print(message)
    }
}
