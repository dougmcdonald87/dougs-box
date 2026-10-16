import copy, importlib.util, pathlib, tempfile, unittest, uuid
SOURCE=pathlib.Path(__file__).resolve().parents[1]/'scripts/windows_state_manifest.py'
module=None
if SOURCE.exists():
    spec=importlib.util.spec_from_file_location('windows_state_manifest',SOURCE)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)

class CheckpointManifestTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(module,'Checkpoint manifest verifier unavailable')
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=pathlib.Path(self.temp.name)/'export';self.root.mkdir()
        self.id=str(uuid.uuid4());self.name='DevBoxWindowsState-123-1'
        self.config='Virtual Machines/'+self.id+'.vmcx'
        self.disk='Virtual Hard Disks/windows-home.vhdx'
        for name,data in [(self.config,b'opaque native configuration fixture'),(self.disk,b'opaque native disk fixture')]:
            p=self.root/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)
        self.disks=[{'path':self.disk,'parent':None,'capacity_bytes':64*1024**3,'type':'Dynamic'}]
    def manifest(self):
        return module.make_manifest(self.root,self.id,self.name,'12.0','finish','clean-shutdown',self.disks)
    def verify(self,value):return module.validate_manifest(self.root,value,self.id,['12.0'])
    def test_whole_inventory_and_identity_pass(self):
        m=self.manifest();self.verify(m);self.assertEqual({x['path'] for x in m['files']},{self.config,self.disk})
    def test_snapshot_filename_is_not_vm_identity(self):
        alternate=self.root/('Snapshots/'+str(uuid.uuid4())+'.vmcx')
        alternate.parent.mkdir();alternate.write_bytes(b'opaque native snapshot fixture')
        self.verify(self.manifest())
    def test_foreign_main_config_refused(self):
        alternate=self.root/('Virtual Machines/'+str(uuid.uuid4())+'.vmcx')
        (self.root/self.config).rename(alternate)
        with self.assertRaises(module.ManifestError):self.manifest()
    def test_unexpected_extra_main_config_refused(self):
        alternate=self.root/('Virtual Machines/'+str(uuid.uuid4())+'.vmcx')
        alternate.write_bytes(b'foreign main configuration')
        with self.assertRaises(module.ManifestError):self.manifest()
    def test_explicit_data_consistent_capture_passes(self):
        accepted=False
        try:
            accepted=module.consistency_policy('save','Running',production_only=True,capture_state='CaptureDataConsistentState')=='data-consistent-export'
        except (module.ManifestError,TypeError):
            pass
        self.assertTrue(accepted,'Explicit whole-VM production data-consistent capture must be supported')
    def test_crash_and_saved_capture_refused(self):
        for capture in ('CaptureCrashConsistentState','CaptureSavedState','Unknown'):
            with self.subTest(capture=capture):
                with self.assertRaises(module.ManifestError):
                    module.consistency_policy('save','Running',production_only=True,capture_state=capture)
    def test_data_consistent_capture_requires_production_only(self):
        with self.assertRaises(module.ManifestError):
            module.consistency_policy('save','Running',capture_state='CaptureDataConsistentState')
    def test_running_finish_refused(self):
        with self.assertRaises(module.ManifestError):module.consistency_policy('finish','Running',shutdown_verified=True)
    def test_unclean_off_finish_refused(self):
        with self.assertRaises(module.ManifestError):module.consistency_policy('finish','Off')
    def test_standard_save_refused(self):
        with self.assertRaises(module.ManifestError):module.consistency_policy('save','Running',checkpoint_id=str(uuid.uuid4()))
    def test_missing_production_receipt_refused(self):
        with self.assertRaises(module.ManifestError):module.consistency_policy('save','Running',production_only=True)
    def test_clean_finish_and_production_save_pass(self):
        self.assertEqual(module.consistency_policy('finish','Off',shutdown_verified=True),'clean-shutdown')
        self.assertEqual(module.consistency_policy('save','Running',production_only=True,checkpoint_id=str(uuid.uuid4())),'production-checkpoint')
    def test_truncated_disk_refused(self):
        m=self.manifest();(self.root/self.disk).write_bytes(b'x')
        with self.assertRaises(module.ManifestError):self.verify(m)
    def test_same_length_corruption_refused(self):
        m=self.manifest();p=self.root/self.disk;p.write_bytes(b'x'*p.stat().st_size)
        with self.assertRaises(module.ManifestError):self.verify(m)
    def test_wrong_vm_identity_refused(self):
        m=self.manifest();m['vm_id']=str(uuid.uuid4())
        with self.assertRaises(module.ManifestError):self.verify(m)
    def test_unsupported_configuration_refused(self):
        m=self.manifest();m['configuration_version']='999.0'
        with self.assertRaises(module.ManifestError):self.verify(m)
    def test_missing_parent_refused(self):
        m=self.manifest();m['disks'][0].update(type='Differencing',parent='Virtual Hard Disks/missing.vhdx')
        with self.assertRaises(module.ManifestError):self.verify(m)
    def test_parent_cycle_refused(self):
        m=self.manifest();m['disks'][0].update(type='Differencing',parent=self.disk)
        with self.assertRaises(module.ManifestError):self.verify(m)
    def test_path_escape_refused(self):
        m=self.manifest();m['files'][0]['path']='../outside'
        with self.assertRaises(module.ManifestError):self.verify(m)
    def test_extra_unlisted_file_refused(self):
        m=self.manifest();(self.root/'unlisted.txt').write_text('unexpected')
        with self.assertRaises(module.ManifestError):self.verify(m)
    def test_linked_export_refused(self):
        m=self.manifest();p=self.root/self.disk;p.unlink();p.symlink_to(self.root/self.config)
        with self.assertRaises(module.ManifestError):self.verify(m)
    def test_duplicate_case_folded_paths_refused(self):
        m=self.manifest();m['files'].append(copy.deepcopy(m['files'][0]));m['files'][-1]['path']=m['files'][-1]['path'].upper()
        with self.assertRaises(module.ManifestError):self.verify(m)

if __name__=='__main__':unittest.main()
