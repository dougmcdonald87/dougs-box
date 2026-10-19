"""Fail-closed policy for an additive, read-only cloud candidate on E:.

This module plans operations; it never contacts a target or mutates disks.
Native inventories and provider entitlement still require independent verification.
"""
import argparse
import ipaddress
import json
import re
import sys
from pathlib import Path

class CloudDriveError(ValueError):
    pass

FIELDS = {'schema_version','drive_letter','portal','target_iqn','disk_unique_id',
          'partition_guid','volume_label','cloud_volume_id'}

def validate_config(config):
    if not isinstance(config,dict) or set(config) != FIELDS:
        raise CloudDriveError('Config fields must match schema exactly; credentials and extra actions are forbidden.')
    if type(config['schema_version']) is not int or config['schema_version'] != 1:
        raise CloudDriveError('Unsupported schema.')
    if config['drive_letter'] != 'E':
        raise CloudDriveError('Only candidate E: is permitted; C:/D: are protected.')
    for key in FIELDS - {'schema_version'}:
        v=config[key]
        if not isinstance(v,str) or not v or v.strip()!=v or any(ord(c)<32 for c in v):
            raise CloudDriveError('Invalid config text: '+key)
        if v.startswith('REPLACE_'):
            raise CloudDriveError('Unconfigured identity: '+key)
    try:
        address=ipaddress.IPv4Address(config['portal'])
    except ipaddress.AddressValueError as e:
        raise CloudDriveError('Portal must be a literal Tailscale IPv4 address.') from e
    if address not in ipaddress.IPv4Network('100.64.0.0/10'):
        raise CloudDriveError('Portal must be within Tailscale IPv4 range.')
    if not re.fullmatch(r'iqn\.\d{4}-\d{2}\.[a-z0-9.-]+:[a-zA-Z0-9:._-]+',config['target_iqn']):
        raise CloudDriveError('Invalid target IQN identity.')
    if not re.fullmatch(r'\{[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\}',config['partition_guid']):
        raise CloudDriveError('Invalid partition GUID identity.')
    return dict(config)

def _integer(value,name):
    if type(value) is not int or value < 0: raise CloudDriveError('Invalid '+name)
    return value

def _boolean(value,name):
    if type(value) is not bool: raise CloudDriveError('Expected boolean '+name)
    return value

def plan_mount(config, inventory):
    c=validate_config(config)
    if not isinstance(inventory,dict):raise CloudDriveError('Invalid inventory.')
    for k in ('occupied_letters','protected_disk_ids','active_sessions','candidate_disks'):
        if not isinstance(inventory.get(k),list):raise CloudDriveError('Missing inventory list '+k)
    if any(str(x).upper().rstrip(':')=='E' for x in inventory['occupied_letters']):
        raise CloudDriveError('E: is occupied; no reassignments allowed.')
    if any(s.get('target_iqn')==c['target_iqn'] for s in inventory['active_sessions']):
        raise CloudDriveError('Refusing to reconfigure an existing session.')
    disks=[d for d in inventory['candidate_disks'] if d.get('unique_id')==c['disk_unique_id']]
    if len(disks)!=1:raise CloudDriveError('Disk identity must match exactly one candidate.')
    d=disks[0]
    for key in ('is_boot','is_system','is_offline','is_read_only'):_boolean(d.get(key),key)
    if d['is_boot'] or d['is_system']:raise CloudDriveError('Refusing system disk.')
    if d['unique_id'] in inventory['protected_disk_ids']:raise CloudDriveError('Refusing protected C:/D: disk.')
    if d.get('bus_type')!='iSCSI':raise CloudDriveError('Candidate must be iSCSI; local disks are not cloud proof.')
    if d.get('portal')!=c['portal'] or d.get('target_iqn')!=c['target_iqn']:
        raise CloudDriveError('Target/portal identity mismatch.')
    if d.get('partition_style')!='GPT':raise CloudDriveError('Requires preformatted GPT; never initializes a disk.')
    parts=d.get('partitions')
    if not isinstance(parts,list):raise CloudDriveError('Missing partition inventory.')
    for sibling in parts:
        paths=sibling.get('access_paths')
        if not isinstance(paths,list):raise CloudDriveError('Missing sibling access-path inventory.')
        if sibling.get('drive_letter') or any(str(path).lower()!=str(sibling.get('volume_unique_id','')).lower() for path in paths):
            raise CloudDriveError('Disk has a mounted partition; disk-wide changes refused.')
    matches=[p for p in parts if str(p.get('guid','')).lower()==c['partition_guid'].lower()]
    if len(matches)!=1:raise CloudDriveError('Partition identity must match exactly one partition.')
    p=matches[0]
    if p.get('filesystem')!='NTFS':raise CloudDriveError('Requires existing NTFS; never formats a disk.')
    volume_id=p.get('volume_unique_id')
    if not isinstance(volume_id,str) or not re.fullmatch(r'\\\\\?\\Volume\{[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\}\\',volume_id):
        raise CloudDriveError('Runtime volume identity unavailable or malformed.')
    if p.get('label')!=c['volume_label']:raise CloudDriveError('Volume label identity mismatch.')
    paths=p.get('access_paths')
    if not isinstance(paths,list):raise CloudDriveError('Missing access-path inventory.')
    if p.get('drive_letter') or any(str(path).lower()!=volume_id.lower() for path in paths):
        raise CloudDriveError('Candidate partition already mounted; no takeover allowed.')
    return {'schema_version':1,'status':'validated_read_only_candidate','drive_letter':'E',
            'disk_number':_integer(d.get('number'),'disk number'),
            'partition_number':_integer(p.get('number'),'partition number'),
            'bus_type':'iSCSI','disk_unique_id':d['unique_id'],'partition_guid':c['partition_guid'],
            'volume_unique_id':volume_id,'volume_label':c['volume_label'],
            'cloud_volume_id':c['cloud_volume_id'],'set_read_only':True,
            'bring_online':d['is_offline'],'original_read_only':d['is_read_only'],
            'original_offline':d['is_offline']}

def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    sub=parser.add_subparsers(dest='command',required=True)
    v=sub.add_parser('validate');v.add_argument('--config',required=True)
    p=sub.add_parser('plan');p.add_argument('--config',required=True);p.add_argument('--inventory',required=True)
    args=parser.parse_args(argv)
    try:
        c=json.loads(Path(args.config).read_text(encoding='utf-8-sig'))
        result=validate_config(c) if args.command=='validate' else plan_mount(c,json.loads(Path(args.inventory).read_text(encoding='utf-8-sig')))
        print(json.dumps(result,sort_keys=True))
        return 0
    except (CloudDriveError,ValueError,OSError,TypeError,AttributeError) as e:
        print('CLOUD E REFUSED: '+str(e),file=sys.stderr)
        return 2

if __name__=='__main__':sys.exit(main())
