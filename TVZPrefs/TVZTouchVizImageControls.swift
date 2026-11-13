import CoreFoundation
import SwiftUI

struct TVZTouchVizImageControl {
    let tvzKey: String
    let tvzDefaultValue: Double
    let tvzRange: ClosedRange<Double>
    let tvzStep: Double
    let tvzTitle: String
    let tvzFormat: String
    let tvzFooter: String

    static let tvzGIFPlaybackRate = TVZTouchVizImageControl(
        tvzKey: "tvzGIFPlaybackRate", tvzDefaultValue: 1,
        tvzRange: 0.5...5.0, tvzStep: 0.1,
        tvzTitle: "GIF Playback Speed", tvzFormat: "%.1f x",
        tvzFooter: "Adjusts GIF playback and the custom image preview; still images are unchanged."
    )

    static let tvzImageOffsetX = TVZTouchVizImageControl(
        tvzKey: "tvzImageOffsetX", tvzDefaultValue: 0,
        tvzRange: -100.0...100.0, tvzStep: 1,
        tvzTitle: "Image Horizontal Offset", tvzFormat: "%.0f pt",
        tvzFooter: "Negative moves left; positive moves right. Applies to touch images and image trails; the preview stays centered."
    )

    static let tvzImageOffsetY = TVZTouchVizImageControl(
        tvzKey: "tvzImageOffsetY", tvzDefaultValue: 0,
        tvzRange: -100.0...100.0, tvzStep: 1,
        tvzTitle: "Image Vertical Offset", tvzFormat: "%.0f pt",
        tvzFooter: "Negative moves up; positive moves down. Applies to touch images and image trails; the preview stays centered."
    )

    /// Validate the stored object before NSNumber coercion can turn malformed strings into zero.
    func tvz_sanitizedValue(_ tvzObject: Any?) -> Double {
        guard let tvzNumber = tvzObject as? NSNumber,
              CFGetTypeID(tvzNumber) != CFBooleanGetTypeID(),
              tvzNumber.doubleValue.isFinite else {
            return tvzDefaultValue
        }
        let tvzValue = min(max(tvzNumber.doubleValue, tvzRange.lowerBound), tvzRange.upperBound)
        return tvzValue == 0 ? 0 : tvzValue
    }

    func tvz_steppedValue(_ tvzValue: Double) -> Double {
        let tvzSafeValue = tvz_sanitizedValue(tvzValue)
        let tvzRoundedValue = (tvzSafeValue / tvzStep).rounded() * tvzStep
        return tvz_sanitizedValue(tvzRoundedValue)
    }

    func tvz_binding(_ tvzStoredValue: Binding<Double>,
                     tvzDefaults: UserDefaults = TVZUserDefaults.standard) -> Binding<Double> {
        Binding(
            get: {
                // Read the observed binding so edits and Reset invalidate the dependent views.
                _ = tvzStoredValue.wrappedValue
                return tvz_sanitizedValue(tvzDefaults.object(forKey: tvzKey))
            },
            set: { tvzValue in
                tvzStoredValue.wrappedValue = tvz_steppedValue(tvzValue)
            }
        )
    }
}

struct TVZTouchVizImageSliderSection: View {
    let tvzControl: TVZTouchVizImageControl
    @Binding private var tvzValue: Double

    init(tvzControl: TVZTouchVizImageControl, tvzValue: Binding<Double>) {
        self.tvzControl = tvzControl
        _tvzValue = tvzControl.tvz_binding(tvzValue)
    }

    var body: some View {
        Section {
            HStack(spacing: 12) {
                Button {
                    tvzValue -= tvzControl.tvzStep
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundColor(TVZ_COLOR)
                }
                .buttonStyle(PlainButtonStyle())
                Slider(value: $tvzValue, in: tvzControl.tvzRange, step: tvzControl.tvzStep)
                Button {
                    tvzValue += tvzControl.tvzStep
                } label: {
                    Image(systemName: "plus.circle")
                        .foregroundColor(TVZ_COLOR)
                }
                .buttonStyle(PlainButtonStyle())
            }
        } header: {
            HStack(alignment: .lastTextBaseline) {
                Text(NSLocalizedString(tvzControl.tvzTitle, bundle: Bundle.tvz_support, comment: ""))
                Spacer()
                Text(String(format: tvzControl.tvzFormat, tvzValue))
                    .font(.footnote.monospacedDigit())
                    .textCase(nil)
            }
        } footer: {
            Text(NSLocalizedString(tvzControl.tvzFooter, bundle: Bundle.tvz_support, comment: ""))
        }
    }
}
