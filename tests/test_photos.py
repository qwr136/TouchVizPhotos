import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from tvz_source_checks import strip_comments

ROOT = Path(__file__).resolve().parents[1]

def source(name): return strip_comments((ROOT/name).read_text())

class TVZPhotoSourceContracts(unittest.TestCase):
    def test_original_identity_and_preferences(self):
        control = (ROOT/'layout/DEBIAN/control').read_text()
        self.assertIn('Package: com.82flex.touchvis\n', control)
        self.assertIn('Name: Touch-Viz\n', control)
        self.assertIn('@"com.82flex.touchviz"', source('TVZPrefs/TVZUserDefaults.mm'))
        self.assertNotIn('com.xiaofei', control)
        self.assertTrue((ROOT/'LICENSE').read_text().startswith('MIT License'))

    def test_original_emoji_and_other_effects_retained(self):
        view=source('TVZPrefs/TVZRootView.swift')
        for name in ('emojiPicker','selectedEmoji','useTrackingEffect','useQuickPathEffect','useMorphEffect','imageShouldAutoRotate'):
            self.assertIn(name,view)

    def test_file_picker_replaced_by_system_photos(self):
        view=source('TVZPrefs/TVZRootView.swift')
        picker=source('TVZPrefs/TVZTouchVizPhotoPicker.swift')
        self.assertNotIn('.fileImporter(',view)
        self.assertIn('TVZTouchVizPhotoPicker(onStart:',view)
        for code in ('PHPickerConfiguration()', 'configuration.filter = .images',
                     'configuration.selectionLimit = 1','configuration.preferredAssetRepresentationMode = .current',
                     'provider.hasItemConformingToTypeIdentifier(UTType.gif.identifier)',
                     'provider.loadFileRepresentation(', 'Bundle.tvz_saveFillImage(withPath: url.path)',
                     'DispatchQueue.main.async'):
            self.assertIn(code,picker)
        self.assertNotIn('loadObject(ofClass: UIImage',picker)
        self.assertNotIn('pngData()',picker)

    def test_failure_and_cancellation_keep_previous_image(self):
        view=source('TVZPrefs/TVZRootView.swift')
        tail=view[view.index('case .failure(let error):'):]
        failure=tail[:tail.index('.onAppear')]
        self.assertNotIn('imageFillName =',failure)
        self.assertIn('guard let result = result else { return }',view)
        self.assertIn('tvz_applySelectedImage(name)',view)
        self.assertNotIn('tvz_applySelectedImage',failure)
        picker=source('TVZPrefs/TVZTouchVizPhotoPicker.swift')
        self.assertIn('parent.onComplete(nil)',picker)
        self.assertIn('tvz_importErrorMessage',view)

    def test_preview_and_touch_consumer_are_animated(self):
        preview=source('TVZPrefs/TVZTouchVizImagePreview.swift')
        view=source('TVZPrefs/TVZRootView.swift')
        self.assertIn('struct TVZTouchVizImagePreview: View',preview)
        for code in ('private let tvzFrames: [UIImage]',
                     'private let tvzDuration: TimeInterval',
                     'TimelineView(.animation(minimumInterval: 0.05',
                     'Image(uiImage: tvz_frame(at: tvzTimeline.date))',
                     'else if tvzDuration == 0',
                     '.frame(width: 60, height: 60)', '.aspectRatio(contentMode: .fit)'):
            self.assertIn(code,preview)
        for obsolete in ('UIViewRepresentable','UIImageView','@State','onChange','onAppear'):
            self.assertNotIn(obsolete,preview)
        self.assertIn('TVZTouchVizImagePreview(',view)
        self.assertIn('image: fillImage,',view)
        self.assertIn('.id(imageFillName)',view)
        preview_body=view[view.index('var imageEffectPreview: some View {'):view.index('var imageEffectSection: some View {')]
        self.assertNotIn('if let fillImage',preview_body)
        self.assertIn('self.window && self.image.images.count > 1',source('LNTouchVisualizer/Private/LNTouchImageView.m'))
        factory=source('LNTouchVisualizer/Private/LNTouchImageFactory.m')
        self.assertIn('for (UIImage *frame in fill.images)',factory)
        self.assertIn('fillImage:frame',factory)
        self.assertIn('animatedImageWithImages:frames duration:fill.duration',factory)
        life=source('LNTouchVisualizer/Private/LNTouchImageView.m')
        self.assertIn('self.window && self.image.images.count > 1',life)
        self.assertIn('[self stopAnimating]',life)

    def test_material_callbacks_apply_the_new_selection_once(self):
        view=source('TVZPrefs/TVZRootView.swift')
        self.assertIn('@StateObject private var tvz_selection: TVZTouchVizSelection<UIImage>',view)
        self.assertIn('private var imageFillName: String { tvz_selection.current.name }',view)
        self.assertIn('private var fillImage: UIImage? { tvz_selection.current.image }',view)
        self.assertIn('selectedEmoji: tvz_emojiSelection',view)
        self.assertIn('tvz_applySelectedImage(name, emoji: emoji)',view)
        apply=view[view.index('private func tvz_applySelectedImage'):view.index('var resetSection: some View')]
        self.assertIn('tvz_selection.select(name, emoji: emoji ?? "")',apply)
        self.assertIn('transaction.disablesAnimations = true',apply)
        self.assertNotIn('reload()',apply)
        self.assertNotIn('asyncAfter',apply)
        self.assertNotIn('.onChange(of: selectedEmoji)',view)
        self.assertNotIn('@State private var sourceImage',source('TVZPrefs/TVZTouchVizImagePreview.swift'))
        persist=view[view.index('persist: { name, emoji in'):view.index('func reload()')]
        self.assertIn('Bundle.tvz_commitFillImage(named: name, emoji: emoji)',persist)
        bundle=source('TVZPrefs/NSBundle+TVZPrefs.mm')
        commit=bundle[bundle.index('+ (BOOL)tvz_commitFillImageNamed:'):bundle.index('+ (BOOL)tvz_pruneFillImagesAfterSelectingName:')]
        self.assertLess(commit.index('[defaults setObject:name'),commit.index('[defaults synchronize]'))
        self.assertLess(commit.index('[defaults synchronize]'),commit.index('[defaults endUpdates]'))
        ci=(ROOT/'.github/workflows/build.yml').read_text()
        self.assertIn('sh tests/run_selection_tests.sh',ci)
        self.assertIn('sh tests/run_preview_tests.sh',ci)
        simulator=(ROOT/'tests/run_preview_tests.sh').read_text()
        self.assertIn('TVZPrefs/TVZTouchVizImagePreview.swift tests/preview_test.swift',simulator)
        native=(ROOT/'tests/run_selection_tests.sh').read_text()
        self.assertIn('TVZPrefs/TVZTouchVizSelection.swift tests/selection_test.swift',native)

    def test_decoder_and_cache_use_actual_file_identity(self):
        bundle=source('TVZPrefs/NSBundle+TVZPrefs.mm')
        for code in ('[TVZTouchVizImageLoader imageAtPath:path]',
                     '[TVZTouchVizImageLoader imageAtPath:imagePath]',
                     '[tvz_cachedPath isEqualToString:imagePath]',
                     '[tvz_cachedAttributes isEqual:attributes]',
                     'copyItemAtPath:path toPath:imagePath'):
            self.assertIn(code,bundle)
        decoder=source('TVZPrefs/TVZTouchVizImageFrames.mm')
        for code in ('CGImageSourceGetType(source)','CGImageSourceCreateThumbnailAtIndex',
                     'TVZTouchVizPlanTimeline(delays','TVZTouchVizMaxFileBytes',
                     'TVZTouchVizMaxFrames','TVZTouchVizMaxDecodedBytes','kCGImageStatusComplete'):
            self.assertIn(code,decoder)

    def test_swift_compiler_uses_matching_public_sdk(self):
        ci=(ROOT/'.github/workflows/build.yml').read_text()
        self.assertIn('Link Xcode iOS SDK 18.5',ci)
        self.assertIn('xcode-version: \'16.4\'',ci)

    def test_control_center_device_stub_is_used(self):
        stub = ROOT/'CCTouchViz/Frameworks/ControlCenterUIKit.framework/ControlCenterUIKit.tbd'
        self.assertTrue(stub.exists())
        self.assertIn('platform:              ios', stub.read_text())
        make=(ROOT/'CCTouchViz/Makefile').read_text()
        self.assertIn('-FFrameworks',make)

    def test_ci_gates_build_and_real_decoder_before_release(self):
        ci=(ROOT/'.github/workflows/build.yml').read_text()
        self.assertIn('needs: test',ci)
        self.assertIn('sh tests/run_imageio_tests.sh',ci)
        self.assertLess(ci.index('tests/verify_deb.py'),ci.index('actions/upload-artifact'))
        for name in ('Makefile','TVZPrefs/Makefile','CCTouchViz/Makefile'):
            make=(ROOT/name).read_text()
            self.assertIn('iphone:clang:18.5:15.0',make)
            self.assertIn('ImageIO',make)

class TVZExecutablePolicy(unittest.TestCase):
    def test_production_timeline_c_policy(self):
        self.assertIsNotNone(shutil.which('cc'), 'A C compiler is required, not a skipped test')
        with tempfile.TemporaryDirectory() as directory:
            binary=Path(directory)/'timeline'
            subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror',str(ROOT/'tests/timeline_test.c'),'-lm','-o',str(binary)],check=True)
            output=subprocess.check_output([str(binary)],text=True)
            self.assertIn('PASS executable production',output)

if __name__=='__main__': unittest.main()
