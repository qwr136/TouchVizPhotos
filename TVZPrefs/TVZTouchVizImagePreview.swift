import SwiftUI
import UIKit

/// Immutable input from the selected-material snapshot; no second image cache in the row.
struct TVZTouchVizImagePreview: View {
    private let frames: [UIImage]
    private let duration: TimeInterval

    init(image: UIImage?) {
        frames = image?.images ?? image.map { [$0] } ?? []
        let interval = image?.duration ?? 0
        duration = frames.count > 1 && interval.isFinite && interval > 0 ? interval : 0
    }

    var body: some View {
        Group {
            if frames.isEmpty {
                Image(systemName: "photo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(.secondary)
            } else if duration == 0 {
                Image(uiImage: frames[0])
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                TimelineView(.animation(minimumInterval: 0.05)) { timeline in
                    Image(uiImage: tvz_frame(at: timeline.date))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
        }
        .frame(width: 60, height: 60)
        .clipped()
        .accessibilityLabel(Text("Touch-Viz image preview"))
    }

    private func tvz_frame(at date: Date) -> UIImage {
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: duration)
        let index = Int(phase / duration * Double(frames.count))
        return frames[min(max(index, 0), frames.count - 1)]
    }
}
