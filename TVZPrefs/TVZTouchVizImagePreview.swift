import SwiftUI
import UIKit

/// Returns zero for invalid durations so the preview can safely display a still frame.
func TVZTouchVizPreviewDuration(_ tvzOriginalDuration: TimeInterval,
                                playbackRate tvzPlaybackRate: Double = 1) -> TimeInterval {
    guard tvzOriginalDuration.isFinite, tvzOriginalDuration > 0 else { return 0 }
    let tvzRate = tvzPlaybackRate.isFinite ? min(max(tvzPlaybackRate, 0.5), 2.0) : 1.0
    let tvzAdjustedDuration = tvzOriginalDuration / tvzRate
    return tvzAdjustedDuration.isFinite && tvzAdjustedDuration > 0 ? tvzAdjustedDuration : 0
}

/// Immutable input from the selected-material snapshot; no second image cache in the row.
struct TVZTouchVizImagePreview: View {
    private let tvzFrames: [UIImage]
    private let tvzDuration: TimeInterval

    init(image tvzImage: UIImage?, playbackRate tvzPlaybackRate: Double = 1) {
        tvzFrames = tvzImage?.images ?? tvzImage.map { [$0] } ?? []
        tvzDuration = tvzFrames.count > 1
            ? TVZTouchVizPreviewDuration(tvzImage?.duration ?? 0, playbackRate: tvzPlaybackRate)
            : 0
    }

    var body: some View {
        Group {
            if tvzFrames.isEmpty {
                Image(systemName: "photo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(.secondary)
            } else if tvzDuration == 0 {
                Image(uiImage: tvzFrames[0])
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                TimelineView(.animation(minimumInterval: 0.05)) { tvzTimeline in
                    Image(uiImage: tvz_frame(at: tvzTimeline.date))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
        }
        .frame(width: 60, height: 60)
        .clipped()
        .accessibilityLabel(Text("Touch-Viz image preview"))
    }

    private func tvz_frame(at tvzDate: Date) -> UIImage {
        // Rate changes remap the reference-clock phase; phase continuity is not guaranteed.
        let tvzPhase = tvzDate.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: tvzDuration)
        let tvzIndex = Int(tvzPhase / tvzDuration * Double(tvzFrames.count))
        return tvzFrames[min(max(tvzIndex, 0), tvzFrames.count - 1)]
    }
}
