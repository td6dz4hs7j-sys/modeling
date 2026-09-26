"""Refresh relative-path delivery hashes; raw inputs and local caches stay private."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parent
records = []
for p in sorted(root.rglob('*')):
    rel = p.relative_to(root)
    if not p.is_file() or any(x in {'input', 'cache', '__pycache__'} for x in rel.parts):
        continue
    if p.name == 'manifest.json' or p.name.startswith('local_verify.'):
        continue
    records.append({'path': rel.as_posix(), 'bytes': p.stat().st_size,
                    'sha256': hashlib.sha256(p.read_bytes()).hexdigest()})
(root / 'manifest.json').write_text(json.dumps({
    'scope': 'Published Q3 bundle; excludes manifest itself, raw input, cache and local logs',
    'files': records}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(f'{len(records)} files recorded')
