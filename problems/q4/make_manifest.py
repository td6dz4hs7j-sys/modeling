"""Hash the portable bundle after regeneration; no user-specific paths."""
import hashlib
import importlib.metadata
import json
import platform
from pathlib import Path
ROOT=Path(__file__).resolve().parent
def files():
    return sorted(p for p in ROOT.rglob('*') if p.is_file() and p!=ROOT/'manifest.json' and '__pycache__' not in p.parts and '.venv' not in p.parts and p.suffix not in ('.pyc','.tmp'))
def main():
    d=dict(command='python run_problem4.py',verification='python verify_bundle.py',random_seed=None,
           deterministic=True,python=platform.python_version(),
           dependencies={n:importlib.metadata.version(n) for n in ('numpy','scipy','h5py','openpyxl')},
           files=[dict(path=p.relative_to(ROOT).as_posix(),bytes=p.stat().st_size,sha256=hashlib.sha256(p.read_bytes()).hexdigest()) for p in files()])
    (ROOT/'manifest.json').write_text(json.dumps(d,ensure_ascii=False,indent=2),encoding='utf-8')
if __name__=='__main__':main()
