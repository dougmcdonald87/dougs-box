"""Canary bound to an opened directory; device flush/readback, not cloud proof."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys
import uuid

class ProbeError(ValueError):
    pass

def _plain(path,directory=False):
    info=path.lstat()
    if stat.S_ISLNK(info.st_mode) or getattr(info,'st_file_attributes',0)&getattr(stat,'FILE_ATTRIBUTE_REPARSE_POINT',1024):
        raise ProbeError('Reparse/symlink paths refused.')
    if directory and not stat.S_ISDIR(info.st_mode):raise ProbeError('Volume root must be a directory.')
    return info

class _BoundDirectory:
    """Relative opens never re-resolve root or its ancestors after binding."""
    def __init__(self,root,expected_volume=None):
        self.root=Path(root);self.expected_volume=expected_volume;self.fd=None;self.handle=None
    def __enter__(self):
        before=_plain(self.root,True)
        for parent in self.root.parents:_plain(parent,True)
        try:
            if os.name=='nt':self._windows_bind()
            else:
                self.fd=os.open(self.root,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW)
                opened=os.fstat(self.fd)
                if (opened.st_dev,opened.st_ino)!=(before.st_dev,before.st_ino):raise ProbeError('Directory changed before binding.')
            return self
        except Exception:
            self.__exit__(None,None,None);raise
    def __exit__(self,*args):
        if self.fd is not None:os.close(self.fd);self.fd=None
        if self.handle is not None:self.kernel.CloseHandle(self.handle);self.handle=None
    def _windows_bind(self):
        import ctypes as ct
        from ctypes import wintypes as w
        self.ct=ct;self.w=w
        self.kernel=ct.WinDLL('kernel32',use_last_error=True)
        self.ntdll=ct.WinDLL('ntdll')
        self.kernel.CreateFileW.argtypes=[w.LPCWSTR,w.DWORD,w.DWORD,ct.c_void_p,w.DWORD,w.DWORD,w.HANDLE]
        self.kernel.CreateFileW.restype=w.HANDLE
        self.kernel.CloseHandle.argtypes=[w.HANDLE];self.kernel.CloseHandle.restype=w.BOOL
        # Do not share deletion; OPEN_REPARSE_POINT lets us refuse a root link.
        self.handle=self.kernel.CreateFileW(str(self.root),0xC0100000,3,None,3,0x02200000,None)
        if self.handle==ct.c_void_p(-1).value:
            self.handle=None;raise ct.WinError(ct.get_last_error())
        class Info(ct.Structure):
            _fields_=[('attributes',w.DWORD),('creation',w.FILETIME),('access',w.FILETIME),('write',w.FILETIME),
                      ('serial',w.DWORD),('size_hi',w.DWORD),('size_lo',w.DWORD),('links',w.DWORD),('index_hi',w.DWORD),('index_lo',w.DWORD)]
        self.kernel.GetFileInformationByHandle.argtypes=[w.HANDLE,ct.POINTER(Info)];self.kernel.GetFileInformationByHandle.restype=w.BOOL
        info=Info()
        if not self.kernel.GetFileInformationByHandle(self.handle,ct.byref(info)):raise ct.WinError(ct.get_last_error())
        if info.attributes&0x400 or not info.attributes&0x10:raise ProbeError('Opened root is reparse or not directory.')
        self.kernel.GetFinalPathNameByHandleW.argtypes=[w.HANDLE,w.LPWSTR,w.DWORD,w.DWORD];self.kernel.GetFinalPathNameByHandleW.restype=w.DWORD
        buf=ct.create_unicode_buffer(32768)
        n=self.kernel.GetFinalPathNameByHandleW(self.handle,buf,len(buf),1)
        if not n or n>=len(buf):raise ProbeError('Unable to bind volume identity.')
        self.canonical=buf.value
        if self.expected_volume and self.canonical.rstrip('\\').lower()!=self.expected_volume.rstrip('\\').lower():
            raise ProbeError('Opened volume differs from expected identity.')
    def open(self,name,create=False):
        if not re.fullmatch(r'[A-Za-z0-9._-]+',name):raise ProbeError('Relative filename required.')
        if os.name!='nt':
            flags=(os.O_RDWR|os.O_CREAT|os.O_EXCL if create else os.O_RDONLY|os.O_NONBLOCK)|os.O_NOFOLLOW
            return os.open(name,flags,0o600,dir_fd=self.fd)
        import msvcrt
        ct=self.ct;w=self.w
        class Unicode(ct.Structure):
            _fields_=[('length',w.USHORT),('maximum',w.USHORT),('buffer',ct.c_void_p)]
        class Attributes(ct.Structure):
            _fields_=[('length',w.ULONG),('root',w.HANDLE),('name',ct.POINTER(Unicode)),('attributes',w.ULONG),('security',ct.c_void_p),('qos',ct.c_void_p)]
        class StatusUnion(ct.Union):
            _fields_=[('status',w.LONG),('pointer',ct.c_void_p)]
        class Status(ct.Structure):
            _fields_=[('value',StatusUnion),('information',ct.c_size_t)]
        text=ct.create_unicode_buffer(name);length=len(name.encode('utf-16-le'))
        unicode=Unicode(length,length+2,ct.addressof(text))
        attrs=Attributes(ct.sizeof(Attributes),self.handle,ct.pointer(unicode),0x1040,None,None)
        status=Status();handle=w.HANDLE()
        api=self.ntdll.NtCreateFile
        api.argtypes=[ct.POINTER(w.HANDLE),w.ULONG,ct.POINTER(Attributes),ct.POINTER(Status),ct.c_void_p,w.ULONG,w.ULONG,w.ULONG,w.ULONG,ct.c_void_p,w.ULONG]
        api.restype=w.LONG
        # FILE_CREATE is exclusive. RootDirectory is the held root handle.
        # OBJ_DONT_REPARSE, FILE_OPEN_REPARSE_POINT, NON_DIRECTORY_FILE and
        # synchronous I/O avoid path traversal and permit fsync/readback.
        code=api(ct.byref(handle),(0xC0000000 if create else 0x80000000)|0x100000,ct.byref(attrs),ct.byref(status),None,0x80,0 if create else 1,2 if create else 1,0x200060,None,0)
        if code<0:
            self.ntdll.RtlNtStatusToDosError.argtypes=[w.LONG];self.ntdll.RtlNtStatusToDosError.restype=w.ULONG
            raise ct.WinError(self.ntdll.RtlNtStatusToDosError(code))
        try:return msvcrt.open_osfhandle(handle.value,os.O_BINARY|(os.O_RDWR if create else os.O_RDONLY))
        except Exception:self.kernel.CloseHandle(handle);raise

def _read_marker(fd,expected):
    info=os.fstat(fd)
    if not stat.S_ISREG(info.st_mode) or getattr(info,'st_file_attributes',0)&getattr(stat,'FILE_ATTRIBUTE_REPARSE_POINT',1024):raise ProbeError('Nonregular/reparse marker refused.')
    if info.st_size>8192:raise ProbeError('Oversized marker.')
    os.lseek(fd,0,os.SEEK_SET);m=json.loads(os.read(fd,8193).decode('utf-8-sig'))
    if m.get('schema_version')!=1 or m.get('provider_kind')!='cloud-block' or m.get('cloud_volume_id')!=expected:raise ProbeError('Cloud marker identity mismatch.')
    return m

def probe(root,expected,expected_volume=None):
    root=Path(root).absolute()
    try:
        with _BoundDirectory(root,expected_volume) as bound:
            marker_fd=bound.open('.devbox-cloud-volume.json')
            try:
                _read_marker(marker_fd,expected)
                filename='.devbox-cloud-canary-'+uuid.uuid4().hex+'.bin';payload=os.urandom(65536)
                fd=bound.open(filename,create=True)
                try:
                    view=memoryview(payload)
                    while view:
                        n=os.write(fd,view)
                        if n<=0:raise ProbeError('Incomplete canary write.')
                        view=view[n:]
                    os.fsync(fd);os.lseek(fd,0,os.SEEK_SET)
                    blocks=[]
                    while True:
                        block=os.read(fd,65536)
                        if not block:break
                        blocks.append(block)
                    if b''.join(blocks)!=payload:raise ProbeError('Canary readback mismatch.')
                finally:os.close(fd)
                _read_marker(marker_fd,expected)
                return {'schema_version':1,'status':'readback_verified','file':filename,'bytes':len(payload),
                        'sha256':hashlib.sha256(payload).hexdigest(),'scope':'device_flush_and_local_readback_only',
                        'cloud_crash_durability_proven':False}
            finally:os.close(marker_fd)
    except (OSError,ValueError,TypeError,AttributeError) as e:raise ProbeError(str(e)) from e

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--root',default='E:\\');p.add_argument('--cloud-volume-id',required=True);p.add_argument('--volume-unique-id',required=True)
    args=p.parse_args()
    if os.name!='nt' or Path(args.root).absolute()!=Path('E:\\'):
        print('CLOUD E REFUSED: command-line probe is Windows E: only.',file=sys.stderr);return 2
    try:print(json.dumps(probe(args.root,args.cloud_volume_id,args.volume_unique_id)));return 0
    except ProbeError as e:print('CLOUD E PROBE FAILED: '+str(e),file=sys.stderr);return 2

if __name__=='__main__':sys.exit(main())
