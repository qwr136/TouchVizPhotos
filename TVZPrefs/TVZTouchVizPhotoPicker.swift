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

/// SwiftUI Image(uiImage:) shows only a poster frame, so preview with UIImageView.
private final class TVZTouchVizAnimatedPreviewView: UIView {
    let imageView = UIImageView()

    override var intrinsicContentSize: CGSize {
        CGSize(width: 60, height: 60)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setImage(_ image: UIImage) {
        imageView.stopAnimating()
        imageView.animationImages = nil
        imageView.image = image
        guard let frames = image.images, frames.count > 1 else { return }
        imageView.animationImages = frames
        imageView.animationDuration = max(image.duration, 0.02)
        imageView.animationRepeatCount = 0
        imageView.startAnimating()
    }

    func stopPlayback() {
        imageView.stopAnimating()
        imageView.animationImages = nil
        imageView.image = nil
    }
}

struct TVZTouchVizImagePreview: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> TVZTouchVizAnimatedPreviewView {
        TVZTouchVizAnimatedPreviewView()
    }

    func updateUIView(_ view: TVZTouchVizAnimatedPreviewView, context: Context) {
        view.setImage(image)
    }

    static func dismantleUIView(_ view: TVZTouchVizAnimatedPreviewView, coordinator: ()) {
        view.stopPlayback()
    }
}
