"""Build a portable, locally signed test archive, never from a user's state folder."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
import hashlib
import json
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

source = Path(__file__).resolve().parents[1]
app, output = (Path(arg).resolve() for arg in sys.argv[1:3])
info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
version = info['CFBundleShortVersionString']
for p in app.rglob('*'):
    assert p.name not in {'Install.json', 'identity.pk8', 'certificate.p7b'}, f'Local installation data: {p.name}'
    assert p.suffix != '.log', 'Diagnostic logs must never be packaged.'
web = app/'Contents/Resources/engine/web/dist'
page = (web/'index.html').read_text()
assets = re.findall(r'(?:src|href)="(\./assets/[^\"]+)"', page)
assert assets and all((web/p).is_file() for p in assets), 'Missing built viewer assets.'
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
assert subprocess.check_output(['lipo','-archs',str(app/'Contents/MacOS/DashLink')]).decode().strip() == 'arm64'

excluded = {'.git','.gradle','.kotlin','node_modules','.build-local','build','.DS_Store'}
private = {'identity.pk8','certificate.p7b','Install.json'}
with tempfile.TemporaryDirectory(prefix='dashlink-release-') as temporary:
    release = Path(temporary)/f'DashLink-{version}-test'
    release.mkdir()
    shutil.copytree(app,release/'DashLink.app',symlinks=True,copy_function=shutil.copy)
    for name in ['README.md','NOTICE.txt','RELEASING.md']:
        shutil.copyfile(source/name,release/name)
    if (source/'TEST-REPORT.txt').exists(): shutil.copyfile(source/'TEST-REPORT.txt',release/'TEST-REPORT.txt')
    shutil.copyfile(source/'Receiver/LICENSE',release/'LICENSE.txt')
    with ZipFile(release/'DashLink-source.zip','w',ZIP_DEFLATED) as archive:
        for p in sorted(source.rglob('*')):
            parts = p.relative_to(source).parts
            if p.is_file() and not p.is_symlink() and not any(part in excluded for part in parts) and p.name not in private:
                archive.write(p,Path('DashLink-source')/p.relative_to(source))
    manifest = {'version':version, 'build':info['CFBundleVersion'], 'architecture':'arm64',
                'minimumMacOS':info['LSMinimumSystemVersion'], 'channel':'experimental-test',
                'notarized':False, 'appleCarPlayCertified':False,
                'binarySHA256':hashlib.sha256((app/'Contents/MacOS/DashLink').read_bytes()).hexdigest()}
    (release/'release.json').write_text(json.dumps(manifest,indent=2)+'\n')
    subprocess.run(['codesign','--verify','--deep','--strict',str(release/'DashLink.app')],check=True)
    output.parent.mkdir(parents=True,exist_ok=True)
    subprocess.run(['ditto','--norsrc','-c','-k','--keepParent',str(release),str(output)],check=True)
    with ZipFile(output) as archive:
        assert not any(Path(p).name in private or p.endswith('.log') for p in archive.namelist())
        assert archive.read(f'{release.name}/DashLink.app/Contents/Info.plist') == (app/'Contents/Info.plist').read_bytes()
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_suffix('.zip.sha256').write_text(f'{digest}  {output.name}\n')
print(f'Packaged {output.name}: app, instructions, source, notices, and release metadata; no local state.')
