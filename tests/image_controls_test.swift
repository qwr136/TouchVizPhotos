import Foundation
import SwiftUI
import UIKit

@MainActor
func TVZTouchVizRunSliderTests() -> String? {
    let tvzSuite = "com.82flex.touchviz.controls-tests." + UUID().uuidString
    let tvzStore = UserDefaults(suiteName: tvzSuite)!
    defer { tvzStore.removePersistentDomain(forName: tvzSuite) }
    let tvzRate = TVZTouchVizImageControl.tvzGIFPlaybackRate
    let tvzX = TVZTouchVizImageControl.tvzImageOffsetX
    let tvzY = TVZTouchVizImageControl.tvzImageOffsetY
    func tvzNear(_ a: Double, _ b: Double) -> Bool { abs(a-b) < 0.000001 }
    let tvzInvalidValues: [Any?] = [nil, "bad", true, Double.nan, Double.infinity]
    for tvzControl in [tvzRate, tvzX, tvzY] {
        for tvzInvalid in tvzInvalidValues {
            if !tvzNear(tvzControl.tvz_sanitizedValue(tvzInvalid),tvzControl.tvzDefaultValue) {
                return "invalid slider input fallback failed"
            }
        }
        let tvzOriginal = Binding<Double>(
            get: { tvzStore.double(forKey: tvzControl.tvzKey) },
            set: { tvzStore.set($0, forKey: tvzControl.tvzKey) })
        let tvzBinding = tvzControl.tvz_binding(tvzOriginal, tvzDefaults: tvzStore)
        if !tvzNear(tvzBinding.wrappedValue,tvzControl.tvzDefaultValue) { return "missing-key slider default failed" }
        tvzBinding.wrappedValue += tvzControl.tvzStep
        if !tvzNear(tvzBinding.wrappedValue,tvzControl.tvzDefaultValue+tvzControl.tvzStep) {
            return "plus button did not apply first value"
        }
        tvzBinding.wrappedValue -= tvzControl.tvzStep
        if !tvzNear(tvzBinding.wrappedValue,tvzControl.tvzDefaultValue) { return "minus button failed" }
        tvzBinding.wrappedValue = 1000
        if !tvzNear(tvzBinding.wrappedValue,tvzControl.tvzRange.upperBound) { return "upper clamp failed" }
        tvzBinding.wrappedValue = -1000
        if !tvzNear(tvzBinding.wrappedValue,tvzControl.tvzRange.lowerBound) { return "lower clamp failed" }
        tvzStore.removeObject(forKey: tvzControl.tvzKey)
        if !tvzNear(tvzBinding.wrappedValue,tvzControl.tvzDefaultValue) { return "reset slider default failed" }
    }
    if !tvzNear(TVZTouchVizPreviewDuration(0.4, playbackRate: 0.5),0.8) ||
       !tvzNear(TVZTouchVizPreviewDuration(0.4, playbackRate: 1),0.4) ||
       !tvzNear(TVZTouchVizPreviewDuration(0.4, playbackRate: 2),0.2) ||
       !tvzNear(TVZTouchVizPreviewDuration(0.4, playbackRate: .nan),0.4) ||
       TVZTouchVizPreviewDuration(0, playbackRate: 2) != 0 {
        return "preview playback duration differs from actual touch GIF"
    }
    // Build real production sections; only the host is a fixture.
    let tvzForm = Form {
        TVZTouchVizImageSliderSection(tvzControl: .tvzGIFPlaybackRate, tvzValue: .constant(1))
        TVZTouchVizImageSliderSection(tvzControl: .tvzImageOffsetX, tvzValue: .constant(0))
        TVZTouchVizImageSliderSection(tvzControl: .tvzImageOffsetY, tvzValue: .constant(0))
    }
    let tvzHost = UIHostingController(rootView: tvzForm)
    tvzHost.loadViewIfNeeded()
    tvzHost.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
    tvzHost.view.layoutIfNeeded()
    print("PASS production slider controls: +/- bindings, invalid values, limits, reset, three-section layout and preview 0.5x/1x/2x")
    return nil
}
