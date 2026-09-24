#!/usr/bin/env python3
"""Extract and exercise a native archive without using a Racket installation."""
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tarfile
import tempfile
import zipfile


def main():
    archive = Path(sys.argv[1]).resolve()
    expected = archive.with_name(archive.name + '.sha256').read_text().split()[0]
    if hashlib.sha256(archive.read_bytes()).hexdigest() != expected:
        raise RuntimeError('Archive checksum mismatch')
    with tempfile.TemporaryDirectory(prefix='v2-lens-isolated-') as temporary:
        root = Path(temporary)
        if platform.system() == 'Darwin':
            subprocess.run(['ditto', '-x', '-k', str(archive), str(root)], check=True)
        elif archive.name.endswith('.tar.gz'):
            with tarfile.open(archive) as bundle:
                bundle.extractall(root, filter='data')
        else:
            with zipfile.ZipFile(archive) as bundle:
                bundle.extractall(root)
        distribution = next(p for p in root.iterdir() if p.is_dir() and p.name.startswith('V2-Lens-'))
        metadata = json.loads((distribution / 'build-info.json').read_text())
        if metadata.get('dirty') is not False:
            raise RuntimeError('Refusing an archive built from an unclean checkout')
        system = metadata['platform']
        if system == 'macos':
            app = distribution / 'V2 Lens.app'
            subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
            executable = app / 'Contents/MacOS/V2 Lens'
            # Every Mach-O dependency must resolve inside the archive or to an OS library.
            for path in app.rglob('*'):
                if not path.is_file() or path.is_symlink():
                    continue
                with path.open('rb') as stream:
                    magic = stream.read(4)
                if magic not in (b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xca\xfe\xba\xbe'):
                    continue
                linked = subprocess.check_output(['otool', '-L', str(path)], text=True)
                # A dylib's install ID is its identity, not a loaded dependency.
                ids = subprocess.check_output(['otool', '-D', str(path)], text=True).splitlines()[1:]
                for line in linked.splitlines()[1:]:
                    dependency = line.strip().split(' (')[0]
                    if dependency in ids:
                        continue
                    if dependency.startswith('/') and not dependency.startswith(('/usr/lib/', '/System/Library/')):
                        raise RuntimeError(f'External build-machine dependency: {path}: {dependency}')
        elif system == 'windows':
            executable = distribution / 'V2-Lens.exe'
        else:
            executable = distribution / 'bin/v2-lens'
        cwd = root / 'empty working directory'
        cwd.mkdir()
        env = os.environ.copy()
        for name in list(env):
            if name.startswith(('PLT', 'RACKET', 'DYLD_', 'LD_LIBRARY_PATH')):
                env.pop(name)
        # Windows still needs OS DLLs. Unix subprocesses need no PATH tools.
        env['PATH'] = str(Path(env.get('SystemRoot', 'C:/Windows')) / 'System32') if system == 'windows' else str(cwd)
        for name in ('PLTUSERHOME', 'PLTCONFIGDIR', 'PLTCOLLECTS', 'PLTADDONDIR'):
            directory = root / name
            directory.mkdir()
            env[name] = str(directory)
        result = subprocess.run([str(executable), '--smoke-test'], cwd=cwd, env=env,
                                capture_output=True, text=True, timeout=60)
        print(result.stdout, end='')
        print(result.stderr, end='', file=sys.stderr)
        if result.returncode != 0 or 'V2_LENS_SMOKE_OK' not in result.stdout:
            raise RuntimeError(f'Packaged smoke test failed: exit {result.returncode}')
        print(f'Verified standalone archive: {archive.name}')


if __name__ == '__main__':
    main()
