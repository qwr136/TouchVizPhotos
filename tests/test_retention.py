import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from tvz_source_checks import strip_comments

ROOT = Path(__file__).resolve().parents[1]


def image_name(i, extension='gif'):
    return f'{i:08X}-1234-4567-89AB-0123456789AB.{extension}'


class TVZRetentionFilesystemTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which('cc'):
            raise RuntimeError('C compiler required; file cleanup tests cannot be skipped')
        cls.build = tempfile.TemporaryDirectory()
        cls.binary = Path(cls.build.name)/'retention'
        subprocess.run(['cc','-std=c11','-D_POSIX_C_SOURCE=200809L','-D_DARWIN_C_SOURCE','-Wall','-Wextra','-Werror',
                        str(ROOT/'tests/retention_driver.c'),'-o',str(cls.binary)],check=True)

    @classmethod
    def tearDownClass(cls):
        cls.build.cleanup()

    def setUp(self):
        self.sandbox = tempfile.TemporaryDirectory()
        self.base = Path(self.sandbox.name)
        self.root = self.base/'Touch-Viz'
        self.root.mkdir()

    def tearDown(self):
        self.sandbox.cleanup()

    def write(self, i, extension='gif', data=b'owned image bytes'):
        path = self.root/image_name(i,extension)
        path.write_bytes(data)
        return path

    def prune(self, keep, pending=(), valid=True, root=None):
        result = subprocess.run([str(self.binary),str(root or self.root),keep,*pending],
                                text=True,capture_output=True)
        self.assertEqual(result.returncode==0,valid,result.stdout+result.stderr)
        error, removed = map(int,result.stdout.split())
        return error,removed

    def test_A_B_C_each_success_leaves_one_file(self):
        source = self.base/'album-original.gif'
        source.write_bytes(b'album original unchanged')
        for i in range(1,4):
            selected = self.write(i)
            self.prune(selected.name)
            self.assertEqual(list(self.root.iterdir()),[selected])
        self.assertEqual(source.read_bytes(),b'album original unchanged')

    def test_existing_three_images_keep_current_only(self):
        paths = [self.write(i) for i in range(1,4)]
        self.assertEqual(self.prune(paths[-1].name),(0,2))
        self.assertEqual(set(self.root.iterdir()),{paths[-1]})
        self.assertEqual(self.prune(paths[-1].name),(0,0))

    def test_static_GIF_Emoji_switches_have_one_file(self):
        for i,ext in enumerate(('gif','jpg','gif','png','heic','PNG'),1):
            selected = self.write(i,ext)
            self.prune(selected.name)
            self.assertEqual(set(self.root.iterdir()),{selected})

    def test_missing_or_empty_new_file_keeps_old(self):
        old=self.write(1)
        self.prune(image_name(2),valid=False)
        self.assertTrue(old.exists())
        bad=self.write(2,data=b'')
        self.prune(bad.name,valid=False)
        self.assertTrue(old.exists())

    def test_pending_import_survives_old_cleanup(self):
        old=self.write(1);current=self.write(2);pending=self.write(3)
        self.assertEqual(self.prune(current.name,[pending.name]),(0,1))
        self.assertEqual(set(self.root.iterdir()),{current,pending})
        self.prune(pending.name)
        self.assertEqual(set(self.root.iterdir()),{pending})

    def test_out_of_order_completion_releases_pending_without_leaking_old(self):
        a,b,c = [self.write(i) for i in range(1,4)]
        # Later completion ran first: keep committed C and pending A/B.
        self.prune(c.name,[a.name,b.name])
        self.prune(c.name,[a.name])
        self.prune(c.name)
        self.assertEqual(set(self.root.iterdir()),{c})

    def test_default_cleans_managed_copies_only(self):
        self.write(1); self.write(2,'png')
        unowned=self.root/'notes.txt';unowned.write_text('do not delete')
        self.prune('default.png')
        self.assertEqual(set(self.root.iterdir()),{unowned})

    def test_links_folders_and_non_image_files_untouched(self):
        selected=self.write(1);self.write(2)
        outside=self.base/'outside';outside.write_bytes(b'never delete')
        link=self.root/image_name(3);link.symlink_to(outside)
        hard=self.root/image_name(4);os.link(outside,hard)
        folder=self.root/image_name(5);folder.mkdir()
        nested=folder/image_name(6);nested.write_bytes(b'no recursion')
        text=self.root/image_name(7,'txt');text.write_text('not an image')
        unowned=self.root/'custom-name.gif';unowned.write_bytes(b'unowned')
        self.prune(selected.name)
        for path in (selected,link,hard,folder,nested,text,unowned,outside):
            self.assertTrue(path.exists(),str(path))
        self.assertEqual(outside.read_bytes(),b'never delete')

    def test_invalid_keep_or_symlink_keep_refuses_cleanup(self):
        old=self.write(1)
        for name in ('','../outside.gif','sub/file.gif','sub\\file.gif'):
            self.prune(name,valid=False); self.assertTrue(old.exists())
        outside=self.base/'outside';outside.write_bytes(b'not selected')
        link=self.root/image_name(2);link.symlink_to(outside)
        self.prune(link.name,valid=False);self.assertTrue(old.exists())

    def test_root_symlink_is_not_followed(self):
        old=self.write(1)
        linked=self.base/'linked-root';linked.symlink_to(self.root,target_is_directory=True)
        self.prune(old.name,root=linked,valid=False)
        self.assertTrue(old.exists())

    def test_cleanup_failure_returns_error_preserves_selected(self):
        old=self.write(1)
        self.prune(old.name,root=self.base/'missing',valid=False)
        self.assertTrue(old.exists())


class TVZRetentionIntegrationContracts(unittest.TestCase):
    def test_only_settings_after_commit_and_page_restore_call_cleanup(self):
        view=strip_comments((ROOT/'TVZPrefs/TVZRootView.swift').read_text())
        apply=view[view.index('private func tvz_applySelectedImage'):view.index('var resetSection: some View')]
        self.assertLess(apply.index('tvz_selection.select'),apply.index('tvz_pruneUnusedImages(afterSelectingName: name)'))
        self.assertIn('DispatchQueue.global(qos: .utility).async',apply)
        self.assertIn('Bundle.tvz_pruneFillImages(afterSelectingName: name)',apply)
        self.assertIn('if !tvz_isImportingPhoto {\n                tvz_pruneUnusedImages()',view)
        bundle=strip_comments((ROOT/'TVZPrefs/NSBundle+TVZPrefs.mm').read_text())
        prune=bundle[bundle.index('+ (BOOL)tvz_pruneFillImagesAfterSelectingName:'):bundle.index('+ (BOOL)tvz_removeAllFillImages')]
        self.assertIn('NSString *name = [defaults stringForKey:@"imageFillName"]',prune)
        self.assertIn('[defaults synchronize]',prune)
        self.assertIn('[TVZTouchVizImageLoader imageAtPath:',prune)
        self.assertIn('TVZTouchVizPendingFillImages().allObjects',prune)
        self.assertIn('TVZTouchVizPruneImageDirectory',prune)
        commit=bundle[bundle.index('+ (BOOL)tvz_commitFillImageNamed:'):bundle.index('+ (BOOL)tvz_pruneFillImagesAfterSelectingName:')]
        self.assertIn('@synchronized(self)',commit)
        self.assertIn('@synchronized(self)',prune)
        self.assertIn('if (!saved)',commit)
        self.assertIn('[defaults setObject:previousName',commit)
        model=strip_comments((ROOT/'TVZPrefs/TVZTouchVizSelection.swift').read_text())
        self.assertIn('guard persist(name, emoji) else { return false }',model)
        simulator=(ROOT/'tests/run_preview_tests.sh').read_text()
        for production in ('TVZPrefs/NSBundle+TVZPrefs.mm', 'TVZPrefs/TVZUserDefaults.mm', 'tests/storage_test.mm'):
            self.assertIn(production,simulator)
        self.assertIn('TVZTouchVizRunStorageTests()', (ROOT/'tests/preview_test.swift').read_text())
        for file in ('TouchViz.xm','TVZPrefs/TVZTouchVizPhotoPicker.swift'):
            self.assertNotIn('pruneFillImages',(ROOT/file).read_text())
        self.assertNotIn('.jbroot-',bundle)
        self.assertNotIn('210EC63343619961',bundle)
