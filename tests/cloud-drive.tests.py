import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
try:
    from cloud_drive import CloudDriveError, plan_mount, validate_config
except ImportError:
    CloudDriveError = ValueError
    def plan_mount(*args):
        raise AssertionError('cloud E safety policy not implemented')
    def validate_config(*args):
        raise AssertionError('cloud E config policy not implemented')

CONFIG = {'schema_version': 1, 'drive_letter': 'E', 'portal': '100.100.1.2',
          'target_iqn': 'iqn.2026-10.devbox:cloud-test', 'disk_unique_id': 'cloud-disk-001',
          'partition_guid': '{11111111-1111-1111-1111-111111111111}',
          'volume_unique_id': '\\\\?\\Volume{22222222-2222-2222-2222-222222222222}\\',
          'volume_label': 'DEVBOX_CLOUD_TEST', 'cloud_volume_id': 'cloud-test-001'}
DISK = {'unique_id': 'cloud-disk-001', 'number': 3, 'bus_type': 'iSCSI',
        'is_boot': False, 'is_system': False, 'is_offline': True, 'is_read_only': False,
        'target_iqn': CONFIG['target_iqn'], 'portal': CONFIG['portal'],
        'partition_style': 'GPT', 'partitions': [
            {'number': 2, 'guid': CONFIG['partition_guid'], 'drive_letter': None,
             'volume_unique_id': CONFIG['volume_unique_id'], 'filesystem': 'NTFS',
             'label': CONFIG['volume_label'], 'access_paths': []}]}
INVENTORY = {'occupied_letters': ['C', 'D'], 'protected_disk_ids': ['system', 'workspace'],
             'active_sessions': [], 'candidate_disks': [DISK]}

class PolicyTests(unittest.TestCase):
    def rejection(self, cfg, inv, text):
        with self.assertRaisesRegex(CloudDriveError, text): plan_mount(cfg, inv)

    def test_exact_remote_partition_gets_readonly_e_plan(self):
        p = plan_mount(CONFIG, INVENTORY)
        self.assertEqual(p['drive_letter'], 'E')
        self.assertEqual(p['disk_number'], 3)
        self.assertEqual(p['partition_number'], 2)
        self.assertTrue(p['set_read_only'])
        self.assertTrue(p['bring_online'])
        self.assertEqual(p['status'], 'validated_read_only_candidate')

    def test_any_existing_e_mapping_rejected_before_mount(self):
        i=copy.deepcopy(INVENTORY); i['occupied_letters'].append('E')
        self.rejection(CONFIG, i, 'E:.*occupied')

    def test_c_or_d_disk_cannot_be_reused(self):
        i=copy.deepcopy(INVENTORY); i['protected_disk_ids'].append('cloud-disk-001')
        self.rejection(CONFIG, i, 'protected')

    def test_system_flags_independently_block_candidate(self):
        for flag in ('is_boot', 'is_system'):
            i=copy.deepcopy(INVENTORY);i['candidate_disks'][0][flag]=True
            self.rejection(CONFIG,i,'system')

    def test_wrong_disk_partition_volume_label_target_and_portal_rejected(self):
        for field,value in [('disk_unique_id','wrong'),('partition_guid','{33333333-3333-3333-3333-333333333333}'),
                           ('volume_unique_id','wrong'),('volume_label','wrong'),
                           ('target_iqn','iqn.2026-10.other:wrong'),('portal','100.100.1.3')]:
            c=copy.deepcopy(CONFIG);c[field]=value
            self.rejection(c,INVENTORY,'identity|match')

    def test_ambiguous_matching_disks_rejected(self):
        i=copy.deepcopy(INVENTORY);i['candidate_disks'].append(copy.deepcopy(DISK))
        self.rejection(CONFIG,i,'exactly one')

    def test_raw_and_non_ntfs_rejected_without_format_plan(self):
        i=copy.deepcopy(INVENTORY);i['candidate_disks'][0]['partition_style']='RAW'
        self.rejection(CONFIG,i,'preformatted')
        i=copy.deepcopy(INVENTORY);i['candidate_disks'][0]['partitions'][0]['filesystem']='ReFS'
        self.rejection(CONFIG,i,'NTFS')

    def test_non_iscsi_volume_is_not_cloud_disk(self):
        i=copy.deepcopy(INVENTORY);i['candidate_disks'][0]['bus_type']='File Backed Virtual'
        self.rejection(CONFIG,i,'iSCSI')

    def test_existing_session_is_not_reconfigured(self):
        i=copy.deepcopy(INVENTORY);i['active_sessions']=[{'target_iqn':CONFIG['target_iqn']}]
        self.rejection(CONFIG,i,'existing session')

    def test_already_mounted_partition_refused(self):
        i=copy.deepcopy(INVENTORY);i['candidate_disks'][0]['partitions'][0]['drive_letter']='F'
        self.rejection(CONFIG,i,'mounted')
        i=copy.deepcopy(INVENTORY);i['candidate_disks'][0]['partitions'][0]['access_paths']=['C:\\mount\\']
        self.rejection(CONFIG,i,'mounted')

    def test_mounted_sibling_partition_blocks_diskwide_readonly(self):
        i=copy.deepcopy(INVENTORY)
        sibling=copy.deepcopy(DISK['partitions'][0]);sibling['number']=3
        sibling['guid']='{33333333-3333-3333-3333-333333333333}'
        sibling['drive_letter']='F';sibling['access_paths']=['F:\\']
        i['candidate_disks'][0]['partitions'].append(sibling)
        self.rejection(CONFIG,i,'mounted')

    def test_invalid_or_public_portal_never_accepted(self):
        for portal in ['1.2.3.4','100.1.2.3','100.127.255.256','100.100.1.2:3260','localhost','100.100.1.2\n']:
            c=copy.deepcopy(CONFIG);c['portal']=portal
            with self.assertRaises(CloudDriveError):validate_config(c)

    def test_only_e_and_no_unapproved_schema_or_fields(self):
        for key,val in [('drive_letter','D'),('schema_version',2),('format',True),('password','secret')]:
            c=copy.deepcopy(CONFIG);c[key]=val
            with self.assertRaises(CloudDriveError):validate_config(c)

    def test_bad_types_and_missing_fields_rejected(self):
        for key in CONFIG:
            c=copy.deepcopy(CONFIG);del c[key]
            with self.assertRaises(CloudDriveError):validate_config(c)
        i=copy.deepcopy(INVENTORY);i['candidate_disks'][0]['is_boot']='false'
        self.rejection(CONFIG,i,'boolean')

    def test_cli_failure_produces_no_mount_actions(self):
        import tempfile
        with tempfile.TemporaryDirectory() as t:
            c=Path(t)/'c.json';i=Path(t)/'i.json';c.write_text(json.dumps(CONFIG))
            inv=copy.deepcopy(INVENTORY);inv['occupied_letters'].append('E');i.write_text(json.dumps(inv))
            result=subprocess.run([sys.executable,str(ROOT/'scripts/cloud_drive.py'),'plan','--config',str(c),'--inventory',str(i)],capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            self.assertEqual(result.stdout.strip(),'')

if __name__=='__main__':unittest.main()
