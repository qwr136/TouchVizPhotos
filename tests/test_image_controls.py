import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from tvz_source_checks import strip_comments

ROOT = Path(__file__).resolve().parents[1]
def code(path): return strip_comments((ROOT / path).read_text())

class TVZImageControlTests(unittest.TestCase):
    def test_actual_math_defaults_rate_axes_and_no_drift(self):
        self.assertIsNotNone(shutil.which('cc'))
        with tempfile.TemporaryDirectory() as temp:
            exe = Path(temp) / 'controls'
            subprocess.run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror',
                            str(ROOT/'tests/image_controls_math_test.c'), '-lm', '-o', str(exe)], check=True)
            self.assertIn('PASS production speed', subprocess.check_output([str(exe)], text=True))

    def test_three_original_style_sliders_follow_lift_scale(self):
        root = code('TVZPrefs/TVZRootView.swift')
        body = root[root.index('var mainBody: some View'):]
        order = ['liftScaleSection', 'tvzGIFPlaybackRateSection', 'tvzImageOffsetXSection',
                 'tvzImageOffsetYSection', 'effectsSection']
        self.assertEqual(sorted(body.index(x) for x in order), [body.index(x) for x in order])
        ui = code('TVZPrefs/TVZTouchVizImageControls.swift')
        for needle in ('"minus.circle"', '"plus.circle"', 'Slider(value: $tvzValue',
                       'HStack(spacing: 12)', '.footnote.monospacedDigit()',
                       'tvzRange: 0.5...2.0, tvzStep: 0.1', 'tvzRange: -100.0...100.0, tvzStep: 1'):
            self.assertIn(needle, ui)
        for key in ('tvzGIFPlaybackRate', 'tvzImageOffsetX', 'tvzImageOffsetY'):
            self.assertIn('@AppStorage("'+key+'"', root)
            self.assertIn('tvzKey: "'+key+'"', ui)
            self.assertIn('@"'+key+'"', code('TVZPrefs/TVZUserDefaults.mm'))
            self.assertIn('@"'+key+'"', code('LNTouchVisualizer/Private/TVZTouchVizImageControlConfig.h'))

    def test_configuration_runs_on_reload_not_touch_input(self):
        tweak = code('TouchViz.xm')
        self.assertIn('TVZTouchVizLoadImageControls([TVZUserDefaults standardUserDefaults], _gTouchConfig, _gRippleConfig)', tweak)
        win = code('LNTouchVisualizer/Private/LNTouchVisualizerWindow.m')
        self.assertNotIn('NSUserDefaults',win)
        self.assertNotIn('TVZUserDefaults',win)
        defaults = code('TVZPrefs/TVZUserDefaults.mm')
        notify = defaults[defaults.index('- (void)darwinNotify'):]
        self.assertLess(notify.index('[self synchronize]'), notify.index('notify_post'))

    def test_offset_keeps_raw_input_and_does_not_shift_brush(self):
        win = code('LNTouchVisualizer/Private/LNTouchVisualizerWindow.m')
        self.assertIn('touchView.tvzHasRawCenter ? touchView.tvzRawCenter : newCenter',win)
        self.assertIn('touchView.tvzRawCenter = newCenter',win)
        self.assertIn('rippleView.tvzRawCenter = newCenter',win)
        self.assertIn('config.fillImage != nil',win)
        self.assertIn('[self tvz_displayCenter:newCenter config:self.touchContactConfig coordinate:coordinateTransform]',win)
        self.assertIn('[self tvz_displayCenter:newCenter config:self.touchRippleConfig coordinate:interfaceTransform]',win)
        quick = win[win.index('- (void)sendQuickPathEvent:'):win.index('- (void)sendTouchEvent:')]
        self.assertIn('[super sendQuickPathEvent:event]',quick)
        self.assertNotIn('tvz_displayCenter',quick)
        self.assertIn('_overlayWindow.userInteractionEnabled = NO',win)

    def test_gif_speed_does_not_multiply_lift_or_fade(self):
        view = code('LNTouchVisualizer/Private/LNTouchImageView.m')
        self.assertIn('TVZTouchVizPlaybackDuration(self.image.duration, self.tvzGIFPlaybackRate)',view)
        self.assertIn('if (self.tvzGIFPlaybackRate == rate) return',view)
        win=code('LNTouchVisualizer/Private/LNTouchVisualizerWindow.m')
        self.assertIn('touchView.tvzGIFPlaybackRate = self.touchContactConfig.tvzGIFPlaybackRate',win)
        self.assertIn('rippleView.tvzGIFPlaybackRate = self.touchRippleConfig.tvzGIFPlaybackRate',win)
        self.assertIn('animateWithDuration:self.touchContactConfig.fadeDuration',win)
        self.assertIn('CGAffineTransformScale(touchView.transform, self.touchContactConfig.liftScale',win)
        preview=code('TVZPrefs/TVZTouchVizImagePreview.swift')
        self.assertIn('TVZTouchVizPreviewDuration',preview)
        self.assertIn('tvzOriginalDuration / tvzRate',preview)
        self.assertNotIn('.offset(',preview)
        self.assertNotIn('@State',preview)

    def test_simulator_executes_real_touch_window_and_controls(self):
        runner=(ROOT/'tests/run_preview_tests.sh').read_text()
        self.assertIn('xcrun clang -std=gnu11',runner)
        self.assertNotIn('-x objective-c++',runner)
        for name in ('LNTouchVisualizer/Private/LNTouchVisualizerWindow.m',
                     'LNTouchVisualizer/Private/LNTouchImageView.m',
                     'TVZPrefs/TVZTouchVizImageControls.swift',
                     'tests/image_controls_test.mm','tests/image_controls_test.swift'):
            self.assertIn(name,runner)
        preview=(ROOT/'tests/preview_test.swift').read_text()
        self.assertIn('TVZTouchVizRunImageControlTests()',preview)
        self.assertIn('TVZTouchVizRunSliderTests()',preview)
        self.assertIn('TVZTouchVizRunStorageTests()',preview)
