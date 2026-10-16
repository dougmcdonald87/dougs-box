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
import threading
import uuid
import zipfile

MAX_BYTES = 8 * 1024**3
PART_BYTES = 512 * 1024**2
MANIFEST_BYTES = 1024**2
PREFIX = 'devbox-checkpoint-v1-'
TAG = re.compile(r'devbox-checkpoint-v1-(production|ci-\d+-\d+)-\d{8}T\d{6}Z-[0-9a-f]{32}')
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
    fields = {'schema','repository','channel','generation','snapshot_id','receipt_snapshot_id','bytes','sha256','parts'}
    if not isinstance(value, dict) or set(value) != fields or value['schema'] != 1:
        raise CheckpointError('Invalid checkpoint schema')
    if value['repository'] != remote.repository or value['channel'] != remote.channel or value['generation'] != tag or not TAG.fullmatch(tag) or TAG.fullmatch(tag).group(1) != remote.channel:
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
        generation = PREFIX + remote.channel + '-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ-') + uuid.uuid4().hex
        manifest = {'schema':1,'repository':remote.repository,'channel':remote.channel,'generation':generation,
                    'snapshot_id':snapshot_id,'receipt_snapshot_id':receipt_id,
                    'bytes':Path(archive).stat().st_size,'sha256':digest(archive),'parts':[]}
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            packed_hash = hashlib.sha256()
            with open(archive,'rb') as stream:
                number = 0
                while stream.tell() < manifest['bytes']:
                    piece = root / f'part-{number:04d}.bin'
                    remaining = min(part_bytes,manifest['bytes']-stream.tell())
                    with piece.open('xb') as output:
                        while remaining:
                            block = stream.read(min(1024**2,remaining))
                            if not block:raise CheckpointError('Archive changed during packing')
                            output.write(block);packed_hash.update(block);remaining -= len(block)
                    manifest['parts'].append({'name':piece.name,'bytes':piece.stat().st_size,'sha256':digest(piece)})
                    number += 1
            if packed_hash.hexdigest() != manifest['sha256']:
                raise CheckpointError('Archive changed after verification')
            validate_manifest(manifest,remote,generation,max_bytes)
            # Every mutation is confined to a fresh draft generation.
            remote.create_draft(generation)
            for part in manifest['parts']:
                source = root / part['name'];remote.upload(generation,source)
                downloaded = root / ('readback-' + part['name'])
                remote.download(generation,part['name'],downloaded,max_bytes=part['bytes'])
                if downloaded.stat().st_size != part['bytes'] or digest(downloaded) != part['sha256']:
                    raise CheckpointError('Remote piece readback failed')
            record = root/'checkpoint.json'
            record.write_text(json.dumps(manifest,separators=(',',':')),encoding='utf-8')
            remote.upload(generation,record)
            check = root/'manifest-readback.json';remote.download(generation,'checkpoint.json',check,max_bytes=MANIFEST_BYTES)
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
                remote.download(tag,'checkpoint.json',manifest_path,max_bytes=MANIFEST_BYTES)
                if manifest_path.stat().st_size > MANIFEST_BYTES:raise CheckpointError('Manifest too large')
                value = validate_manifest(json.loads(manifest_path.read_text()),remote,tag,max_bytes)
                assembled = root/'assembled.zip'
                with assembled.open('wb') as output:
                    for part in value['parts']:
                        piece = root/part['name'];remote.download(tag,part['name'],piece,max_bytes=part['bytes'])
                        if piece.stat().st_size != part['bytes'] or digest(piece) != part['sha256']:
                            raise CheckpointError('Cloud piece corrupted')
                        with piece.open('rb') as stream:shutil.copyfileobj(stream,output,1024**2)
                    output.flush();os.fsync(output.fileno())
                if assembled.stat().st_size != value['bytes'] or digest(assembled) != value['sha256']:
                    raise CheckpointError('Cloud archive corrupted')
                archive_check(assembled,max_bytes)
                if verify is not None and verify(assembled,value) is not True:
                    raise CheckpointError('Cryptographic repository verification failed')
                os.replace(assembled,destination)
                return value
            except Exception:
                # Incomplete/corrupt published generation cannot erase older state.
                continue
    raise CheckpointError('No valid cloud checkpoint; existing destination preserved')


class GitHubRemote:
    def __init__(self,repository,channel):
        if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+',repository) or repository != os.environ.get('GITHUB_REPOSITORY'):
            raise CheckpointError('GitHub repository identity mismatch')
        if not os.environ.get('GH_TOKEN'):raise CheckpointError('GitHub job credential unavailable')
        self.repository=repository
        if channel == 'production':
            if os.environ.get('DEVBOX_ISOLATED_TEST') == '1':raise CheckpointError('CI fixtures cannot use production checkpoint channel')
        elif channel != 'ci-' + os.environ.get('GITHUB_RUN_ID','') + '-' + os.environ.get('GITHUB_RUN_ATTEMPT',''):
            raise CheckpointError('CI checkpoint channel identity mismatch')
        if not re.fullmatch(r'production|ci-\d+-\d+',channel):raise CheckpointError('Invalid checkpoint channel')
        self.channel=channel
        self.drafts={}
    def call(self,*args):
        result=subprocess.run(['gh',*args,'--repo',self.repository],capture_output=True,text=True,timeout=300)
        if result.returncode:
            stage=' '.join(args[:2]) if tuple(args[:2]) in (('release','create'),('release','view'),('release','upload'),('release','edit')) else 'command'
            status=re.search(r'\bHTTP\s+([1-5][0-9]{2})\b',result.stderr or '')
            detail=('; HTTP '+status.group(1)) if status else ''
            error=result.stderr or ''
            if 'Resource not accessible by integration' in error:detail+='; integration permission'
            elif 'workflow' in error.lower() and 'refusing' in error.lower():detail+='; workflow permission'
            elif 'Unknown JSON field' in error:detail+='; unsupported JSON field'
            elif 'unknown flag' in error:detail+='; unsupported CLI option'
            raise CheckpointError('GitHub transport operation failed ('+stage+'; exit '+str(result.returncode)+detail+')')
        return result.stdout
    def create_draft(self,tag):
        revision=os.environ.get('GITHUB_SHA')
        if not revision or not re.fullmatch(r'[0-9a-f]{40}',revision):raise CheckpointError('Pinned GitHub revision unavailable')
        self.call('release','create',tag,'--draft','--prerelease','--latest=false','--target',revision,
                  '--title','Encrypted DevBox development checkpoint','--notes','Verified encrypted software-development state. No plaintext user state.')
        identity=json.loads(self.call('release','view',tag,'--json','databaseId'))['databaseId']
        if type(identity)is not int or identity<=0:raise CheckpointError('Draft release identity unavailable')
        self.drafts[tag]=identity
    def upload(self,tag,path):self.call('release','upload',tag,str(path))
    def api(self,endpoint):
        result=subprocess.run(['gh','api',endpoint],capture_output=True,text=True,timeout=300)
        if result.returncode:raise CheckpointError('GitHub metadata operation failed')
        return json.loads(result.stdout)
    def download(self,tag,name,destination,max_bytes):
        if type(max_bytes)is not int or not 0<max_bytes<=PART_BYTES:raise CheckpointError('Invalid download bound')
        draft_id=getattr(self,'drafts',{}).get(tag)
        endpoint=f'repos/{self.repository}/releases/{draft_id}' if draft_id else f'repos/{self.repository}/releases/tags/{tag}'
        release=self.api(endpoint)
        matches=[asset for asset in release['assets'] if asset['name']==name]
        if len(matches)!=1 or type(matches[0]['size'])is not int or not 0<matches[0]['size']<=max_bytes:
            raise CheckpointError('Remote asset missing or exceeds bound')
        asset=matches[0]
        if type(asset['id'])is not int or asset['id']<=0:raise CheckpointError('Invalid asset identity')
        # gh handles authenticated API redirects. Never retain credential-bearing URLs.
        # Bound both preflight metadata and actual streaming bytes, including races.
        with tempfile.TemporaryDirectory(dir=Path(destination).parent) as temp:
            staged=Path(temp)/'asset.bin'
            process=subprocess.Popen(['gh','api',f'repos/{self.repository}/releases/assets/{asset["id"]}',
                                      '-H','Accept: application/octet-stream'],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL)
            expired=threading.Event()
            def expire():expired.set();process.kill()
            timer=threading.Timer(300,expire);timer.start()
            try:
                count=0
                with staged.open('xb') as output:
                    while True:
                        block=process.stdout.read(min(1024**2,max_bytes-count+1))
                        if not block:break
                        count+=len(block)
                        if count>max_bytes:raise CheckpointError('Remote stream exceeds bound')
                        output.write(block)
                if process.wait()!=0 or expired.is_set() or count!=asset['size']:
                    raise CheckpointError('Bounded asset transfer failed')
                os.replace(staged,destination)
            finally:
                timer.cancel()
                if process.poll() is None:process.kill()
                process.wait();process.stdout.close()
    def finish(self,tag):
        self.call('release','edit',tag,'--draft=false','--prerelease','--latest=false')
        if json.loads(self.call('release','view',tag,'--json','isDraft'))['isDraft']:
            raise CheckpointError('Cloud publication not acknowledged')
    def generations(self):
        found=[];page=1
        while True:
            rows=self.api(f'repos/{self.repository}/releases?per_page=100&page={page}')
            found.extend(row['tag_name'] for row in rows if not row['draft'] and TAG.fullmatch(row['tag_name']) and TAG.fullmatch(row['tag_name']).group(1)==self.channel)
            if len(rows)<100:break
            page+=1
        return found


def crypto_verify(archive,restic,record):
    if not os.environ.get('RESTIC_PASSWORD'):raise CheckpointError('Backup key unavailable')
    archive_check(archive)
    with tempfile.TemporaryDirectory() as temp:
        with zipfile.ZipFile(archive) as source:source.extractall(temp)
        result=subprocess.run([restic,'--repo',temp,'check','--read-data'],capture_output=True,timeout=300)
        if result.returncode!=0:return False
        listed=subprocess.run([restic,'--repo',temp,'snapshots','--json'],capture_output=True,timeout=300)
        if listed.returncode!=0:return False
        rows=json.loads(listed.stdout)
        data=[row for row in rows if row['id']==record['snapshot_id'] and 'devbox-auto' in row.get('tags',[])]
        receipts=[row for row in rows if row['id']==record['receipt_snapshot_id'] and 'devbox-verified-receipt-v1' in row.get('tags',[])]
        if len(data)!=1 or len(receipts)!=1:return False
        stage=Path(temp)/'verified-receipt'
        restored=subprocess.run([restic,'--repo',temp,'restore',record['receipt_snapshot_id'],'--target',str(stage)],capture_output=True,timeout=300)
        if restored.returncode!=0:return False
        files=list(stage.rglob('DEVBOX-VERIFIED-RECEIPT.json'))
        if len(files)!=1 or files[0].is_symlink():return False
        proof=json.loads(files[0].read_text(encoding='utf-8-sig'))
        return proof.get('version')==1 and proof.get('snapshotId')==record['snapshot_id'] and bool(re.fullmatch('[0-9a-fA-F]{64}',str(proof.get('canaryHash',''))))


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('operation',choices=['publish','fetch','probe'])
    parser.add_argument('--repository',required=True)
    parser.add_argument('--channel',required=True)
    parser.add_argument('--archive',required=True)
    parser.add_argument('--restic-exe',required=True)
    parser.add_argument('--snapshot-id');parser.add_argument('--receipt-id')
    args=parser.parse_args()
    try:
        remote=GitHubRemote(args.repository,args.channel)
        if args.operation=='probe':
            record={'generations':remote.generations()}
        elif args.operation=='publish':
            if not crypto_verify(args.archive,args.restic_exe,{'snapshot_id':args.snapshot_id,'receipt_snapshot_id':args.receipt_id}):raise CheckpointError('Encrypted repository verification failed; no upload')
            record=publish(args.archive,args.snapshot_id or '',args.receipt_id or '',remote)
        else:
            record=fetch_latest(remote,args.archive,verify=lambda p,r:crypto_verify(p,args.restic_exe,r))
        print(json.dumps(record,separators=(',',':')))
    except Exception as error:
        # Owned error messages contain no raw subprocess output, URLs or credentials.
        detail=str(error) if isinstance(error,CheckpointError) else type(error).__name__
        parser.exit(2,'Cloud checkpoint failed ('+detail+'); no save/restore success claimed.\n')
