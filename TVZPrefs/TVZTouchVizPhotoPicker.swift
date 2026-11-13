import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Uses the system photo picker: selected assets only, no full-library permission.
struct TVZTouchVizPhotoPicker: UIViewControllerRepresentable {
    let onStart: () -> Void
    let onComplete: (Result<String, Error>?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: TVZTouchVizPhotoPicker
        init(parent: TVZTouchVizPhotoPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else {
                parent.onComplete(nil)
                return
            }
            parent.onStart()
            let identifier: String
            if provider.hasItemConformingToTypeIdentifier(UTType.gif.identifier) {
                identifier = UTType.gif.identifier
            } else if let supported = provider.registeredTypeIdentifiers.first(where: {
                UTType($0)?.conforms(to: .image) == true
            }) {
                identifier = supported
            } else {
                parent.onComplete(.failure(Self.importError()))
                return
            }
            // The URL is valid only during this callback. Copy/validate before returning.
            provider.loadFileRepresentation(forTypeIdentifier: identifier) { [self] url, error in
                let result: Result<String, Error>
                if let url = url, let name = Bundle.tvz_saveFillImage(withPath: url.path) {
                    result = .success(name)
                } else {
                    result = .failure(error ?? Self.importError())
                }
                DispatchQueue.main.async { self.parent.onComplete(result) }
            }
        }

        private static func importError() -> NSError {
            NSError(domain: "TouchViz.PhotoImport", code: 1, userInfo: [
                NSLocalizedDescriptionKey: NSLocalizedString(
                    "The image could not be imported. Use a complete image up to 12 MB. GIF supports up to 120 frames and a 60-second loop; simplify large GIFs and try again.",
                    bundle: Bundle.tvz_support, comment: "")
            ])
        }
    }
}

/// Uses native SwiftUI image rendering so list-row recycling cannot clear its contents.
struct TVZTouchVizImagePreview: View {
    let imageName: String
    @State private var sourceImage: UIImage

    init(imageName: String) {
        self.imageName = imageName
        _sourceImage = State(initialValue: Bundle.tvz_fillImageNamed(imageName))
    }

    private var frames: [UIImage] {
        sourceImage.images ?? [sourceImage]
    }

    private var animationDuration: TimeInterval {
        frames.count > 1 && sourceImage.duration.isFinite && sourceImage.duration > 0 ? sourceImage.duration : 0
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05, paused: animationDuration == 0)) { timeline in
            Image(uiImage: frame(at: timeline.date))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 60, height: 60)
                .clipped()
        }
        .frame(width: 60, height: 60)
        .clipped()
        .onAppear(perform: tvz_reloadSelectedImage)
        .onChange(of: imageName) { _ in tvz_reloadSelectedImage() }
    }

    private func tvz_reloadSelectedImage() {
        sourceImage = Bundle.tvz_fillImageNamed(imageName)
    }

    private func frame(at date: Date) -> UIImage {
        guard animationDuration > 0 else { return frames.first ?? sourceImage }
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: animationDuration)
        let index = Int(phase / animationDuration * Double(frames.count))
        return frames[min(max(index, 0), frames.count - 1)]
    }
}
