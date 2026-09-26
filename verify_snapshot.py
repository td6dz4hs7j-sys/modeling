"""Verify published bytes; refresh only after independently validating results.

python verify_snapshot.py
python verify_snapshot.py --refresh
python verify_snapshot.py --git-rev HEAD  # compare committed blobs as well
"""
import argparse
import hashlib
import io
import json
import subprocess
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
MANIFEST = ROOT / 'latest_artifacts_manifest.json'

def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args])

def refresh():
    paths = sorted(set(x.decode('utf-8') for x in git('ls-files', '-c', '-o', '--exclude-standard', '-z', '--', '.').split(b'\0') if x))
    files = []
    for name in paths:
        p = ROOT / name
        if p == MANIFEST or not p.is_file() or '__pycache__' in p.parts:
            continue
        files.append(dict(path=name, bytes=p.stat().st_size, sha256=hashlib.sha256(p.read_bytes()).hexdigest()))
    MANIFEST.write_text(json.dumps(dict(scope='Published branch snapshot, current and explicitly labelled historical evidence; excludes ignored inputs, caches and this manifest.', files=files), ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(f'Recorded {len(files)} published files')

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--refresh',action='store_true');ap.add_argument('--git-rev');args=ap.parse_args()
    if args.refresh:refresh()
    obj=json.loads(MANIFEST.read_text(encoding='utf-8'))
    records=obj if isinstance(obj,list) else obj['files']
    for r in records:
        p=ROOT/r['path'];assert p.is_file(),r['path']
        assert hashlib.sha256(p.read_bytes()).hexdigest()==r['sha256'],r['path']
    if args.git_rev:
        prefix=git('rev-parse','--show-prefix').decode().strip()
        top=git('rev-parse','--show-toplevel').decode().strip()
        data=subprocess.check_output(['git','-C',top,'archive','--format=tar',args.git_rev,*([prefix] if prefix else [])])
        with tarfile.open(fileobj=io.BytesIO(data),mode='r:') as tar:
            for r in records:
                member=tar.extractfile(prefix+r['path']);assert member is not None,r['path']
                assert hashlib.sha256(member.read()).hexdigest()==r['sha256'],r['path']
    print(f'PASS: {len(records)} published file SHA256 values'+(f' and {args.git_rev} blobs' if args.git_rev else ''))

if __name__=='__main__':main()
