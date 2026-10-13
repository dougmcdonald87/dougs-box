import importlib.util,json,os,sys,tempfile,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
try:
    from probe_cloud_drive import ProbeError, probe
except ImportError:
    ProbeError=ValueError
    def probe(*args,**kwargs):raise AssertionError('E readback probe not implemented')

class ProbeTests(unittest.TestCase):
    def fixture(self, root, identity='fixture-volume'):
        (root/'.devbox-cloud-volume.json').write_text(json.dumps({'schema_version':1,'cloud_volume_id':identity,'provider_kind':'cloud-block'}))
    def test_fsynced_payload_readback_reports_no_cloud_crash_claim(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);self.fixture(root);r=probe(root,'fixture-volume')
            self.assertEqual(r['scope'],'device_flush_and_local_readback_only')
            self.assertFalse(r['cloud_crash_durability_proven'])
            self.assertEqual(r['bytes'],65536)
            self.assertEqual(len(r['sha256']),64)
            self.assertTrue((root/r['file']).is_file())
    def test_wrong_or_missing_marker_creates_no_canary(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t)
            with self.assertRaises(ProbeError):probe(root,'fixture-volume')
            self.fixture(root,'wrong')
            with self.assertRaises(ProbeError):probe(root,'fixture-volume')
            self.assertEqual(sorted(p.name for p in root.iterdir()),['.devbox-cloud-volume.json'])
    def test_marker_symlink_never_followed(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);other=root/'other';other.write_text('{}')
            try:(root/'.devbox-cloud-volume.json').symlink_to(other)
            except OSError:self.skipTest('symlink privilege unavailable')
            with self.assertRaises(ProbeError):probe(root,'fixture-volume')
    def test_root_symlink_never_followed(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);real=root/'real';real.mkdir();self.fixture(real)
            try:(root/'alias').symlink_to(real,target_is_directory=True)
            except OSError:self.skipTest('symlink privilege unavailable')
            with self.assertRaises(ProbeError):probe(root/'alias','fixture-volume')
    def test_flush_error_not_success(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);self.fixture(root)
            with patch('os.fsync',side_effect=OSError('storage unavailable')):
                with self.assertRaisesRegex(ProbeError,'storage unavailable'):probe(root,'fixture-volume')
    @unittest.skipIf(os.name=='nt','POSIX rename race; Windows uses native relative handles')
    def test_root_swap_before_create_never_writes_outside_bound_directory(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as t:
            base=Path(t);root=base/'root';root.mkdir();self.fixture(root)
            outside=base/'outside';outside.mkdir();self.fixture(outside)
            moved=base/'original';real_open=os.open;swapped=False
            def swap(path,flags,*args,**kwargs):
                nonlocal swapped
                if not swapped and '.devbox-cloud-canary-' in str(path):
                    root.rename(moved);root.symlink_to(outside,target_is_directory=True);swapped=True
                return real_open(path,flags,*args,**kwargs)
            with patch('os.open',side_effect=swap):
                try:probe(root,'fixture-volume')
                except ProbeError:pass
            self.assertTrue(swapped)
            self.assertEqual([p.name for p in outside.iterdir()],['.devbox-cloud-volume.json'])

    def test_repeated_probe_uses_distinct_files(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);self.fixture(root)
            self.assertNotEqual(probe(root,'fixture-volume')['file'],probe(root,'fixture-volume')['file'])

if __name__=='__main__':unittest.main()
