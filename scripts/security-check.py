#!/usr/bin/env python3
"""Fail-closed local/CI security gate. Standard library only; no cloud scan uploads."""
import argparse
from datetime import datetime, timezone
import fcntl
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import re
import shutil
import ssl
import subprocess
import sys
import tarfile
import tempfile
import urllib.request


ROOT = Path(__file__).resolve().parents[1]
STATE = ROOT / '.local/security'
TOOLS = STATE / 'tools'
SEVERITIES = 'UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL'


def run(args, *, cwd=ROOT, capture=False, accepted=(0,)):
    environment = {key: value for key, value in os.environ.items()
                   if not key.startswith(('TRIVY_', 'GITLEAKS_', 'SEMGREP_'))}
    result = subprocess.run([str(x) for x in args], cwd=cwd, text=True,
                            env=environment,
                            stdout=subprocess.PIPE if capture else None,
                            stderr=subprocess.PIPE if capture else None)
    if result.returncode not in accepted:
        # Scanner output can contain source/secrets. Keep captured output private.
        if capture:
            STATE.mkdir(parents=True, exist_ok=True)
            (STATE / 'last-tool-error.log').write_text((result.stdout or '') + (result.stderr or ''))
        raise RuntimeError(f'{Path(str(args[0])).name} failed (exit {result.returncode})')
    return result


def read_json(path):
    with path.open() as stream:
        return json.load(stream)


def provision():
    spec = read_json(ROOT / 'security/toolchain.json')
    machine = platform.machine()
    key = platform.system() + '-' + ('arm64' if machine in ('aarch64', 'arm64') else machine)
    TOOLS.mkdir(parents=True, exist_ok=True)
    for name in ('trivy', 'gitleaks', 'actionlint'):
        entry = spec[name]
        if key not in entry['assets']:
            raise RuntimeError(f'Unsupported scanner platform: {key}')
        asset, checksum = entry['assets'][key]
        archive = TOOLS / asset
        if not archive.exists() or hashlib.sha256(archive.read_bytes()).hexdigest() != checksum:
            print(f'Downloading {name} {entry["version"]} (SHA-256 verified)', flush=True)
            url = f'https://github.com/{entry["repository"]}/releases/download/v{entry["version"]}/{asset}'
            context = ssl.create_default_context()
            if platform.system() == 'Darwin':
                # Portable Python runtimes may not ship the host CA path. Keep TLS verification
                # enabled and augment it with the trusted macOS system roots.
                roots = subprocess.check_output(['/usr/bin/security', 'find-certificate', '-a', '-p',
                    '/System/Library/Keychains/SystemRootCertificates.keychain'])
                context.load_verify_locations(cadata=roots.decode('ascii'))
            with urllib.request.urlopen(url, timeout=120, context=context) as response:
                data = response.read()
            if hashlib.sha256(data).hexdigest() != checksum:
                raise RuntimeError(f'{name} archive checksum mismatch')
            archive.write_bytes(data)
        with tarfile.open(archive, 'r:gz') as stream:
            member = stream.getmember(name)
            if not member.isfile():
                raise RuntimeError('Scanner archive does not contain a regular executable')
            with stream.extractfile(member) as binary:
                data = binary.read()
        target = TOOLS / name
        if not target.exists() or target.read_bytes() != data:
            target.write_bytes(data)
            target.chmod(0o700)
    return spec


def export_source(destination, revision=None, staged=False):
    if revision or staged:
        args = ['git', 'archive', revision or run(['git', 'write-tree'], capture=True).stdout.strip()]
        result = subprocess.run(args, cwd=ROOT, stdout=subprocess.PIPE, check=True)
        with tarfile.open(fileobj=io.BytesIO(result.stdout), mode='r:') as archive:
            archive.extractall(destination, filter='data')
    else:
        paths = subprocess.check_output(['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'], cwd=ROOT)
        for raw in set(paths.split(b'\0')) - {b''}:
            path = Path(os.fsdecode(raw))
            source = ROOT / path
            if source.is_symlink():
                raise RuntimeError(f'Source symlink requires review: {path}')
            if source.is_file():
                target = destination / path
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, target)


def secret_scan(source, report, *, revision=None):
    args = [TOOLS / 'gitleaks', 'git' if revision else 'dir', '--no-banner', '--redact=100',
            '--ignore-gitleaks-allow', '--gitleaks-ignore-path', source / 'security/no-ignore-file',
            '--config', source / 'security/gitleaks.toml', '--report-format', 'json', '--report-path', report]
    if revision:
        args += ['--log-opts', revision, ROOT]
    else:
        args += [source]
    run(args, capture=True, accepted=(0, 1))
    findings = read_json(report)
    for item in findings:
        prefix = str(source) + '/'
        if item['File'].startswith(prefix):
            item['File'] = item['File'][len(prefix):]
        print(f'  SECRET {item["RuleID"]} {item["File"]}:{item["StartLine"]}')
    report.write_text(json.dumps(findings, indent=2) + '\n')
    return len(findings)


def trivy_scan(source, report, *, image=False):
    args = [TOOLS / 'trivy', 'image' if image else 'fs', '--scanners',
            'vuln,secret' if image else 'vuln,misconfig,secret', '--severity', SEVERITIES,
            '--ignore-unfixed=false', '--config', ROOT / 'security/trivy.yaml',
            '--ignorefile', ROOT / 'security/empty.ignore', '--no-progress', '--list-all-pkgs',
            '--timeout', '15m', '--format', 'json', '--output', report]
    if not image:
        args += ['--include-dev-deps']
    args += [source]
    run(args)
    data = read_json(report)
    for result in data.get('Results', []):
        for secret in result.get('Secrets', []):
            secret['Match'] = '[REDACTED]'
            secret.pop('Code', None)
    report.write_text(json.dumps(data, indent=2) + '\n')
    if image and not any(result.get('Packages') for result in data.get('Results', [])):
        raise RuntimeError('Trivy detected no packages in the container image')
    if not image:
        for dependency_file in read_json(Path(source) / 'security/project.json')['dependency_files']:
            if not any(result.get('Packages') and result.get('Target') == dependency_file
                       for result in data.get('Results', [])):
                raise RuntimeError(f'Trivy did not analyze dependencies from {dependency_file}')
    count = 0
    for result in data.get('Results', []):
        target = result['Target']
        for item in result.get('Vulnerabilities', []):
            count += 1
            print(f'  {item["Severity"]} {item["VulnerabilityID"]} {item["PkgName"]} '
                  f'{item["InstalledVersion"]} -> {item.get("FixedVersion") or "no fix published"}')
        for item in result.get('Misconfigurations', []) + result.get('Secrets', []):
            count += 1
            print(f'  {item["Severity"]} {item.get("ID", item.get("RuleID", "SECRET"))} {target}')
    return count


def sast(source, report, spec):
    if not shutil.which('docker'):
        raise RuntimeError('Docker is required for the pinned local Semgrep scanner')
    run(['docker', 'run', '--rm', '--network=none', '--cap-drop=ALL',
         '--security-opt=no-new-privileges', '--read-only', '--tmpfs', '/tmp:rw,nosuid,size=1g',
         '--user', f'{os.getuid()}:{os.getgid()}', '-e', 'HOME=/tmp', '-e', 'SEMGREP_SEND_METRICS=off',
         '-v', f'{source}:/src:ro', '-v', f'{report.parent}:/reports:rw', '-w', '/src',
         spec['semgrep_image'], 'semgrep', 'scan', '--oss-only', '--metrics=off', '--disable-nosem',
         '--strict', '--error', '--disable-version-check', '--no-git-ignore', '--max-target-bytes=0',
         '--timeout=30', '--timeout-threshold=1',
         '--config', '/src/security/semgrep-rules', '--json', '--output', f'/reports/{report.name}', '/src'],
        capture=True, accepted=(0, 1))
    data = read_json(report)
    for item in data.get('results', []):
        for field in ('lines', 'metavars', 'dataflow_trace'):
            item.get('extra', {}).pop(field, None)
    report.write_text(json.dumps(data, indent=2) + '\n')
    if data.get('errors'):
        raise RuntimeError(f'Semgrep reported {len(data["errors"])} scan errors; see private report')
    if not data.get('paths', {}).get('scanned') and (source / 'src').exists():
        raise RuntimeError('Semgrep scanned no source files')
    scanned = set(data.get('paths', {}).get('scanned', []))
    expected = [p for p in (source / 'src').rglob('*') if p.is_file()
                and p.suffix in ('.java', '.js', '.jsx', '.ts', '.tsx', '.mjs', '.cjs')
                and not p.name.endswith('.d.ts') and not str(p.relative_to(source)).startswith('src/test/')]
    missing = [str(p.relative_to(source)) for p in expected
               if '/src/' + str(p.relative_to(source)) not in scanned]
    if missing:
        raise RuntimeError(f'Semgrep skipped {len(missing)} production source files; first: {missing[0]}')
    for item in data['results']:
        print(f'  SAST {item["check_id"]} {item["path"]}:{item["start"]["line"]}')
    return len(data['results'])


def workflow_check(source, report):
    files = sorted((source / '.github/workflows').glob('*.y*ml'))
    if not files:
        raise RuntimeError('No GitHub workflow found for security enforcement')
    result = run([TOOLS / 'actionlint', '-shellcheck=', *files], cwd=source,
                 capture=True, accepted=(0, 1))
    report.write_text((result.stdout or '') + (result.stderr or ''))
    if result.returncode:
        raise RuntimeError('Invalid GitHub Actions workflow; see private actionlint report')
    return 0


def scan(spec, *, revision=None, source_only=False):
    report_name = revision or ('working-tree-source' if source_only else 'working-tree')
    report = STATE / 'reports' / report_name
    report.mkdir(parents=True, exist_ok=True)
    # An interrupted or early failed scan must never leave an old green summary
    # attached to partly refreshed reports.
    for name in ('summary.json', 'source.json', 'secrets.json', 'history.json', 'semgrep.json', 'actionlint.txt'):
        (report / name).unlink(missing_ok=True)
    for path in report.glob('image-*.json'):
        path.unlink()
    (report / 'summary.json').write_text(json.dumps({'findings': 0,
        'scan_errors': ['Scan did not complete; repair the reported failure and rerun the gate.'],
        'scanned_at_utc': datetime.now(timezone.utc).isoformat(), 'revision': revision or 'working-tree',
        'scope': 'source-only' if source_only else 'source-and-images',
        'image_scans_requested': 0, 'image_scans_completed': 0, 'image_reports': [], 'passed': False}, indent=2) + '\n')
    with tempfile.TemporaryDirectory(prefix='boxeu-security-') as temporary:
        source = Path(temporary) / 'source'
        source.mkdir()
        export_source(source, revision)
        project = read_json(source / 'security/project.json')
        for name in project['dependency_files']:
            if not (source / name).is_file():
                raise RuntimeError(f'Missing dependency lockfile: {name}')
        # No scanner-specific silent bypasses. Policy changes must remain reviewable.
        for name in ('.trivyignore', '.trivyignore.yaml', '.gitleaksignore', '.semgrepignore'):
            if (source / name).exists():
                raise RuntimeError(f'Unreviewed scanner exclusion file: {name}')
        for path in source.rglob('*'):
            if path.is_file() and path.suffix in ('.java', '.ts', '.tsx', '.js', '.jsx', '.yml', '.yaml', '.sh'):
                if re.search(r'trivy\s*:\s*ignore', path.read_text(errors='replace'), re.IGNORECASE):
                    raise RuntimeError(f'Inline Trivy exclusion requires review: {path.relative_to(source)}')
        failures = []
        total = 0
        checks = [
            ('secrets in files', lambda: secret_scan(source, report / 'secrets.json')),
            ('secrets in Git history', lambda: secret_scan(source, report / 'history.json', revision=revision or '--all')),
            ('dependencies and configuration', lambda: trivy_scan(source, report / 'source.json')),
            ('source code', lambda: sast(source, report / 'semgrep.json', spec)),
            ('GitHub workflows', lambda: workflow_check(source, report / 'actionlint.txt'))
        ]
        for title, check in checks:
            print(f'Checking {title}...', flush=True)
            try:
                total += check()
            except (RuntimeError, OSError, ValueError) as error:
                failures.append(f'{title}: {error}')
        images_completed = 0
        image_reports = []
        if not source_only:
            for index, image in enumerate(project['images']):
                tag = f'boxeu-security/{ROOT.name}:{os.getpid()}-{index}'
                try:
                    print(f'Building and scanning {image["name"]} image...', flush=True)
                    args = ['docker', 'build', '--pull', '--platform=linux/amd64', '--tag', tag,
                            '--file', source / image['dockerfile']]
                    for key, value in image.get('build_args', {}).items():
                        args += ['--build-arg', f'{key}={value}']
                    args += [source / image['context']]
                    run(args)
                    total += trivy_scan(tag, report / f'image-{index}.json', image=True)
                    images_completed += 1
                    image_reports.append(f'image-{index}.json')
                    run([TOOLS / 'trivy', 'image', '--format', 'cyclonedx', '--output',
                         report / f'image-{index}.cdx.json', tag])
                except (RuntimeError, OSError, ValueError) as error:
                    failures.append(f'{image["name"]} image: {error}')
                finally:
                    run(['docker', 'image', 'rm', tag], capture=True, accepted=(0, 1))
        print(f'Private security reports: {report}')
        (report / 'summary.json').write_text(json.dumps({'findings': total, 'scan_errors': failures,
            'scanned_at_utc': datetime.now(timezone.utc).isoformat(), 'revision': revision or 'working-tree',
            'scope': 'source-only' if source_only else 'source-and-images',
            'image_scans_requested': 0 if source_only else len(project['images']),
            'image_scans_completed': images_completed, 'image_reports': image_reports,
            'passed': not total and not failures}, indent=2) + '\n')
        for failure in failures:
            print(f'  SCAN ERROR: {failure}', file=sys.stderr)
        if total or failures:
            raise RuntimeError(f'Security gate BLOCKED: {total} findings, {len(failures)} scan errors')
        print('Security gate PASSED')


def install_hooks():
    current = run(['git', 'config', '--get', 'core.hooksPath'], capture=True, accepted=(0, 1)).stdout.strip()
    if current and current != '.githooks':
        raise RuntimeError(f'Existing hooksPath {current!r}; integrate hooks manually without replacing it')
    default = Path(run(['git', 'rev-parse', '--git-path', 'hooks'], capture=True).stdout.strip())
    if not current and any((default / name).exists() for name in ('pre-commit', 'pre-push')):
        raise RuntimeError('Existing Git hooks; integrate manually without replacing them')
    for path in (ROOT / '.githooks').iterdir():
        path.chmod(0o755)
    run(['git', 'config', '--local', 'core.hooksPath', '.githooks'])
    print('Local pre-commit and pre-push hooks installed')


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['setup', 'scan', 'staged', 'pre-push', 'image'])
    parser.add_argument('--source-only', action='store_true')
    parser.add_argument('--install-hooks', action='store_true')
    parser.add_argument('--target')
    args = parser.parse_args()
    STATE.mkdir(parents=True, exist_ok=True)
    STATE.chmod(0o700)
    # Keep reports and shared per-repository scanner files consistent across IDE/hooks/CI calls.
    lock = (STATE / 'gate.lock').open('a')
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print('Waiting for the running security check in this repository...', flush=True)
        fcntl.flock(lock, fcntl.LOCK_EX)
    spec = provision()
    if args.command == 'setup':
        run(['docker', 'pull', spec['semgrep_image']])
        if args.install_hooks:
            install_hooks()
    elif args.command == 'staged':
        with tempfile.TemporaryDirectory(prefix='boxeu-security-index-') as directory:
            source = Path(directory)
            export_source(source, staged=True)
            report = STATE / 'staged-secrets.json'
            if secret_scan(source, report):
                raise RuntimeError('Commit blocked: staged secrets detected')
    elif args.command == 'image':
        if not args.target:
            raise RuntimeError('image requires --target')
        report = STATE / 'reports/image'
        report.mkdir(parents=True, exist_ok=True)
        if trivy_scan(args.target, report / 'trivy.json', image=True):
            raise RuntimeError('Image blocked: security findings detected')
        run([TOOLS / 'trivy', 'image', '--format', 'cyclonedx', '--output', report / 'sbom.cdx.json', args.target])
    elif args.command == 'pre-push':
        revisions = []
        for line in sys.stdin:
            _, revision, _, _ = line.split()
            if set(revision) == {'0'}:
                continue
            commit = run(['git', 'rev-parse', '--verify', f'{revision}^{{commit}}'], capture=True).stdout.strip()
            if commit not in revisions:
                revisions.append(commit)
        for revision in revisions:
            scan(spec, revision=revision)
    else:
        scan(spec, source_only=args.source_only)


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError, ValueError, subprocess.CalledProcessError) as failure:
        print(f'SECURITY BLOCKED: {failure}', file=sys.stderr)
        sys.exit(1)
