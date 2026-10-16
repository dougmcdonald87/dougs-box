"""Whole-VM file inventory verifier; native Hyper-V validates disk/config contents."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import uuid

class ManifestError(RuntimeError):
    pass

def _guid(value):
    try:
        if not isinstance(value,str) or str(uuid.UUID(value)) != value.lower():raise ValueError()
        return str(uuid.UUID(value))
    except (ValueError,AttributeError):raise ManifestError('Invalid VM/checkpoint identity') from None

def consistency_policy(mode,state,production_only=False,checkpoint_id=None,shutdown_verified=False,capture_state=None):
    if mode=='finish' and state=='Off' and shutdown_verified is True:return 'clean-shutdown'
    if capture_state is not None:
        if mode=='save' and state=='Running' and production_only is True and capture_state=='CaptureDataConsistentState':return 'data-consistent-export'
        raise ManifestError('Unsupported live capture consistency refused')
    if mode=='save' and state=='Running' and production_only is True and checkpoint_id:
        _guid(checkpoint_id)
        return 'production-checkpoint'
    raise ManifestError('Inconsistent Save/Finish request refused')

def _relative(value):
    if not isinstance(value,str) or not value or '\\' in value or ':' in value:
        raise ManifestError('Invalid export relative path')
    path=PurePosixPath(value)
    if path.is_absolute() or any(x in ('','.', '..') for x in value.split('/')):
        raise ManifestError('Export path escape refused')
    return value

def _linked(path):
    return path.is_symlink() or getattr(path,'is_junction',lambda:False)()

def _inventory(root):
    root=Path(root).absolute()
    if not root.is_dir() or any(_linked(x) for x in (root,*root.parents)):
        raise ManifestError('Export root unavailable or linked')
    result=[];total=0;names=set()
    for base,dirs,files in os.walk(root,followlinks=False):
        for name in dirs:
            if _linked(Path(base)/name):raise ManifestError('Export directory link refused')
        for name in files:
            path=Path(base)/name
            if _linked(path) or not path.is_file():raise ManifestError('Export file link refused')
            relative=_relative(path.relative_to(root).as_posix())
            if relative.casefold() in names:raise ManifestError('Duplicate export path')
            names.add(relative.casefold());size=path.stat().st_size;total+=size
            if len(names)>10000 or total>80*1024**3:raise ManifestError('Export inventory capacity exceeded')
            digest=hashlib.sha256()
            with path.open('rb') as stream:
                for block in iter(lambda:stream.read(1024**2),b''):digest.update(block)
            result.append({'path':relative,'bytes':size,'sha256':digest.hexdigest()})
    if not result:raise ManifestError('Empty export refused')
    return sorted(result,key=lambda x:x['path'])

def _structure(value,expected_vm_id,supported_versions):
    fields={'schema','vm_id','vm_name','configuration_version','mode','consistency','generation','files','disks','config'}
    if not isinstance(value,dict) or set(value)!=fields or type(value['schema']) is not int or value['schema']!=1:
        raise ManifestError('Invalid whole VM manifest schema')
    if _guid(value['vm_id'])!=_guid(expected_vm_id):raise ManifestError('VM identity mismatch')
    if not isinstance(value['vm_name'],str) or not re.fullmatch(r'DevBoxWindowsState-\d+-\d+',value['vm_name']):
        raise ManifestError('VM name outside owned probe')
    version=value['configuration_version']
    if not isinstance(version,str) or not re.fullmatch(r'\d+\.\d+',version) or version not in supported_versions:
        raise ManifestError('Unsupported VM configuration version')
    pairs={'save':{'production-checkpoint','data-consistent-export'},'finish':{'clean-shutdown'}}
    if value['mode'] not in pairs or value['consistency'] not in pairs[value['mode']]:raise ManifestError('Consistency mode mismatch')
    if not isinstance(value['generation'],str) or not re.fullmatch(value['mode']+r'-[0-9a-f]{32}',value['generation']):
        raise ManifestError('Generation identity mismatch')
    if not isinstance(value['files'],list) or not 0<len(value['files'])<=10000:raise ManifestError('Invalid file inventory')
    files={};total=0
    for file in value['files']:
        if not isinstance(file,dict) or set(file)!={'path','bytes','sha256'}:raise ManifestError('Invalid file entry')
        name=_relative(file['path']);key=name.casefold()
        if key in files:raise ManifestError('Duplicate manifest path')
        if type(file['bytes']) is not int or file['bytes']<0 or not isinstance(file['sha256'],str) or not re.fullmatch(r'[0-9a-f]{64}',file['sha256']):
            raise ManifestError('Invalid file length/digest')
        files[key]=file;total+=file['bytes']
    if total>80*1024**3:raise ManifestError('Manifest inventory too large')
    config=_relative(value['config'])
    configs=[f for f in files.values() if f['path'].lower().endswith('.vmcx')]
    main=[f for f in configs if f['path'].casefold().endswith('/virtual machines/'+_guid(expected_vm_id)+'.vmcx')]
    if len(main)!=1 or config.casefold() not in files or main[0]['path'].casefold()!=config.casefold():
        raise ManifestError('Exactly one owned VM configuration required')
    for f in configs:
        if f is not main[0] and not re.search(r'/snapshots/[0-9a-f-]{36}\.vmcx
    # Checkpoint filenames contain checkpoint IDs. Native Compare-VM binds the embedded VM ID.
    disks=value['disks']
    if not isinstance(disks,list) or not disks:raise ManifestError('Export disks missing')
    graph={}
    for disk in disks:
        if not isinstance(disk,dict) or set(disk)!={'path','parent','capacity_bytes','type'}:raise ManifestError('Invalid disk entry')
        path=_relative(disk['path']);key=path.casefold()
        if key in graph or key not in files or not path.lower().endswith(('.vhdx','.avhdx')):raise ManifestError('Disk file missing/duplicated')
        if type(disk['capacity_bytes']) is not int or disk['capacity_bytes']!=64*1024**3:raise ManifestError('Owned disk capacity mismatch')
        parent=disk['parent']
        if disk['type']=='Dynamic' and parent is None:graph[key]=None
        elif disk['type']=='Differencing' and parent is not None:graph[key]=_relative(parent).casefold()
        else:raise ManifestError('Disk type/parent mismatch')
    listed={f['path'].casefold() for f in files.values() if f['path'].lower().endswith(('.vhdx','.avhdx'))}
    if set(graph)!=listed:raise ManifestError('Disk/parent inventory incomplete')
    for key in graph:
        seen=set();current=key
        while current is not None:
            if current not in graph:raise ManifestError('Differencing parent missing')
            if current in seen:raise ManifestError('Differencing parent cycle')
            seen.add(current);current=graph[current]
    return files

def make_manifest(root,vm_id,vm_name,version,mode,consistency,disks):
    files=_inventory(root);configs=[f['path'] for f in files if f['path'].lower().endswith('.vmcx')]
    main=[p for p in configs if p.casefold().endswith('/virtual machines/'+_guid(vm_id)+'.vmcx')]
    if len(main)!=1:raise ManifestError('Export VM configuration ambiguous/missing')
    value={'schema':1,'vm_id':_guid(vm_id),'vm_name':vm_name,'configuration_version':version,'mode':mode,'consistency':consistency,'generation':mode+'-'+uuid.uuid4().hex,'files':files,'disks':disks,'config':main[0]}
    _structure(value,vm_id,[version])
    return value

def validate_manifest(root,value,expected_vm_id,supported_versions):
    _structure(value,expected_vm_id,supported_versions)
    actual=_inventory(root)
    if actual!=sorted(value['files'],key=lambda x:x['path']):raise ManifestError('Export file inventory/length/hash mismatch')
    return value

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('action',choices=['create','verify']);parser.add_argument('--root',required=True);parser.add_argument('--metadata',required=True);parser.add_argument('--manifest',required=True)
    args=parser.parse_args();metadata=json.loads(Path(args.metadata).read_text(encoding='utf-8-sig'))
    if args.action=='create':
        destination=Path(args.manifest)
        if destination.exists():raise ManifestError('Existing immutable manifest must not be replaced')
        consistency=consistency_policy(metadata['mode'],metadata['state'],metadata.get('production_only',False),metadata.get('checkpoint_id'),metadata.get('shutdown_verified',False),metadata.get('capture_state'))
        value=make_manifest(args.root,metadata['vm_id'],metadata['vm_name'],metadata['configuration_version'],metadata['mode'],consistency,metadata['disks'])
        if 'generation' in metadata:
            value['generation']=metadata['generation']
            _structure(value,metadata['vm_id'],[metadata['configuration_version']])
        payload=json.dumps(value,indent=2).encode()
        if len(payload)>1024**2:raise ManifestError('Manifest exceeds metadata limit')
        with destination.open('xb') as stream:stream.write(payload)
    else:
        raw=Path(args.manifest).read_bytes()
        if len(raw)>1024**2:raise ManifestError('Manifest exceeds metadata limit')
        value=validate_manifest(args.root,json.loads(raw),metadata['vm_id'],metadata['supported_versions'])
    print(json.dumps({'vm_id':value['vm_id'],'generation':value['generation'],'files':len(value['files']),'verified':True}))
,f['path'],re.I):
            raise ManifestError('Unexpected additional VM configuration')
    # Checkpoint filenames contain checkpoint IDs. Native Compare-VM binds the embedded VM ID.
    disks=value['disks']
    if not isinstance(disks,list) or not disks:raise ManifestError('Export disks missing')
    graph={}
    for disk in disks:
        if not isinstance(disk,dict) or set(disk)!={'path','parent','capacity_bytes','type'}:raise ManifestError('Invalid disk entry')
        path=_relative(disk['path']);key=path.casefold()
        if key in graph or key not in files or not path.lower().endswith(('.vhdx','.avhdx')):raise ManifestError('Disk file missing/duplicated')
        if type(disk['capacity_bytes']) is not int or disk['capacity_bytes']!=64*1024**3:raise ManifestError('Owned disk capacity mismatch')
        parent=disk['parent']
        if disk['type']=='Dynamic' and parent is None:graph[key]=None
        elif disk['type']=='Differencing' and parent is not None:graph[key]=_relative(parent).casefold()
        else:raise ManifestError('Disk type/parent mismatch')
    listed={f['path'].casefold() for f in files.values() if f['path'].lower().endswith(('.vhdx','.avhdx'))}
    if set(graph)!=listed:raise ManifestError('Disk/parent inventory incomplete')
    for key in graph:
        seen=set();current=key
        while current is not None:
            if current not in graph:raise ManifestError('Differencing parent missing')
            if current in seen:raise ManifestError('Differencing parent cycle')
            seen.add(current);current=graph[current]
    return files

def make_manifest(root,vm_id,vm_name,version,mode,consistency,disks):
    files=_inventory(root);configs=[f['path'] for f in files if f['path'].lower().endswith('.vmcx')]
    if len(configs)!=1:raise ManifestError('Export configuration ambiguous/missing')
    value={'schema':1,'vm_id':_guid(vm_id),'vm_name':vm_name,'configuration_version':version,'mode':mode,'consistency':consistency,'generation':mode+'-'+uuid.uuid4().hex,'files':files,'disks':disks,'config':configs[0]}
    _structure(value,vm_id,[version])
    return value

def validate_manifest(root,value,expected_vm_id,supported_versions):
    _structure(value,expected_vm_id,supported_versions)
    actual=_inventory(root)
    if actual!=sorted(value['files'],key=lambda x:x['path']):raise ManifestError('Export file inventory/length/hash mismatch')
    return value

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('action',choices=['create','verify']);parser.add_argument('--root',required=True);parser.add_argument('--metadata',required=True);parser.add_argument('--manifest',required=True)
    args=parser.parse_args();metadata=json.loads(Path(args.metadata).read_text(encoding='utf-8-sig'))
    if args.action=='create':
        destination=Path(args.manifest)
        if destination.exists():raise ManifestError('Existing immutable manifest must not be replaced')
        consistency=consistency_policy(metadata['mode'],metadata['state'],metadata.get('production_only',False),metadata.get('checkpoint_id'),metadata.get('shutdown_verified',False),metadata.get('capture_state'))
        value=make_manifest(args.root,metadata['vm_id'],metadata['vm_name'],metadata['configuration_version'],metadata['mode'],consistency,metadata['disks'])
        if 'generation' in metadata:
            value['generation']=metadata['generation']
            _structure(value,metadata['vm_id'],[metadata['configuration_version']])
        payload=json.dumps(value,indent=2).encode()
        if len(payload)>1024**2:raise ManifestError('Manifest exceeds metadata limit')
        with destination.open('xb') as stream:stream.write(payload)
    else:
        raw=Path(args.manifest).read_bytes()
        if len(raw)>1024**2:raise ManifestError('Manifest exceeds metadata limit')
        value=validate_manifest(args.root,json.loads(raw),metadata['vm_id'],metadata['supported_versions'])
    print(json.dumps({'vm_id':value['vm_id'],'generation':value['generation'],'files':len(value['files']),'verified':True}))
