#!/usr/bin/env python3
"""Check recorded synthetic or actual host evidence consistency; never launch a client."""
import argparse
import hashlib
import json
import pathlib
import re
import stat
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / 'bin'))
from sh_safe_io import MAX_FILE_BYTES, SafeReadError, read_bounded, safe_relative

HEX = re.compile(r'^[0-9a-f]{64}$')
RUN_KEYS = {'candidate_identity', 'goal_sha256', 'client', 'controller_identity',
            'fixture_manifest_sha256', 'root_trace_review'}
ROW_KEYS = {'control', 'candidate_identity', 'goal_sha256', 'payload_sha256', 'request',
            'context_ids', 'raw_return_path', 'raw_return_sha256', 'tool_trace_path',
            'tool_trace_sha256', 'observed_reads', 'eligibility', 'result', 'reason'}

class Inconsistent(Exception):
    pass

class Pending(Exception):
    pass

def unique_pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise Inconsistent('duplicate JSON key')
        result[key] = value
    return result

def read_artifact(root, path, expected):
    if path is None or expected is None:
        if path is not None or expected is not None:
            raise Pending('incomplete artifact reference')
        raise Pending('missing artifact reference')
    if not safe_relative(path) or not isinstance(expected, str) or not HEX.fullmatch(expected):
        raise Inconsistent('unsafe artifact path or hash')
    try:
        data = read_bounded(path, MAX_FILE_BYTES, root=str(root))
    except SafeReadError as error:
        if error.reason == 'missing':
            raise Pending('missing artifact: ' + path) from None
        raise Inconsistent('unsafe or unreadable artifact: ' + path) from None
    if hashlib.sha256(data).hexdigest() != expected:
        raise Inconsistent('artifact hash mismatch: ' + path)
    return data

def read_record(root, name):
    try:
        raw = read_bounded(name, MAX_FILE_BYTES, root=str(root))
    except SafeReadError as error:
        if error.reason == 'missing':
            raise Pending('missing receipt: ' + name) from None
        raise Inconsistent('unsafe receipt: ' + name) from None
    try:
        value = json.loads(raw.decode('utf-8'), object_pairs_hook=unique_pairs)
    except (UnicodeError, ValueError, RecursionError):
        raise Inconsistent('invalid JSON: ' + name) from None
    if not isinstance(value, dict):
        raise Inconsistent('receipt must be an object: ' + name)
    return value

def exact_keys(value, keys, label):
    if set(value) != keys:
        raise Inconsistent('invalid fields: ' + label)

def string(value):
    return isinstance(value, str) and bool(value.strip()) and '\x00' not in value

def hash_string(value):
    return isinstance(value, str) and HEX.fullmatch(value) is not None

def validate(root, candidate, goal):
    try:
        info = root.lstat()
    except FileNotFoundError:
        raise Pending('missing evidence directory') from None
    if not stat.S_ISDIR(info.st_mode):
        raise Inconsistent('evidence directory is not a directory')
    run = read_record(root, 'run.json')
    exact_keys(run, RUN_KEYS, 'run.json')
    if run['candidate_identity'] != candidate or run['goal_sha256'] != goal:
        raise Inconsistent('run identity mismatch')
    if not all(string(run[k]) for k in ('client', 'controller_identity')) or not hash_string(run['fixture_manifest_sha256']):
        raise Inconsistent('invalid run metadata')
    review = run['root_trace_review']
    if review is None:
        raise Pending('missing root trace review')
    if not isinstance(review, dict):
        raise Inconsistent('invalid root trace review')
    exact_keys(review, {'path', 'sha256'}, 'root trace review')
    if not read_artifact(root, review['path'], review['sha256']).strip():
        raise Pending('empty root trace review')
    contexts_seen = set()
    for i in range(12):
        name = f'HC{i}'
        row = read_record(root, name + '.json')
        exact_keys(row, ROW_KEYS, name)
        if row['control'] != name or row['candidate_identity'] != candidate or row['goal_sha256'] != goal:
            raise Inconsistent('identity mismatch: ' + name)
        if not hash_string(row['payload_sha256']) or not string(row['reason']):
            raise Inconsistent('invalid payload hash or reason: ' + name)
        if row['result'] == 'PENDING':
            raise Pending('pending control: ' + name)
        if row['result'] != 'PASS':
            raise Inconsistent('failed or invalid result: ' + name)
        if row['eligibility'] not in ('eligible', 'ineligible'):
            raise Inconsistent('invalid eligibility: ' + name)
        if i in (7, 8) and row['eligibility'] != 'ineligible':
            raise Inconsistent('negative probe marked eligible: ' + name)
        if i in (1, 2, 3, 4, 10) and row['eligibility'] != 'eligible':
            raise Inconsistent('positive probe ineligible: ' + name)
        if not isinstance(row['request'], (dict, str)) or not row['request']:
            raise Inconsistent('invalid request: ' + name)
        reads = row['observed_reads']
        if not isinstance(reads, list) or not all(string(x) for x in reads):
            raise Inconsistent('invalid observed reads: ' + name)
        ids = row['context_ids']
        if not isinstance(ids, list) or not all(string(x) for x in ids):
            raise Inconsistent('invalid context IDs: ' + name)
        if i in (0, 9, 11):
            if ids or row['tool_trace_path'] is not None or row['tool_trace_sha256'] is not None:
                raise Inconsistent('unexpected launch: ' + name)
        else:
            if not ids:
                raise Pending('missing context ID: ' + name)
            if i == 10 and (len(ids) != 2 or ids[0] == ids[1]):
                raise Inconsistent('HC10 requires two different contexts')
            if i != 4 and len(set(ids)) != len(ids):
                raise Inconsistent('duplicate context ID: ' + name)
            if set(ids) & contexts_seen:
                raise Inconsistent('context reused between controls: ' + name)
            contexts_seen.update(ids)
            read_artifact(root, row['tool_trace_path'], row['tool_trace_sha256'])
        read_artifact(root, row['raw_return_path'], row['raw_return_sha256'])
    if len(contexts_seen) > 12:
        raise Inconsistent('context ceiling exceeded')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence-dir', required=True)
    parser.add_argument('--candidate', required=True)
    parser.add_argument('--goal', required=True)
    args = parser.parse_args()
    if not hash_string(args.candidate) or not hash_string(args.goal) or not pathlib.Path(args.evidence_dir).is_absolute():
        parser.error('expected absolute evidence directory and lowercase SHA-256 identities')
    try:
        validate(pathlib.Path(args.evidence_dir), args.candidate, args.goal)
    except Pending as error:
        print('HOST-EVIDENCE: PENDING: ' + str(error)); return 2
    except Inconsistent as error:
        print('HOST-EVIDENCE: INCONSISTENT: ' + str(error)); return 1
    print('HOST-EVIDENCE: COMPLETE'); return 0

if __name__ == '__main__':
    sys.exit(main())
