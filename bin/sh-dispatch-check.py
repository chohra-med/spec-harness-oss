#!/usr/bin/env python3
"""Validate a dispatch and its declared source identity; never run an agent."""
import argparse
import hashlib
import importlib.util
import json
import os
import pathlib
import re
import stat
import subprocess
import sys

# Execute only the exact shipped reader bytes. The installer preserves custom siblings as conflicts.
_SAFE_READER_SHA256 = '4e5428632fdba326f31f779f3a5629a48c3a60408b2e0b7dd062450f02ec19fa'

def _load_safe_reader():
    if not hasattr(os, 'O_NOFOLLOW'):
        raise ValueError('no no-follow support')
    path = pathlib.Path(__file__).parent / 'sh_safe_io.py'
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | getattr(os, 'O_NONBLOCK', 0))
    try:
        before = os.fstat(fd)
        if not stat.S_ISREG(before.st_mode) or before.st_size > 8 * 1024 * 1024:
            raise ValueError('unsafe reader')
        chunks = []
        remaining = before.st_size
        while remaining:
            chunk = os.read(fd, min(remaining, 65536))
            if not chunk:
                raise ValueError('short reader')
            chunks.append(chunk); remaining -= len(chunk)
        data = b''.join(chunks)
        after = os.fstat(fd)
        identity = lambda item: (item.st_dev, item.st_ino, item.st_size, item.st_mtime_ns)
        if identity(before) != identity(after) or hashlib.sha256(data).hexdigest() != _SAFE_READER_SHA256:
            raise ValueError('reader mismatch')
    finally:
        os.close(fd)
    spec = importlib.util.spec_from_file_location('dispatch_safe_io', path)
    if spec is None:
        raise ValueError('reader loader unavailable')
    module = importlib.util.module_from_spec(spec)
    exec(compile(data, str(path), 'exec'), module.__dict__)
    return module

try:
    _safe = _load_safe_reader()
except (OSError, ValueError, SyntaxError):
    if __name__ == '__main__':
        print('PENDING: missing, unsafe or modified safe-reader sibling')
        raise SystemExit(2)
    raise ImportError('missing, unsafe or modified safe-reader sibling') from None
read_bounded = _safe.read_bounded
SafeReadError = _safe.SafeReadError
safe_relative = _safe.safe_relative
MAX_RECEIPT_BYTES = _safe.MAX_RECEIPT_BYTES
MAX_FILE_BYTES = _safe.MAX_FILE_BYTES
HEX = re.compile(r'^[0-9a-f]{64}$')
ROLES = {'sdd-tester', 'sdd-verifier', 'sdd-reviewer', 'sdd-plan-goldfish'}
PACKET_REQUIRED = {'input.md', 'spec.md', 'goal.md', 'plan.md', 'tasks.md'}

class Refused(Exception):
    pass

class Pending(Exception):
    pass

def digest(data):
    return hashlib.sha256(data).hexdigest()

def unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise Refused('duplicate JSON key')
        result[key] = value
    return result

def decode_json(value):
    try:
        return json.loads(value, object_pairs_hook=unique)
    except (ValueError, UnicodeError, RecursionError):
        raise Refused('invalid JSON') from None

def keys(value, wanted, name):
    if not isinstance(value, dict) or set(value) != wanted:
        raise Refused('invalid ' + name + ' fields')

def hash_value(value):
    return isinstance(value, str) and HEX.fullmatch(value) is not None

def path_text(value):
    return isinstance(value, str) and bool(value) and not any(c in value for c in '\r\n\x00') and '<' not in value and '>' not in value

def absolute(value, base=None, existing=True):
    if not path_text(value):
        raise Refused('invalid path')
    p = pathlib.Path(value)
    if not p.is_absolute():
        if base is None or not safe_relative(value):
            raise Refused('unsafe relative path')
        p = pathlib.Path(base) / value
    text = str(p)
    if os.path.normpath(text) != text or value.endswith('/'):
        raise Refused('noncanonical path')
    current = pathlib.Path('/')
    for component in p.parts[1:]:
        current = current / component
        try:
            info = current.lstat()
        except FileNotFoundError:
            if existing:
                raise Pending('missing path: ' + str(current)) from None
            break
        except NotADirectoryError:
            raise Refused('non-directory path component') from None
        except OSError:
            raise Pending('unreadable path: ' + str(current)) from None
        if stat.S_ISLNK(info.st_mode):
            raise Refused('linked path')
    return p

def read_file(root, relative, limit=MAX_FILE_BYTES):
    try:
        return read_bounded(relative, limit, root=str(root))
    except SafeReadError as error:
        if error.reason == 'missing' or error.reason.startswith('unreadable'):
            raise Pending('missing or unreadable input: ' + relative) from None
        raise Refused('unsafe or changed input: ' + relative) from None

def read_absolute(path, limit=MAX_RECEIPT_BYTES):
    p = absolute(path)
    return read_file('/', str(p)[1:], limit)

def parse_payload(data):
    try:
        text = data.decode('utf-8')
    except UnicodeError:
        raise Refused('DISPATCH-CONTAMINATED: invalid UTF-8') from None
    if not text.endswith('\n') or '\r' in text or '\x00' in text:
        raise Refused('DISPATCH-CONTAMINATED: invalid line framing')
    lines = text[:-1].split('\n')
    parts = []
    for line in lines:
        if ': ' not in line:
            raise Refused('DISPATCH-CONTAMINATED: invalid field')
        key, value = line.split(': ', 1)
        parts.append((key, value))
    if len(parts) != len(dict(parts)):
        raise Refused('DISPATCH-CONTAMINATED: duplicate field')
    fields = dict(parts)
    role = fields.get('role')
    if role not in ROLES:
        raise Refused('DISPATCH-CONTAMINATED: invalid role')
    names = ['role'] + (['pass'] if role == 'sdd-reviewer' else []) + ['feature', 'source revision', 'source pin', 'goal sha256', 'allowed files', 'return']
    if 'concerns source' in fields or 'concerns' in fields:
        if role != 'sdd-tester' and not (role == 'sdd-reviewer' and fields.get('pass') == '2'):
            raise Refused('DISPATCH-CONTAMINATED: concerns not allowed')
        if 'concerns source' in fields:
            names.append('concerns source')
        if 'concerns' in fields:
            names.append('concerns')
    if [key for key, _ in parts] != names or (role == 'sdd-reviewer' and fields.get('pass') not in ('1', '2')):
        raise Refused('DISPATCH-CONTAMINATED: invalid field order or pass')
    for name in names:
        if name not in ('role', 'pass'):
            fields[name] = decode_json(fields[name])
    for name in ('feature', 'source revision', 'goal sha256', 'return'):
        if not path_text(fields[name]):
            raise Refused('DISPATCH-CONTAMINATED: invalid scalar')
    if fields['return'] != 'role Output' or not hash_value(fields['goal sha256']):
        raise Refused('DISPATCH-CONTAMINATED: invalid return or goal hash')
    concern = fields.get('concerns')
    if concern is not None and (not isinstance(concern, str) or not concern or '\r' in concern or '\x00' in concern):
        raise Refused('DISPATCH-CONTAMINATED: invalid concern')
    if 'concerns source' in fields and (concern is None or concern == 'no status given'):
        raise Refused('DISPATCH-CONTAMINATED: unexpected concerns source')
    if concern is not None and concern != 'no status given' and 'concerns source' not in fields:
        raise Refused('DISPATCH-CONTAMINATED: unbound concern')
    pin = fields['source pin']
    keys(pin, {'path', 'sha256', 'identity'}, 'source pin reference')
    if not path_text(pin['path']) or not hash_value(pin['sha256']) or not hash_value(pin['identity']):
        raise Refused('invalid source pin reference')
    allowed = fields['allowed files']
    if not isinstance(allowed, list) or not allowed or not all(path_text(p) for p in allowed):
        raise Refused('invalid allowed files')
    return fields

def safe_registry_path(name):
    return safe_relative(name) and not any(c in name for c in '\r\n')

def registry(root, files):
    if not isinstance(files, dict) or not files:
        raise Refused('invalid file registry')
    for name, expected in files.items():
        if not safe_registry_path(name) or not isinstance(expected, dict):
            raise Refused('unsafe registry path')
        kind = expected.get('kind')
        wanted = {'kind'} if kind == 'absent' else {'kind', 'mode', 'sha256' if kind == 'file' else 'target'}
        keys(expected, wanted, 'registry entry')
        if kind not in ('file', 'symlink', 'absent'):
            raise Refused('unsupported registry entry')
        if kind != 'absent' and (type(expected['mode']) is not int or not 0 <= expected['mode'] <= 0o7777):
            raise Refused('invalid file mode')
        if kind == 'file' and not hash_value(expected['sha256']):
            raise Refused('invalid file hash')
        if kind == 'symlink' and (not isinstance(expected['target'], str) or '\x00' in expected['target']):
            raise Refused('invalid link target')
        parent = pathlib.Path(root)
        for component in pathlib.PurePosixPath(name).parts[:-1]:
            parent /= component
            try:
                info = parent.lstat()
            except FileNotFoundError:
                raise Pending('missing source parent') from None
            if not stat.S_ISDIR(info.st_mode):
                raise Refused('unsafe source parent')
        p = pathlib.Path(root) / name
        try:
            info = p.lstat()
        except FileNotFoundError:
            if kind == 'absent':
                continue
            raise Pending('missing source input: ' + name) from None
        if kind == 'absent':
            raise Refused('changed source state: ' + name)
        if stat.S_IMODE(info.st_mode) != expected['mode']:
            raise Refused('changed source mode: ' + name)
        if kind == 'file':
            if not stat.S_ISREG(info.st_mode):
                raise Refused('unsafe source file')
            if digest(read_file(root, name)) != expected['sha256']:
                raise Refused('changed source hash: ' + name)
        elif not stat.S_ISLNK(info.st_mode) or os.readlink(p) != expected['target']:
            raise Refused('changed symlink: ' + name)

def git(root, *args):
    env = dict(os.environ)
    env.update({'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': '/dev/null', 'GIT_OPTIONAL_LOCKS': '0', 'GIT_PAGER': 'cat', 'LC_ALL': 'C'})
    for name in ('GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_EXTERNAL_DIFF', 'GIT_CONFIG_COUNT'):
        env.pop(name, None)
    try:
        result = subprocess.run(['git', '-c', 'core.fsmonitor=false', '-c', 'core.pager=cat', *args], cwd=root, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    except OSError:
        raise Pending('Git unavailable') from None
    if result.returncode:
        raise Pending('Git identity unavailable')
    return result.stdout

def git_state(root, pin):
    head = git(root, 'rev-parse', 'HEAD').decode().strip()
    branch = git(root, 'branch', '--show-current').decode().strip()
    status = git(root, 'status', '--porcelain=v1', '--untracked-files=all').decode()
    diff = git(root, 'diff', '--no-ext-diff', '--no-textconv', '--binary', 'HEAD')
    cached = git(root, 'diff', '--no-ext-diff', '--no-textconv', '--binary', '--cached')
    gitdir = pathlib.Path(git(root, 'rev-parse', '--absolute-git-dir').decode().strip())
    absolute(str(gitdir))
    try:
        idx = read_file(gitdir, 'index')
        idx_hash = digest(idx)
    except Pending:
        if (gitdir / 'index').exists():
            raise
        idx_hash = None
    names = {os.fsdecode(x) for x in git(root, 'ls-files', '--cached', '--others', '--exclude-standard', '-z').split(b'\0') if x}
    if (head != pin['head'] or branch != pin['branch'] or status != pin['status'] or digest(diff) != pin['diff_head_sha256'] or digest(cached) != pin['cached_diff_sha256'] or idx_hash != pin['index_sha256'] or names != set(pin['files'])):
        raise Refused('changed Git source identity')

def non_git(root, feature, pin, goal, pinpath, dispatchpath):
    dependencies = pin['dependencies']
    keys(dependencies, {'path', 'sha256'}, 'dependency reference')
    if not hash_value(dependencies['sha256']):
        raise Refused('invalid manifest hash')
    manifest_path = absolute(dependencies['path'])
    if manifest_path != feature / 'dependencies.json':
        raise Refused('invalid manifest location')
    manifest_data = read_absolute(str(manifest_path))
    if digest(manifest_data) != dependencies['sha256']:
        raise Refused('changed manifest hash')
    manifest = decode_json(manifest_data)
    keys(manifest, {'schema', 'source_files', 'packet_dependencies'}, 'dependency manifest')
    if type(manifest['schema']) is not int or manifest['schema'] != 1:
        raise Refused('invalid manifest schema')
    names = manifest['source_files']
    if not isinstance(names, list) or not names or not all(safe_registry_path(n) for n in names) or names != sorted(set(names)) or names != sorted(pin['files']):
        raise Refused('source declarations mismatch')
    deps = manifest['packet_dependencies']
    if not isinstance(deps, dict) or not PACKET_REQUIRED <= set(deps):
        raise Refused('missing packet declarations')
    for name, expected in deps.items():
        if not safe_registry_path(name) or not hash_value(expected):
            raise Refused('unsafe packet declaration')
        p = feature / name
        if p in (manifest_path, pinpath, dispatchpath) or name == 'dispatch.txt' or name.startswith('gates/') or 'feedback' in name or 'history' in name:
            raise Refused('dependency cycle or output')
        if digest(read_file(feature, name)) != expected:
            raise Refused('changed packet input hash: ' + name)
    if deps['goal.md'] != goal:
        raise Refused('goal hash mismatch')
    return manifest_data

def concern_evidence(fields, root):
    reference = fields['concerns source']
    keys(reference, {'path', 'sha256', 'identity'}, 'concerns source')
    if not path_text(reference['path']) or not hash_value(reference['sha256']) or not hash_value(reference['identity']):
        raise Refused('invalid concerns source')
    envelope_path = absolute(reference['path'])
    if not pathlib.Path(reference['path']).is_absolute() or envelope_path == root or root in envelope_path.parents:
        raise Refused('concerns source outside-root requirement')
    envelope_data = read_absolute(str(envelope_path))
    if digest(envelope_data) != reference['sha256']:
        raise Refused('changed concerns envelope hash')
    envelope = decode_json(envelope_data)
    keys(envelope, {'schema','source_identity','goal_sha256','context_id','request_sha256','raw_return','concerns_range','identity'}, 'concerns envelope')
    if type(envelope['schema']) is not int or envelope['schema'] != 1:
        raise Refused('invalid concerns schema')
    if envelope['source_identity'] != fields['source pin']['identity'] or envelope['goal_sha256'] != fields['goal sha256']:
        raise Refused('concerns source identity or goal mismatch')
    if not path_text(envelope['context_id']) or not envelope['context_id'].strip() or not hash_value(envelope['request_sha256']) or not hash_value(envelope['identity']):
        raise Refused('invalid concerns context or identity')
    body = dict(envelope); del body['identity']
    if digest(json.dumps(body,sort_keys=True,separators=(',',':')).encode()) != envelope['identity'] or reference['identity'] != envelope['identity']:
        raise Refused('concerns envelope identity mismatch')
    raw_ref = envelope['raw_return']
    keys(raw_ref, {'path','sha256'}, 'raw return')
    if not safe_registry_path(raw_ref['path']) or not hash_value(raw_ref['sha256']):
        raise Refused('unsafe raw return reference')
    raw_path = envelope_path.parent / raw_ref['path']
    if raw_path == envelope_path or raw_path == root or root in raw_path.parents:
        raise Refused('raw return self-reference or inside source')
    raw_data = read_file(envelope_path.parent, raw_ref['path'], MAX_RECEIPT_BYTES)
    if digest(raw_data) != raw_ref['sha256']:
        raise Refused('changed raw return hash')
    if b'\r' in raw_data or b'\x00' in raw_data:
        raise Refused('invalid raw return framing')
    try:
        raw_data.decode('utf-8')
    except UnicodeDecodeError:
        raise Refused('invalid raw return UTF-8') from None
    lines = raw_data[:-1].split(b'\n') if raw_data.endswith(b'\n') else raw_data.split(b'\n')
    if not lines or lines[-1] != b'STATUS: DONE_WITH_CONCERNS' or any(line in (b'STATUS: DONE', b'STATUS: DONE_WITH_CONCERNS', b'STATUS: BLOCKED', b'STATUS: NEEDS_CONTEXT') for line in lines[:-1]):
        raise Refused('invalid or ambiguous implementer status')
    final_start = len(raw_data) - len(lines[-1]) - (1 if raw_data.endswith(b'\n') else 0)
    span = envelope['concerns_range']
    keys(span, {'start','end'}, 'concerns range')
    start, end = span['start'], span['end']
    if type(start) is not int or type(end) is not int or not (0 <= start < end < final_start) or (start and raw_data[start-1:start] != b'\n') or raw_data[end:end+1] != b'\n':
        raise Refused('invalid concerns range')
    try:
        selected = raw_data[start:end].decode('utf-8')
    except UnicodeDecodeError:
        raise Refused('invalid concerns UTF-8 boundary') from None
    if selected != fields['concerns']:
        raise Refused('concerns bytes mismatch')
    return envelope_path, envelope_data, raw_ref['path'], raw_data


def validate_role_scope(path, root, feature, pinpath, manifest_path, role, review_pass):
    """Enforce declared blind-role scope without claiming a worker sandbox."""
    if role != 'sdd-plan-goldfish' and not (role == 'sdd-reviewer' and review_pass == '1'):
        return
    if path == pinpath or (manifest_path is not None and path == manifest_path):
        return
    if path == feature or feature in path.parents:
        permitted = {feature / name for name in ('input.md','spec.md','goal.md','plan.md','tasks.md','design.md','research.md')}
        if role == 'sdd-reviewer':
            permitted.add(feature / 'gates/source-recheck.md')
        if path not in permitted or not path.is_file():
            raise Refused('DISPATCH-CONTAMINATED: forbidden feature scope')
        return
    protected = (root / 'specs', root / '.spec-harness', root / '.memory/80-feedback.md')
    is_scope = not path.is_file()
    for forbidden in protected:
        if path == forbidden or forbidden in path.parents or (is_scope and path in forbidden.parents):
            raise Refused('DISPATCH-CONTAMINATED: forbidden source scope')

def validate(dispatchpath):
    payload_data = read_absolute(dispatchpath, MAX_RECEIPT_BYTES)
    fields = parse_payload(payload_data)
    pref = fields['source pin']
    pinpath = absolute(pref['path'])
    pin_data = read_absolute(str(pinpath))
    if digest(pin_data) != pref['sha256']:
        raise Refused('changed pin hash')
    pin = decode_json(pin_data)
    if not isinstance(pin, dict):
        raise Refused('invalid pin')
    if 'head' in pin:
        kind = 'git'; keys(pin, {'root','head','branch','status','diff_head_sha256','cached_diff_sha256','index_sha256','files','identity'}, 'Git pin')
        if not all(isinstance(pin[x],str) for x in ('head','branch','status')) or not all(hash_value(pin[x]) for x in ('diff_head_sha256','cached_diff_sha256')) or not (pin['index_sha256'] is None or hash_value(pin['index_sha256'])):
            raise Refused('invalid Git pin fields')
        if fields['source revision'] != pin['head']:
            raise Refused('source revision mismatch')
    else:
        kind = 'non-Git'; keys(pin, {'root','marker','files','dependencies','identity'}, 'non-Git pin')
        if pin['marker'] != 'non-Git' or fields['source revision'] != 'non-Git':
            raise Refused('invalid non-Git marker')
    if not hash_value(pin['identity']) or pin['identity'] != pref['identity']:
        raise Refused('identity mismatch')
    body = dict(pin); del body['identity']
    if digest(json.dumps(body, sort_keys=True, separators=(',', ':')).encode()) != pin['identity']:
        raise Refused('invalid pin identity')
    if not isinstance(pin['files'], dict) or not pin['files']:
        raise Refused('invalid file registry')
    root = absolute(pin['root']); feature = absolute(fields['feature'], root)
    if not root.is_dir() or not feature.is_dir():
        raise Refused('source or feature is not a directory')
    if pinpath == root or root in pinpath.parents:
        raise Refused('pin is inside source root')
    manifest_path = None
    if kind == 'non-Git' and isinstance(pin.get('dependencies'), dict):
        manifest_name = pin['dependencies'].get('path')
        if isinstance(manifest_name, str) and os.path.isabs(manifest_name):
            manifest_path = pathlib.Path(manifest_name)
    for value in fields['allowed files']:
        path = absolute(value, root, existing=False)
        if path == root or not (root in path.parents or path == feature or feature in path.parents or path == pinpath):
            raise Refused('unsafe allowed file scope')
        validate_role_scope(path, root, feature, pinpath, manifest_path, fields['role'], fields.get('pass'))
    provenance = concern_evidence(fields, root) if 'concerns source' in fields else None
    if kind == 'git':
        git_state(root, pin)
        if digest(read_file(feature, 'goal.md')) != fields['goal sha256']:
            raise Refused('goal hash mismatch')
    else:
        manifest = non_git(root, feature, pin, fields['goal sha256'], pinpath, pathlib.Path(dispatchpath))
    registry(root, pin['files'])
    if kind == 'git':
        git_state(root, pin)
        if digest(read_file(feature, 'goal.md')) != fields['goal sha256']:
            raise Refused('changed goal hash')
    else:
        if non_git(root, feature, pin, fields['goal sha256'], pinpath, pathlib.Path(dispatchpath)) != manifest:
            raise Refused('changed manifest')
    registry(root, pin['files'])
    if read_absolute(str(pinpath)) != pin_data or read_absolute(dispatchpath) != payload_data:
        raise Refused('changed dispatch or pin')
    if provenance is not None:
        envelope_path, envelope_data, raw_name, raw_data = provenance
        if read_absolute(str(envelope_path)) != envelope_data or read_file(envelope_path.parent, raw_name, MAX_RECEIPT_BYTES) != raw_data:
            raise Refused('changed concerns evidence')

def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dispatch', required=True)
    try:
        args = parser.parse_args(argv)
    except SystemExit:
        return 2
    if not os.path.isabs(args.dispatch):
        print('PENDING: dispatch path must be absolute'); return 2
    try:
        validate(args.dispatch)
    except Refused as error:
        print('DISPATCH-CONTAMINATED or PENDING: ' + str(error)); return 1
    except (Pending, OSError, UnicodeError, RecursionError) as error:
        print('PENDING: ' + str(error)); return 2
    print('DISPATCH-VALID'); return 0

if __name__ == '__main__':
    raise SystemExit(main())
