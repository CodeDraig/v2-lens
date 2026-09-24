#!/usr/bin/env python3
"""Build a native, runtime-inclusive test distribution with Racket 9.2."""
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def run(*args, **kwargs):
    print('+', ' '.join(map(str, args)), flush=True)
    return subprocess.run(list(map(str, args)), check=True, **kwargs)


def racket_value(expression):
    return subprocess.check_output(['racket', '-e', expression], text=True).strip()


def prepare_mac(app, version):
    """Complete raco's minimal framework layout before signing inside out."""
    contents = app / 'Contents'
    info = contents / 'Info.plist'
    with info.open('rb') as stream:
        metadata = plistlib.load(stream)
    metadata.update(CFBundleIdentifier='io.github.codedraig.v2-lens',
                    CFBundleName='V2 Lens', CFBundleDisplayName='V2 Lens',
                    CFBundleVersion=version.split('-')[0],
                    CFBundleShortVersionString=version.split('-')[0],
                    V2LensReleaseVersion=version)
    with info.open('wb') as stream:
        plistlib.dump(metadata, stream)
    # Some local Racket distributions bundle GUI/OpenSSL dylibs with absolute
    # Homebrew paths. Rewrite references to their bundled peers before signing.
    binaries = []
    for path in contents.rglob('*'):
        if path.is_file() and not path.is_symlink():
            with path.open('rb') as stream:
                magic = stream.read(4)
            if magic in (b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xca\xfe\xba\xbe'):
                binaries.append(path)
    for path in binaries:
        ids = subprocess.check_output(['otool', '-D', str(path)], text=True).splitlines()[1:]
        linked = subprocess.check_output(['otool', '-L', str(path)], text=True)
        for line in linked.splitlines()[1:]:
            dependency = line.strip().split(' (')[0]
            if dependency in ids or not dependency.startswith('/') or dependency.startswith(('/usr/lib/', '/System/Library/')):
                continue
            candidates = [other for other in binaries if other.name == Path(dependency).name]
            if len(candidates) != 1:
                raise RuntimeError(f'Cannot resolve bundled dependency: {path}: {dependency}')
            path.chmod(path.stat().st_mode | 0o200)
            replacement = '@loader_path/' + os.path.relpath(candidates[0], path.parent)
            run('install_name_tool', '-change', dependency, replacement, path)
    for framework in (contents / 'Frameworks').glob('*.framework'):
        versions = framework / 'Versions'
        actual = [p for p in versions.iterdir() if p.is_dir() and not p.is_symlink()]
        if len(actual) != 1:
            raise RuntimeError(f'Unexpected framework versions: {actual}')
        runtime = actual[0]
        resources = runtime / 'Resources'
        resources.mkdir(exist_ok=True)
        framework_info = resources / 'Info.plist'
        if not framework_info.exists():
            with framework_info.open('wb') as stream:
                plistlib.dump({'CFBundleIdentifier': 'org.racket-lang.' + framework.stem,
                               'CFBundleExecutable': framework.stem,
                               'CFBundlePackageType': 'FMWK',
                               'CFBundleVersion': '9.2'}, stream)
        for link, target in [(versions / 'Current', runtime.name),
                             (framework / framework.stem, 'Versions/Current/' + framework.stem),
                             (framework / 'Resources', 'Versions/Current/Resources')]:
            if not link.exists() and not link.is_symlink():
                link.symlink_to(target)
        run('codesign', '--force', '--sign', '-', framework)
    # raco may copy additional native libraries into Resources.
    for library in contents.rglob('*.dylib'):
        if not library.is_symlink():
            run('codesign', '--force', '--sign', '-', library)
    run('codesign', '--force', '--sign', '-', app)
    run('codesign', '--verify', '--deep', '--strict', app)


def main():
    os.chdir(ROOT)
    version = (ROOT / 'VERSION').read_text().strip()
    racket_version = racket_value('(display (version))')
    if racket_version != '9.2':
        raise SystemExit(f'Build requires Racket 9.2, found {racket_version}')
    system = {'Darwin': 'macos', 'Windows': 'windows', 'Linux': 'linux'}[platform.system()]
    machine = racket_value('(display (system-type \'arch))')
    arch = {'aarch64': 'arm64', 'x86_64': 'x64'}.get(machine)
    if arch is None or (system != 'macos' and arch != 'x64'):
        raise SystemExit(f'Unsupported build target: {system}/{machine}')
    name = f'V2-Lens-{version}-{system}-{arch}'
    output = ROOT / 'target' / 'packages'
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='native-build-', dir=ROOT / 'target') as temporary:
        work = Path(temporary)
        executable = work / ('V2 Lens.app' if system == 'macos' else
                             'V2-Lens.exe' if system == 'windows' else 'v2-lens')
        options = ['--icns', ROOT / 'private/launch-v2-lens.icns'] if system == 'macos' else []
        run('raco', 'exe', '--gui', '--cs', *options, '-o', executable,
            ROOT / 'private/launch-v2-lens.rkt')
        binary = executable / 'Contents/MacOS/V2 Lens' if system == 'macos' else executable
        # Homebrew's Racket stub is read-only; distribute needs to rewrite it.
        binary.chmod(binary.stat().st_mode | 0o200)
        distribution = work / name
        run('raco', 'distribute', distribution, executable)
        if system == 'macos':
            prepare_mac(distribution / executable.name, version)
        shutil.copy2(ROOT / 'LICENSE', distribution / 'LICENSE.txt')
        shutil.copy2(ROOT / 'docs/testing-native-builds.md', distribution / 'START-HERE.md')
        notices = distribution / 'runtime-licenses'
        notices.mkdir()
        share = Path(racket_value('(require setup/dirs) (display (find-share-dir))'))
        for license_file in share.glob('LICENSE*'):
            if license_file.is_file():
                shutil.copy2(license_file, notices / license_file.name)
        if not list(notices.iterdir()):
            raise RuntimeError(f'Racket license notices missing from {share}')
        # Preserve notices for installed Racket packages, including native GUI libraries.
        pkgs = Path(racket_value('(require setup/dirs) (display (find-pkgs-dir))'))
        for license_file in pkgs.glob('*/LICENSE*'):
            if license_file.is_file():
                dest = notices / license_file.parent.name
                dest.mkdir(exist_ok=True)
                shutil.copy2(license_file, dest / license_file.name)
        commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
        changes = subprocess.check_output(['git', 'status', '--porcelain'], text=True).strip()
        if changes:
            raise RuntimeError(f'Package requires a clean checkout:\n{changes}')
        dirty = False
        (distribution / 'build-info.json').write_text(json.dumps({
            'version': version, 'commit': commit, 'dirty': dirty,
            'platform': system, 'architecture': arch, 'racket': racket_version,
            'signing': 'ad-hoc' if system == 'macos' else 'unsigned'}, indent=2) + '\n')
        archive = output / (name + ('.tar.gz' if system == 'linux' else '.zip'))
        if system == 'macos':
            run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', distribution, archive)
        elif system == 'windows':
            with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as bundle:
                for path in sorted(distribution.rglob('*')):
                    if path.is_file():
                        bundle.write(path, path.relative_to(work))
        else:
            run('tar', '-czf', archive, '-C', work, name)
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        archive.with_name(archive.name + '.sha256').write_text(f'{digest}  {archive.name}\n')
        print(f'Packaged: {archive}')


if __name__ == '__main__':
    main()
