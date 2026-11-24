import base64, hashlib, io, zipfile
from pathlib import Path
parts=sorted(Path('.').glob('source-part-*.b64'))
data=base64.b64decode(''.join(p.read_text().strip() for p in parts))
assert hashlib.sha256(data).hexdigest()=='df2f788a40944afa6871b530bd41f79e2263a74526c5332d6060ab9e39bc0988'
root=Path('source');root.mkdir(exist_ok=False)
with zipfile.ZipFile(io.BytesIO(data)) as archive:
 for name in archive.namelist():
  path=Path(name)
  if path.is_absolute() or '..' in path.parts: raise ValueError('Unsafe path')
 archive.extractall(root)
print('158 source files restored in source/. See source/README.md.')
