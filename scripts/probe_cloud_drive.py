"""Fresh canary: device flush and readback, never a cloud durability guarantee."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import sys
import uuid

class ProbeError(ValueError):
    pass

def _plain(path, directory=False):
    info=path.lstat()
    if stat.S_ISLNK(info.st_mode) or getattr(info,'st_file_attributes',0)&getattr(stat,'FILE_ATTRIBUTE_REPARSE_POINT',1024):
        raise ProbeError('Reparse/symlink paths refused.')
    if directory and not stat.S_ISDIR(info.st_mode):raise ProbeError('Volume root must be a directory.')
    return info

def read_marker(root,expected):
    _plain(root,True)
    # Reject reparse ancestors as well as the leaf; prevent a redirected path.
    for parent in root.parents:_plain(parent,True)
    marker=root/'.devbox-cloud-volume.json';_plain(marker)
    flags=os.O_RDONLY|getattr(os,'O_NOFOLLOW',0)|getattr(os,'O_BINARY',0)
    fd=os.open(marker,flags)
    try:
        info=os.fstat(fd)
        if getattr(info,'st_file_attributes',0)&getattr(stat,'FILE_ATTRIBUTE_REPARSE_POINT',1024):raise ProbeError('Reparse marker refused.')
        if info.st_size>8192:raise ProbeError('Oversized marker.')
        raw=os.read(fd,8193)
    finally:os.close(fd)
    m=json.loads(raw.decode('utf-8-sig'))
    if m.get('schema_version')!=1 or m.get('provider_kind')!='cloud-block' or m.get('cloud_volume_id')!=expected:
        raise ProbeError('Cloud marker identity mismatch.')
    return m

def probe(root,expected):
    root=Path(root).absolute()
    try:
        read_marker(root,expected)
        filename='.devbox-cloud-canary-'+uuid.uuid4().hex+'.bin'
        payload=os.urandom(65536)
        path=root/filename
        flags=os.O_WRONLY|os.O_CREAT|os.O_EXCL|getattr(os,'O_NOFOLLOW',0)|getattr(os,'O_BINARY',0)
        fd=os.open(path,flags,0o600)
        try:
            view=memoryview(payload)
            while view:
                n=os.write(fd,view)
                if n<=0:raise ProbeError('Incomplete canary write.')
                view=view[n:]
            os.fsync(fd)
        finally:os.close(fd)
        _plain(path)
        observed=path.read_bytes()
        if observed!=payload:raise ProbeError('Canary readback mismatch.')
        read_marker(root,expected)
        return {'schema_version':1,'status':'readback_verified','file':filename,
                'bytes':len(payload),'sha256':hashlib.sha256(payload).hexdigest(),
                'scope':'device_flush_and_local_readback_only',
                'cloud_crash_durability_proven':False}
    except (OSError,ValueError,TypeError,AttributeError) as e:
        raise ProbeError(str(e)) from e

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--root',default='E:\\');p.add_argument('--cloud-volume-id',required=True)
    args=p.parse_args()
    if os.name!='nt' or Path(args.root).absolute()!=Path('E:\\'):
        print('CLOUD E REFUSED: command-line probe is Windows E: only.',file=sys.stderr);return 2
    try:print(json.dumps(probe(args.root,args.cloud_volume_id)));return 0
    except ProbeError as e:print('CLOUD E PROBE FAILED: '+str(e),file=sys.stderr);return 2

if __name__=='__main__':sys.exit(main())
