"""Bounded append-only GitHub checkpoint transport. CLI verifies Restic crypto.

Library callers supply encrypted repositories and their own cryptographic verifier.
No Windows/user files are restored here; only the encrypted repository is staged.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile
import uuid
import zipfile

MAX_BYTES = 8 * 1024**3
PART_BYTES = 512 * 1024**2
MANIFEST_BYTES = 1024**2
PREFIX = 'devbox-checkpoint-v1-'
TAG = re.compile(r'devbox-checkpoint-v1-\d{8}T\d{6}Z-[0-9a-f]{32}')
HEX = re.compile(r'[0-9a-f]{64}')


class CheckpointError(RuntimeError):
    pass


def digest(path):
    result = hashlib.sha256()
    with open(path, 'rb') as stream:
        for block in iter(lambda: stream.read(1024**2), b''):
            result.update(block)
    return result.hexdigest()


def archive_check(path, max_bytes=MAX_BYTES):
    """Structural guard only; native Restic check is the cryptographic gate."""
    if Path(path).is_symlink() or not 0 < Path(path).stat().st_size <= max_bytes:
        raise CheckpointError('Archive unavailable or exceeds checkpoint limit')
    seen = set()
    total = 0
    with zipfile.ZipFile(path) as archive:
        for entry in archive.infolist():
            name = entry.filename
            if name.casefold() in seen or stat.S_ISLNK(entry.external_attr >> 16):
                raise CheckpointError('Duplicate or link archive entry')
            seen.add(name.casefold())
            if entry.is_dir():
                valid = re.fullmatch(r'(keys|snapshots|index|locks|data)(/[0-9a-f]{2})?/', name)
            else:
                valid = name == 'config' or re.fullmatch(r'(keys|snapshots|index|locks)/[0-9a-f]{64}|data/[0-9a-f]{2}/[0-9a-f]{64}', name)
            if not valid:
                raise CheckpointError('Not a scoped Restic repository archive')
            total += entry.file_size
            if total > max_bytes:
                raise CheckpointError('Inflated repository exceeds checkpoint limit')
        if 'config' not in seen or not any(n.startswith('keys/') and not n.endswith('/') for n in seen):
            raise CheckpointError('Encrypted repository config/key missing')


def validate_manifest(value, remote, tag, max_bytes):
    fields = {'schema','repository','generation','snapshot_id','receipt_snapshot_id','bytes','sha256','parts'}
    if not isinstance(value, dict) or set(value) != fields or value['schema'] != 1:
        raise CheckpointError('Invalid checkpoint schema')
    if value['repository'] != remote.repository or value['generation'] != tag or not TAG.fullmatch(tag):
        raise CheckpointError('Checkpoint identity mismatch')
    for field in ('snapshot_id','receipt_snapshot_id','sha256'):
        if not isinstance(value[field], str) or not HEX.fullmatch(value[field]):
            raise CheckpointError('Invalid checkpoint digest/identity')
    if type(value['bytes']) is not int or not 0 < value['bytes'] <= max_bytes:
        raise CheckpointError('Checkpoint size exceeds limit')
    parts = value['parts']
    if not isinstance(parts,list) or not 0 < len(parts) <= 100:
        raise CheckpointError('Invalid piece count')
    total = 0
    for number, piece in enumerate(parts):
        if not isinstance(piece,dict) or set(piece) != {'name','bytes','sha256'}:
            raise CheckpointError('Invalid piece metadata')
        if piece['name'] != f'part-{number:04d}.bin' or type(piece['bytes']) is not int or not 0 < piece['bytes'] <= PART_BYTES:
            raise CheckpointError('Invalid piece name/size')
        if not isinstance(piece['sha256'],str) or not HEX.fullmatch(piece['sha256']):
            raise CheckpointError('Invalid piece hash')
        total += piece['bytes']
    if total != value['bytes']:
        raise CheckpointError('Incomplete piece coverage')
    return value


def publish(archive, snapshot_id, receipt_id, remote, max_bytes=MAX_BYTES, part_bytes=PART_BYTES):
    try:
        if not 0 < max_bytes <= MAX_BYTES or not 0 < part_bytes <= PART_BYTES:
            raise CheckpointError('Invalid transport limit')
        archive_check(archive,max_bytes)
        if not HEX.fullmatch(snapshot_id) or not HEX.fullmatch(receipt_id):
            raise CheckpointError('Verified snapshot IDs required')
        generation = PREFIX + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ-') + uuid.uuid4().hex
        manifest = {'schema':1,'repository':remote.repository,'generation':generation,
                    'snapshot_id':snapshot_id,'receipt_snapshot_id':receipt_id,
                    'bytes':Path(archive).stat().st_size,'sha256':digest(archive),'parts':[]}
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            with open(archive,'rb') as stream:
                number = 0
                while stream.tell() < manifest['bytes']:
                    piece = root / f'part-{number:04d}.bin'
                    remaining = min(part_bytes,manifest['bytes']-stream.tell())
                    with piece.open('xb') as output:
                        while remaining:
                            block = stream.read(min(1024**2,remaining))
                            if not block:raise CheckpointError('Archive changed during packing')
                            output.write(block);remaining -= len(block)
                    manifest['parts'].append({'name':piece.name,'bytes':piece.stat().st_size,'sha256':digest(piece)})
                    number += 1
            validate_manifest(manifest,remote,generation,max_bytes)
            # Every mutation is confined to a fresh draft generation.
            remote.create_draft(generation)
            for part in manifest['parts']:
                source = root / part['name'];remote.upload(generation,source)
                downloaded = root / ('readback-' + part['name'])
                remote.download(generation,part['name'],downloaded)
                if downloaded.stat().st_size != part['bytes'] or digest(downloaded) != part['sha256']:
                    raise CheckpointError('Remote piece readback failed')
            record = root/'checkpoint.json'
            record.write_text(json.dumps(manifest,separators=(',',':')),encoding='utf-8')
            remote.upload(generation,record)
            check = root/'manifest-readback.json';remote.download(generation,'checkpoint.json',check)
            if check.stat().st_size > MANIFEST_BYTES or json.loads(check.read_text()) != manifest:
                raise CheckpointError('Remote manifest readback failed')
            remote.finish(generation)
            return manifest
    except CheckpointError:raise
    except Exception as error:
        raise CheckpointError('Checkpoint publication failed; previous generations retained') from error


def fetch_latest(remote, destination, max_bytes=MAX_BYTES, verify=None):
    destination = Path(destination)
    if not 0 < max_bytes <= MAX_BYTES or destination.is_symlink():
        raise CheckpointError('Invalid recovery destination/limit')
    destination.parent.mkdir(parents=True,exist_ok=True)
    # All failed candidates stay in an owned staging folder, never destination.
    with tempfile.TemporaryDirectory(dir=destination.parent) as temp:
        root = Path(temp)
        for tag in remote.generations():
            if not isinstance(tag,str) or not TAG.fullmatch(tag):continue
            try:
                manifest_path = root/'checkpoint.json'
                remote.download(tag,'checkpoint.json',manifest_path)
                if manifest_path.stat().st_size > MANIFEST_BYTES:raise CheckpointError('Manifest too large')
                value = validate_manifest(json.loads(manifest_path.read_text()),remote,tag,max_bytes)
                assembled = root/'assembled.zip'
                with assembled.open('wb') as output:
                    for part in value['parts']:
                        piece = root/part['name'];remote.download(tag,part['name'],piece)
                        if piece.stat().st_size != part['bytes'] or digest(piece) != part['sha256']:
                            raise CheckpointError('Cloud piece corrupted')
                        with piece.open('rb') as stream:shutil.copyfileobj(stream,output,1024**2)
                    output.flush();os.fsync(output.fileno())
                if assembled.stat().st_size != value['bytes'] or digest(assembled) != value['sha256']:
                    raise CheckpointError('Cloud archive corrupted')
                archive_check(assembled,max_bytes)
                if verify is not None and verify(assembled) is not True:
                    raise CheckpointError('Cryptographic repository verification failed')
                os.replace(assembled,destination)
                return value
            except Exception:
                # Incomplete/corrupt published generation cannot erase older state.
                continue
    raise CheckpointError('No valid cloud checkpoint; existing destination preserved')


class GitHubRemote:
    def __init__(self,repository):
        if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+',repository) or repository != os.environ.get('GITHUB_REPOSITORY'):
            raise CheckpointError('GitHub repository identity mismatch')
        if not os.environ.get('GH_TOKEN'):raise CheckpointError('GitHub job credential unavailable')
        self.repository=repository
    def call(self,*args):
        result=subprocess.run(['gh',*args,'--repo',self.repository],capture_output=True,text=True,timeout=300)
        if result.returncode:raise CheckpointError('GitHub transport operation failed')
        return result.stdout
    def create_draft(self,tag):
        revision=os.environ.get('GITHUB_SHA')
        if not revision or not re.fullmatch(r'[0-9a-f]{40}',revision):raise CheckpointError('Pinned GitHub revision unavailable')
        self.call('release','create',tag,'--draft','--prerelease','--latest=false','--target',revision,
                  '--title','Encrypted DevBox development checkpoint','--notes','Verified encrypted software-development state. No plaintext user state.')
    def upload(self,tag,path):self.call('release','upload',tag,str(path))
    def download(self,tag,name,destination):
        # gh preserves asset basename. A private subdirectory permits alternate target names.
        with tempfile.TemporaryDirectory(dir=Path(destination).parent) as temp:
            self.call('release','download',tag,'--pattern',name,'--dir',temp)
            os.replace(Path(temp)/name,destination)
    def finish(self,tag):
        self.call('release','edit',tag,'--draft=false','--prerelease','--latest=false')
        if json.loads(self.call('release','view',tag,'--json','isDraft'))['isDraft']:
            raise CheckpointError('Cloud publication not acknowledged')
    def generations(self):
        rows=json.loads(self.call('release','list','--limit','100','--json','tagName,isDraft'))
        return [row['tagName'] for row in rows if not row['isDraft'] and TAG.fullmatch(row['tagName'])]


def crypto_verify(archive,restic):
    if not os.environ.get('RESTIC_PASSWORD'):raise CheckpointError('Backup key unavailable')
    archive_check(archive)
    with tempfile.TemporaryDirectory() as temp:
        with zipfile.ZipFile(archive) as source:source.extractall(temp)
        result=subprocess.run([restic,'--repo',temp,'check','--read-data'],capture_output=True,timeout=300)
        return result.returncode == 0


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('operation',choices=['publish','fetch'])
    parser.add_argument('--repository',required=True)
    parser.add_argument('--archive',required=True)
    parser.add_argument('--restic-exe',required=True)
    parser.add_argument('--snapshot-id');parser.add_argument('--receipt-id')
    args=parser.parse_args()
    try:
        remote=GitHubRemote(args.repository)
        if args.operation=='publish':
            if not crypto_verify(args.archive,args.restic_exe):raise CheckpointError('Encrypted repository verification failed; no upload')
            record=publish(args.archive,args.snapshot_id or '',args.receipt_id or '',remote)
        else:
            record=fetch_latest(remote,args.archive,verify=lambda p:crypto_verify(p,args.restic_exe))
        print(json.dumps(record,separators=(',',':')))
    except Exception:
        parser.exit(2,'Cloud checkpoint failed; no save/restore success claimed.\n')
