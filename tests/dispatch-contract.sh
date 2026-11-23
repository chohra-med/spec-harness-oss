#!/usr/bin/env bash
# Synthetic contract controls. They do not launch model contexts or prove host behavior.
set -u
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HARNESS_DIR="${SPEC_HARNESS_DIR:-$(cd "$TEST_DIR/.." && pwd -P)}"
TMP_PARENT="$(cd "${TMPDIR:-/tmp}" && pwd -P)" || exit 1
TMP="$(mktemp -d "$TMP_PARENT/sh-dispatch-contract.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT
python3 -I -B - "$HARNESS_DIR" "$TMP" <<'PY'
import copy, hashlib, json, os, pathlib, subprocess, sys
root, tmp = map(pathlib.Path, sys.argv[1:])
validator = root / 'tests/check-host-controls.py'
checker = root / 'bin/sh-dispatch-check.py'
failures = []
def sha(data): return hashlib.sha256(data).hexdigest()
def put(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data if isinstance(data, bytes) else data.encode())
def enc(value): return json.dumps(value, sort_keys=True, separators=(',', ':')).encode()
def run(args): return subprocess.run([sys.executable, '-I', '-B', *map(str,args)], capture_output=True, text=True)
def check(label, ok, output=''):
    print(('PASS: ' if ok else 'FAIL: ') + label)
    if not ok: failures.append(label); print(output[:1500])
def validation(directory, candidate='a'*64, goal='b'*64):
    return run([validator, '--evidence-dir', directory, '--candidate', candidate, '--goal', goal])
def case(label, directory, expected, candidate='a'*64, goal='b'*64):
    p=validation(directory,candidate,goal)
    check(label, p.returncode == expected, p.stdout+p.stderr)
def write_json(path, obj): put(path, json.dumps(obj, sort_keys=True))
def complete(directory):
    directory.mkdir(parents=True, exist_ok=True)
    artifacts = {}
    for name in ['review'] + [f'raw{i}' for i in range(12)] + [f'trace{i}' for i in range(12) if i not in (0,9,11)]:
        content=('synthetic '+name+'\n').encode(); put(directory/name,content); artifacts[name]=sha(content)
    run_record={'candidate_identity':'a'*64,'goal_sha256':'b'*64,'client':'synthetic client','controller_identity':'synthetic controller','fixture_manifest_sha256':'c'*64,'root_trace_review':{'path':'review','sha256':artifacts['review']}}
    write_json(directory/'run.json',run_record)
    for i in range(12):
        contexts = [] if i in (0,9,11) else [f'context-{i}']
        if i == 10: contexts.append('context-10-replacement')
        trace = None if i in (0,9,11) else f'trace{i}'
        row={'control':f'HC{i}','candidate_identity':'a'*64,'goal_sha256':'b'*64,'payload_sha256':'d'*64,'request':{'synthetic':True},'context_ids':contexts,'raw_return_path':f'raw{i}','raw_return_sha256':artifacts[f'raw{i}'],'tool_trace_path':trace,'tool_trace_sha256':artifacts.get(trace),'observed_reads':[],'eligibility':'ineligible' if i in (7,8) else 'eligible','result':'PASS','reason':'synthetic observation'}
        write_json(directory/f'HC{i}.json',row)
    return run_record

def mutate(directory, filename, fn):
    path=directory/filename; obj=json.loads(path.read_text()); fn(obj); write_json(path,obj)
case('missing evidence is PENDING',tmp/'empty',2)
d=tmp/'full'; complete(d); case('complete synthetic host evidence',d,0)
for label, filename, field, value, expected in [
 ('forged PASS without trace','HC1.json','tool_trace_path',None,2),
 ('candidate mismatch','HC2.json','candidate_identity','e'*64,1),
 ('goal mismatch','HC2.json','goal_sha256','e'*64,1),
 ('inherited context eligible','HC7.json','eligibility','eligible',1),
 ('followed-up context eligible','HC8.json','eligibility','eligible',1),
 ('HC10 missing fresh replacement','HC10.json','context_ids',['same'],1),
 ('HC10 reused context','HC10.json','context_ids',['same','same'],1),
 ('unknown receipt field','HC3.json','unknown','prior verdict',1),
 ('pending observation','HC3.json','result','PENDING',2),
 ('failed observation','HC3.json','result','FAIL',1),
 ('path traversal','HC1.json','raw_return_path','../escape',1),
]:
    d=tmp/('case-'+str(len(failures))+'-'+label.replace(' ','-')); complete(d)
    mutate(d,filename,lambda o:o.__setitem__(field,value)); case(label,d,expected)
d=tmp/'changed'; complete(d); put(d/'raw1','changed'); case('changed artifact',d,1)
d=tmp/'review-missing'; complete(d); (d/'review').unlink(); case('root trace review required',d,2)
d=tmp/'duplicate'; complete(d); p=d/'HC2.json'; p.write_text(p.read_text()[:-1]+',"control":"HC2"}'); case('duplicate JSON key refused',d,1)
d=tmp/'symlink'; complete(d); (d/'raw1').unlink(); os.symlink(d/'raw2',d/'raw1'); case('symlink artifact refused',d,1)
# This fixture is synthetic, uses a declared non-Git scope and creates no host contexts.
src=tmp/'source'; feature=tmp/'feature'; evidence=tmp/'pins'; src.mkdir(); feature.mkdir(); evidence.mkdir()
for name in ['AGENTS.md','commands/sdd.md']+[f'agents/{role}.md' for role in ('sdd-tester','sdd-verifier','sdd-reviewer','sdd-plan-goldfish')]: put(src/name,'synthetic '+name+'\n')
for name in ('input.md','spec.md','goal.md','plan.md','tasks.md'): put(feature/name,'synthetic '+name+'\n')
source_names=sorted(str(p.relative_to(src)) for p in src.rglob('*') if p.is_file())
manifest_path=feature/'dependencies.json'; pin_path=evidence/'source-pin.json'; payload_path=evidence/'payload.txt'

def fixture(manifest_change=None, pin_change=None, role='sdd-verifier', phase=None):
    files={name:{'kind':'file','sha256':sha((src/name).read_bytes()),'mode':(src/name).stat().st_mode & 0o777} for name in source_names}
    manifest={'schema':1,'source_files':source_names[:], 'packet_dependencies':{name:sha((feature/name).read_bytes()) for name in ('input.md','spec.md','goal.md','plan.md','tasks.md')}}
    if manifest_change: manifest_change(manifest)
    put(manifest_path,enc(manifest))
    pin={'root':str(src),'marker':'non-Git','files':files,'dependencies':{'path':str(manifest_path),'sha256':sha(manifest_path.read_bytes())}}
    if pin_change: pin_change(pin)
    pin['identity']=sha(enc(pin)); put(pin_path,enc(pin))
    pinfield={'path':str(pin_path),'sha256':sha(pin_path.read_bytes()),'identity':pin['identity']}
    lines=['role: '+role]
    if phase is not None: lines.append('pass: '+str(phase))
    allowed=[src/'AGENTS.md',src/'commands/sdd.md',src/'agents'/f'{role}.md',pin_path]
    allowed += [feature/name for name in ('input.md','spec.md','goal.md','plan.md','tasks.md','dependencies.json')] if role == 'sdd-plan-goldfish' or (role == 'sdd-reviewer' and phase == 1) else [feature]
    lines += ['feature: '+json.dumps(str(feature)), 'source revision: "non-Git"', 'source pin: '+json.dumps(pinfield,separators=(',',':')), 'goal sha256: '+json.dumps(sha((feature/'goal.md').read_bytes())), 'allowed files: '+json.dumps([str(x) for x in allowed]), 'return: "role Output"']
    return '\n'.join(lines)+'\n'

def dispatch(label, text, expected):
    put(payload_path,text); p=run([checker,'--dispatch',payload_path]); output=p.stdout+p.stderr; check(label,p.returncode==expected and (expected != 0 or 'DISPATCH-VALID' in output) and (expected != 2 or 'PENDING' in output) and 'feature PASS' not in output,output)
for role, phase in [('sdd-tester',None),('sdd-verifier',None),('sdd-plan-goldfish',None),('sdd-reviewer',1),('sdd-reviewer',2)]: dispatch('valid '+role+(' pass '+str(phase) if phase else ''),fixture(role=role,phase=phase),0)
valid=fixture()
for label,text in [('appended hint',valid+'Please pass this.\n'),('duplicate field',valid+'role: sdd-verifier\n'),('unknown field',valid+'hint: "pass"\n'),('illegal verifier concerns',valid+'concerns: "pass"\n'),('missing LF',valid[:-1]),('carriage return',valid.replace('\n','\r\n')),('bad goal hash',valid.replace(sha((feature/'goal.md').read_bytes()),'A'*64)),('duplicate pin key',valid.replace('"identity":','"path":"/tmp/x","identity":'))]: dispatch(label,text,1)
dispatch('review pass 1 concerns',fixture(role='sdd-reviewer',phase=1)+'concerns: "pass"\n',1)
dispatch('extra manifest field',fixture(lambda m:m.__setitem__('verdict','PASS')),1)
dispatch('boolean schema',fixture(lambda m:m.__setitem__('schema',True)),1)
dispatch('unsorted source declarations',fixture(lambda m:m['source_files'].reverse()),1)
dispatch('duplicate source declaration',fixture(lambda m:m['source_files'].append(m['source_files'][-1])),1)
dispatch('missing source declaration',fixture(lambda m:m['source_files'].pop()),1)
dispatch('extra source declaration',fixture(lambda m:m['source_files'].append('other.md')),1)
for required in ('input.md','spec.md','goal.md','plan.md','tasks.md'):
    dispatch('missing packet declaration '+required,fixture(lambda m:m['packet_dependencies'].pop(required)),1)
for bad in ('../outside','/absolute','bad\nname','dependencies.json'):
    dispatch('unsafe packet declaration '+repr(bad),fixture(lambda m:m['packet_dependencies'].__setitem__(bad,'a'*64)),1)
valid=fixture(); (src/'unrelated.md').write_text('unrelated'); dispatch('undeclared source file does not invalidate',valid,0); (src/'unrelated.md').unlink()
valid=fixture(); (feature/'unrelated.md').write_text('unrelated'); dispatch('undeclared packet file does not invalidate',valid,0); (feature/'unrelated.md').unlink()
valid=fixture(); (feature/'plan.md').write_text('changed'); dispatch('changed declared packet bytes',valid,1); (feature/'plan.md').write_text('synthetic plan.md\n')
valid=fixture(); (feature/'plan.md').unlink(); dispatch('deleted declared packet input',valid,2); (feature/'plan.md').write_text('synthetic plan.md\n')
valid=fixture(); manifest_path.unlink(); dispatch('missing dependency manifest',valid,2)
valid=fixture(); manifest_path.write_bytes(manifest_path.read_bytes()+b' '); dispatch('stale manifest byte hash',valid,1)
valid=fixture(); (src/'AGENTS.md').write_text('changed'); dispatch('changed source bytes',valid,1); (src/'AGENTS.md').write_text('synthetic AGENTS.md\n')
valid=fixture(); (src/'AGENTS.md').chmod(0o600); dispatch('changed source mode',valid,1); (src/'AGENTS.md').chmod(0o644)
valid=fixture(); dispatch('goal hash differs from payload',valid.replace(sha((feature/'goal.md').read_bytes()),'a'*64),1)

# Additional manifest and no-follow controls, repinned where the malformed content itself is under test.
def rebind_manifest(text, raw):
    put(manifest_path,raw)
    pin=json.loads(pin_path.read_text()); pin.pop('identity'); pin['dependencies']['sha256']=sha(raw); pin['identity']=sha(enc(pin)); put(pin_path,enc(pin))
    replacement={'path':str(pin_path),'sha256':sha(pin_path.read_bytes()),'identity':pin['identity']}
    return '\n'.join('source pin: '+json.dumps(replacement,separators=(',',':')) if line.startswith('source pin: ') else line for line in text.splitlines())+'\n'
valid=fixture(); duplicate=b'{"schema":1,'+manifest_path.read_bytes()[1:]; dispatch('duplicate manifest key',rebind_manifest(valid,duplicate),1)
dispatch('non-integer schema',fixture(lambda m:m.__setitem__('schema','1')),1)
dispatch('pin unknown key',fixture(pin_change=lambda p:p.__setitem__('verdict','PASS')),1)
valid=fixture(); packetfile=feature/'plan.md'; packetfile.unlink(); os.symlink(feature/'goal.md',packetfile); dispatch('linked packet input refused',valid,1); packetfile.unlink(); put(packetfile,'synthetic plan.md\n')
valid=fixture(); packetfile.unlink(); os.mkfifo(packetfile); dispatch('special packet input refused',valid,1); packetfile.unlink(); put(packetfile,'synthetic plan.md\n')
absent='absent.txt'
valid=fixture(lambda m:m['source_files'].append(absent) or m['source_files'].sort(),lambda p:p['files'].__setitem__(absent,{'kind':'absent'})); dispatch('declared absent source',valid,0); put(src/absent,'appeared'); dispatch('declared absent source now present',valid,1); (src/absent).unlink()
link=src/'synthetic-link'; os.symlink('first-target',link); link_mode=link.lstat().st_mode & 0o777
valid=fixture(lambda m:m['source_files'].append('synthetic-link') or m['source_files'].sort(),lambda p:p['files'].__setitem__('synthetic-link',{'kind':'symlink','target':'first-target','mode':link_mode})); dispatch('declared symlink identity',valid,0); link.unlink(); os.symlink('second-target',link); dispatch('changed symlink target',valid,1); link.unlink()

# Nested JSON duplication, missing declared content, and symlinked parent directories.
valid=fixture(); raw=manifest_path.read_bytes(); marker=b'"packet_dependencies":{'; assert marker in raw
raw=raw.replace(marker,marker+b'"goal.md":"'+sha((feature/'goal.md').read_bytes()).encode()+b'",',1)
dispatch('duplicate nested dependency key',rebind_manifest(valid,raw),1)
valid=fixture(); (src/'AGENTS.md').unlink(); dispatch('deleted declared source',valid,2); put(src/'AGENTS.md','synthetic AGENTS.md\n')
real=feature/'real-parent'; real.mkdir(); put(real/'child.md','synthetic child\n'); os.symlink(real,feature/'linked-parent')
valid=fixture(lambda m:m['packet_dependencies'].__setitem__('linked-parent/child.md',sha((real/'child.md').read_bytes())))
dispatch('linked packet parent refused',valid,1); (feature/'linked-parent').unlink(); (real/'child.md').unlink(); real.rmdir()
real=src/'real-parent'; real.mkdir(); put(real/'child.md','synthetic child\n'); os.symlink(real,src/'linked-parent')
entry={'kind':'file','sha256':sha((real/'child.md').read_bytes()),'mode':0o644}
valid=fixture(lambda m:m['source_files'].append('linked-parent/child.md') or m['source_files'].sort(),lambda p:p['files'].__setitem__('linked-parent/child.md',entry))
dispatch('linked source parent refused',valid,1); (src/'linked-parent').unlink(); (real/'child.md').unlink(); real.rmdir()

# Declared inputs cannot include outputs or a self-referential manifest.
dispatch('manifest self-reference refused',fixture(lambda m:m['packet_dependencies'].__setitem__('dependencies.json','a'*64)),1)
put(feature/'dispatch.txt','synthetic output'); dispatch('dispatch output dependency refused',fixture(lambda m:m['packet_dependencies'].__setitem__('dispatch.txt',sha((feature/'dispatch.txt').read_bytes()))),1); (feature/'dispatch.txt').unlink()
valid=fixture(); manifest_copy=evidence/'manifest-copy.json'; put(manifest_copy,manifest_path.read_bytes()); manifest_path.unlink(); os.symlink(manifest_copy,manifest_path); dispatch('linked dependency manifest refused',valid,1); manifest_path.unlink(); manifest_copy.unlink()
valid=fixture(); pin_copy=evidence/'pin-copy.json'; put(pin_copy,pin_path.read_bytes()); pin_path.unlink(); os.symlink(pin_copy,pin_path); dispatch('linked identity pin refused',valid,1); pin_path.unlink(); pin_copy.unlink()
# A missing implementer status has the central no-status concern, only where concerns are allowed.
dispatch('tester default no-status concern',fixture(role='sdd-tester')+'concerns: "no status given"\n',0)
dispatch('reviewer pass 2 default no-status concern',fixture(role='sdd-reviewer',phase=2)+'concerns: "no status given"\n',0)
dispatch('tester arbitrary unquoted concern refused',fixture(role='sdd-tester')+'concerns: "invented concern"\n',1)

# A pin cannot be an input of the manifest that binds that pin.
saved_pin_path=pin_path; pin_path=feature/'source-pin.json'
cycle=fixture(lambda m:m['packet_dependencies'].__setitem__('source-pin.json','a'*64))
put(payload_path,cycle); result=run([checker,'--dispatch',payload_path]); message=result.stdout+result.stderr
check('pin/manifest cycle refused explicitly',result.returncode==1 and any(x in message.lower() for x in ('cycle','self-reference','output')),message)
pin_path.unlink(); pin_path=saved_pin_path

# In-process wrapper around the actual safe reader; no production test hook or timed race.
import contextlib, importlib.util, io
try:
    spec=importlib.util.spec_from_file_location('dispatch_checker_under_test',checker)
    if spec is None or spec.loader is None: raise RuntimeError('checker loader unavailable')
    module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    real_reader=module.read_bounded
    main=module.main
except Exception as error:
    check('actual checker callable and safe-reader binding',False,repr(error))
else:
    check('actual checker callable and safe-reader binding',callable(main) and callable(real_reader))
    def invoke_with_reader(text, target=None, mutate=False):
        put(payload_path,text); fired=[]; reads=[]; out=io.StringIO(); err=io.StringIO()
        def wrapping_reader(path,max_bytes,*,root=None,allow_symlink=False):
            data=real_reader(path,max_bytes,root=root,allow_symlink=allow_symlink)
            reads.append(str(path))
            lexical=pathlib.Path(root)/path if root is not None else pathlib.Path(path)
            if mutate and lexical==target and not fired:
                target.write_bytes(target.read_bytes()+b'changed during validation\n'); fired.append(True)
            return data
        try:
            module.read_bounded=wrapping_reader
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                code=module.main(['--dispatch',str(payload_path)])
        finally:
            module.read_bounded=real_reader
        return code, bool(fired), reads, out.getvalue()+err.getvalue()
    valid=fixture(); code,fired,reads,output=invoke_with_reader(valid)
    check('no-op actual reader wrapper remains valid',code==0 and bool(reads) and not fired,output)
    for label,target in [('source',src/'AGENTS.md'),('packet',feature/'plan.md')]:
        valid=fixture(); original=target.read_bytes(); original_mode=target.stat().st_mode & 0o777
        try:
            code,fired,reads,output=invoke_with_reader(valid,target,True)
            check(label+' mid-check mutation rejected',code==1 and fired and bool(reads) and any(word in output.lower() for word in ('changed','mismatch','stale','hash')),output)
        finally:
            target.write_bytes(original); target.chmod(original_mode)
        put(payload_path,valid); output=io.StringIO()
        with contextlib.redirect_stdout(output),contextlib.redirect_stderr(output):
            code=module.main(['--dispatch',str(payload_path)])
        check(label+' restored bytes pass with real reader',code==0,output.getvalue())

    # Synthetic provenance only: byte correspondence does not prove actual origin.
    raw_path=evidence/'implementer-return.txt'; envelope_path=evidence/'concerns-envelope.json'
    concern='First concern\nSecond concern'
    raw_bytes=('Synthetic implementer handback\n'+concern+'\nSTATUS: DONE_WITH_CONCERNS\n').encode()
    def make_concern_fixture(role='sdd-tester',phase=None,edit=None,raw=raw_bytes,selected=concern):
        text=fixture(role=role,phase=phase); pin=json.loads(pin_path.read_text()); put(raw_path,raw)
        start=raw.find(concern.encode()); end=start+len(concern.encode())
        env={'schema':1,'source_identity':pin['identity'],'goal_sha256':sha((feature/'goal.md').read_bytes()),'context_id':'synthetic-implementer','request_sha256':'a'*64,'raw_return':{'path':raw_path.name,'sha256':sha(raw)},'concerns_range':{'start':start,'end':end}}
        if edit: edit(env)
        env['identity']=sha(enc(env)); put(envelope_path,enc(env))
        reference={'path':str(envelope_path),'sha256':sha(envelope_path.read_bytes()),'identity':env['identity']}
        return text+'concerns source: '+json.dumps(reference,separators=(',',':'))+'\nconcerns: '+json.dumps(selected)+'\n'
    def rebind_envelope(text,raw):
        put(envelope_path,raw); old=next(x for x in text.splitlines() if x.startswith('concerns source: ')); ref=json.loads(old.split(': ',1)[1]); ref['sha256']=sha(raw)
        return text.replace(old,'concerns source: '+json.dumps(ref,separators=(',',':')))
    def probe_concern(label,text,expected,need=(),forbid=(),target=None):
        put(payload_path,text); reads=[]; fired=[]; out=io.StringIO()
        def reader(path,max_bytes,*,root=None,allow_symlink=False):
            lexical=pathlib.Path(root)/path if root is not None else pathlib.Path(path)
            reads.append(lexical)
            data=real_reader(path,max_bytes,root=root,allow_symlink=allow_symlink)
            if target == lexical and not fired:
                target.write_bytes(target.read_bytes()+b'changed\n'); fired.append(True)
            return data
        try:
            module.read_bounded=reader
            with contextlib.redirect_stdout(out),contextlib.redirect_stderr(out):
                code=module.main(['--dispatch',str(payload_path)])
        finally: module.read_bounded=real_reader
        ok=(code==expected and all(p in reads for p in need) and not any(p in reads for p in forbid) and (target is None or bool(fired)))
        check(label,ok,'exit='+str(code)+' reads='+repr(reads)+' output='+out.getvalue())
    for role,phase in [('sdd-tester',None),('sdd-reviewer',2)]:
        probe_concern('valid synthetic provenance '+role,make_concern_fixture(role,phase),0,need=(envelope_path,raw_path))
    for role,phase in [('sdd-verifier',None),('sdd-plan-goldfish',None),('sdd-reviewer',1)]:
        base=fixture(role=role,phase=phase)
        for suffix in ['concerns: "no status given"\n','concerns source: '+json.dumps({'path':str(envelope_path),'sha256':'a'*64,'identity':'b'*64})+'\n','concerns source: '+json.dumps({'path':str(envelope_path),'sha256':'a'*64,'identity':'b'*64})+'\nconcerns: "synthetic"\n']:
            probe_concern('prohibited '+role+' '+str(len(suffix)),base+suffix,1,forbid=(envelope_path,raw_path))
    probe_concern('non-default concern without provenance',fixture(role='sdd-tester')+'concerns: "synthetic"\n',1)
    text=make_concern_fixture(); refline=next(x for x in text.splitlines() if x.startswith('concerns source: '))
    probe_concern('source without concerns',fixture(role='sdd-tester')+refline+'\n',1,forbid=(envelope_path,raw_path))
    probe_concern('default with source',fixture(role='sdd-tester')+refline+'\nconcerns: "no status given"\n',1,forbid=(envelope_path,raw_path))
    for label,selected in [('changed concern','First concern\nOther concern'),('missing concern','First concern'),('extra concern',concern+'\nextra')]:
        probe_concern(label,make_concern_fixture(selected=selected),1,need=(envelope_path,raw_path))
    for label,edit in [
      ('wrong source identity',lambda x:x.__setitem__('source_identity','b'*64)),
      ('wrong goal hash',lambda x:x.__setitem__('goal_sha256','b'*64)),
      ('boolean schema',lambda x:x.__setitem__('schema',True)),
      ('unknown field',lambda x:x.__setitem__('verdict','PASS')),
      ('missing field',lambda x:x.pop('request_sha256')),
      ('invalid request hash',lambda x:x.__setitem__('request_sha256','X'*64)),
      ('empty context',lambda x:x.__setitem__('context_id','')),
      ('boolean start',lambda x:x['concerns_range'].__setitem__('start',True)),
      ('empty range',lambda x:x['concerns_range'].__setitem__('end',x['concerns_range']['start'])),
      ('non-line start',lambda x:x['concerns_range'].__setitem__('start',x['concerns_range']['start']+1)),
      ('non-line end',lambda x:x['concerns_range'].__setitem__('end',x['concerns_range']['end']-1)),
      ('out of bounds',lambda x:x['concerns_range'].__setitem__('end',999999)),
      ('traversal raw path',lambda x:x['raw_return'].__setitem__('path','../other')),
      ('absolute raw path',lambda x:x['raw_return'].__setitem__('path','/other')),
      ('self reference',lambda x:x['raw_return'].__setitem__('path',envelope_path.name)),
      ('unknown raw field',lambda x:x['raw_return'].__setitem__('extra','x')),
      ('wrong raw hash type',lambda x:x['raw_return'].__setitem__('sha256',False)),
      ('negative range start',lambda x:x['concerns_range'].__setitem__('start',-1)),
      ('unknown range field',lambda x:x['concerns_range'].__setitem__('extra',1)),
    ]:
        probe_concern(label,make_concern_fixture(edit=edit),1,need=(envelope_path,))
    text=make_concern_fixture(); old=next(x for x in text.splitlines() if x.startswith('concerns source: ')); ref=json.loads(old.split(': ',1)[1]); ref['identity']='b'*64
    probe_concern('wrong envelope identity',text.replace(old,'concerns source: '+json.dumps(ref)),1,need=(envelope_path,))
    text=make_concern_fixture(); put(envelope_path,envelope_path.read_bytes()+b' '); probe_concern('stale envelope hash',text,1,need=(envelope_path,))
    text=make_concern_fixture(); raw_path.unlink(); probe_concern('absent raw return',text,2,need=(envelope_path,raw_path))
    text=make_concern_fixture(); put(raw_path,raw_bytes+b'changed'); probe_concern('stale raw return',text,1,need=(envelope_path,raw_path))
    for label,raw in [('wrong status',raw_bytes.replace(b'DONE_WITH_CONCERNS',b'DONE')),('ambiguous status',b'STATUS: DONE\n'+raw_bytes),('CR in return',raw_bytes.replace(b'\n',b'\r\n')),('invalid UTF8',raw_bytes+b'\xff')]:
        probe_concern(label,make_concern_fixture(raw=raw),1,need=(envelope_path,raw_path))
    text=make_concern_fixture(); raw=envelope_path.read_bytes(); raw=b'{"schema":1,'+raw[1:]; probe_concern('duplicate envelope key',rebind_envelope(text,raw),1,need=(envelope_path,))
    probe_concern('valid raw return without final LF',make_concern_fixture(raw=raw_bytes[:-1]),0,need=(envelope_path,raw_path))
    utf8_raw=raw_bytes.replace(b'Synthetic', 'Synthé'.encode())
    probe_concern('UTF-8 splitting offset',make_concern_fixture(edit=lambda x:x['concerns_range'].__setitem__('start',utf8_raw.index(b'\xc3')+1),raw=utf8_raw),1,need=(envelope_path,raw_path))
    text=make_concern_fixture(); raw=envelope_path.read_bytes(); envelope_path.unlink(); copied=evidence/'copy-envelope.json'; put(copied,raw); os.symlink(copied,envelope_path)
    probe_concern('linked envelope refused',text,1,forbid=(raw_path,)); envelope_path.unlink(); copied.unlink()
    real=evidence/'real-parent'; real.mkdir(); put(real/'return.txt',raw_bytes); os.symlink(real,evidence/'linked-parent')
    text=make_concern_fixture(edit=lambda x:x['raw_return'].__setitem__('path','linked-parent/return.txt'))
    probe_concern('linked raw parent refused',text,1,need=(envelope_path,)); (evidence/'linked-parent').unlink(); (real/'return.txt').unlink(); real.rmdir()
    alias=tmp/'aliased-source'; os.symlink(src,alias); text=fixture(pin_change=lambda x:x.__setitem__('root',str(alias))); dispatch('aliased source root refused',text,1); alias.unlink()
    text=make_concern_fixture(); raw_path.unlink(); os.symlink(envelope_path,raw_path); probe_concern('linked raw return',text,1,need=(envelope_path,raw_path)); raw_path.unlink()
    text=make_concern_fixture(); raw_path.unlink(); os.mkfifo(raw_path); probe_concern('special raw return',text,1,need=(envelope_path,raw_path)); raw_path.unlink()
    for label,target in [('envelope',envelope_path),('raw return',raw_path)]:
        text=make_concern_fixture(); original=target.read_bytes()
        try: probe_concern(label+' post-read mutation',text,1,need=(target,),target=target)
        finally: put(target,original)
        probe_concern(label+' restored after mutation',text,0,need=(envelope_path,raw_path))

    # The scope matrix exercises the actual main and records actual bounded-reader calls.
    def scope_payload(role,phase,paths):
        text=fixture(role=role,phase=phase)
        return '\n'.join('allowed files: '+json.dumps([str(p) for p in paths]) if line.startswith('allowed files: ') else line for line in text.splitlines())+'\n'
    def scope_check(label,role,phase,paths,expected,forbidden=None):
        text=scope_payload(role,phase,paths); put(payload_path,text); reads=[]; captured=io.StringIO()
        def reader(path,max_bytes,*,root=None,allow_symlink=False):
            lexical=pathlib.Path(root)/path if root is not None else pathlib.Path(path)
            reads.append(lexical)
            return real_reader(path,max_bytes,root=root,allow_symlink=allow_symlink)
        try:
            module.read_bounded=reader
            with contextlib.redirect_stdout(captured),contextlib.redirect_stderr(captured): code=module.main(['--dispatch',str(payload_path)])
        finally: module.read_bounded=real_reader
        observed_forbidden=forbidden is not None and any(r==forbidden or forbidden in r.parents for r in reads)
        check(label,code==expected and not observed_forbidden,'exit='+str(code)+' reads='+repr(reads)+' output='+captured.getvalue())
    def scopes(role):
        return [src/'AGENTS.md',src/'commands/sdd.md',src/'agents'/f'{role}.md',feature/'input.md',feature/'spec.md',feature/'goal.md',feature/'plan.md',feature/'tasks.md',pin_path,feature/'dependencies.json']
    for name in ('CLAUDE.md','RULES.md','CONTRIBUTING.md','constitution.md'): put(src/name,'synthetic policy\n')
    put(src/'ai_rules/rules/policy.md','synthetic rule\n'); put(src/'.memory/30-tech.md','neutral technology\n'); put(src/'.memory/80-feedback.md','forbidden history\n')
    put(src/'.spec-harness/runs/prior.txt','forbidden run\n'); put(src/'specs/other/goal.md','other packet\n')
    put(src/'safe-source/code.txt','synthetic source\n'); put(src/'tests-scope/test.txt','synthetic test\n')
    put(src/'.memory/80-feedback.md.extra','prefix lookalike\n'); put(src/'.spec-harness-safe/data.txt','prefix lookalike\n')
    put(feature/'gate-briefs.md','forbidden brief\n'); put(feature/'gates/tester.md','forbidden gate\n'); put(feature/'gates/source-recheck.md','ticket recheck\n')
    for role,phase in [('sdd-plan-goldfish',None),('sdd-reviewer',1)]:
        base=scopes(role)
        for label,path in [('explicit brief',feature/'gate-briefs.md'),('explicit gate',feature/'gates/tester.md'),('missing gate',feature/'gates/missing.md'),('feature parent',feature),('gates parent',feature/'gates'),('feedback',src/'.memory/80-feedback.md'),('memory parent',src/'.memory'),('run',src/'.spec-harness/runs/prior.txt'),('harness parent',src/'.spec-harness'),('other packet',src/'specs/other/goal.md'),('all specs',src/'specs'),('recheck prefix',feature/'gates/source-recheck.md.extra'),('recheck child',feature/'gates/source-recheck.md/child')]:
            scope_check(role+' rejects '+label,role,phase,base+[path],1,forbidden=path)
        positives=base+[src/'CLAUDE.md',src/'RULES.md',src/'CONTRIBUTING.md',src/'constitution.md',src/'ai_rules/rules/policy.md',src/'.memory/30-tech.md',src/'safe-source',src/'tests-scope',src/'.memory/80-feedback.md.extra',src/'.spec-harness-safe']
        scope_check(role+' allows exact neutral and safe scopes',role,phase,positives,0)
    scope_check('goldfish rejects source recheck','sdd-plan-goldfish',None,scopes('sdd-plan-goldfish')+[feature/'gates/source-recheck.md'],1,forbidden=feature/'gates/source-recheck.md')
    scope_check('reviewer pass 1 allows exact source recheck','sdd-reviewer',1,scopes('sdd-reviewer')+[feature/'gates/source-recheck.md'],0)
    scope_check('tester allows selected brief','sdd-tester',None,scopes('sdd-tester')+[feature/'gate-briefs.md'],0)
    scope_check('reviewer pass 2 allows selected brief and record','sdd-reviewer',2,scopes('sdd-reviewer')+[feature/'gate-briefs.md',feature/'gates/tester.md'],0)
    # Repeat selected-feature overlap under source/specs, not just in the external packet.
    external_feature=feature; external_manifest_path=manifest_path; feature=src/'specs/chosen'; feature.mkdir(parents=True); manifest_path=feature/'dependencies.json'
    for name in ('input.md','spec.md','goal.md','plan.md','tasks.md'): put(feature/name,'synthetic '+name+'\n')
    put(feature/'gate-briefs.md','forbidden brief\n'); put(feature/'gates/source-recheck.md','ticket recheck\n')
    for role,phase in [('sdd-plan-goldfish',None),('sdd-reviewer',1)]:
        base=scopes(role)
        scope_check(role+' internal feature exact docs',role,phase,base,0)
        scope_check(role+' internal feature brief',role,phase,base+[feature/'gate-briefs.md'],1,forbidden=feature/'gate-briefs.md')
        scope_check(role+' internal feature broad ancestor',role,phase,base+[src/'specs'],1,forbidden=feature/'gate-briefs.md')
    scope_check('internal reviewer allows exact recheck','sdd-reviewer',1,scopes('sdd-reviewer')+[feature/'gates/source-recheck.md'],0)
    feature=external_feature; manifest_path=external_manifest_path

# A disposable synthetic Git repository exercises clean and dirty identity without touching source Git state.
gitroot=tmp/'git-source'; gitroot.mkdir()
def git(*args): return subprocess.check_output(['git',*args],cwd=gitroot,stderr=subprocess.PIPE)
git('init','-q'); git('config','user.name','Fixture'); git('config','user.email','fixture@example.invalid')
for name in source_names: put(gitroot/name,(src/name).read_bytes())
git('add','--all'); git('commit','-qm','synthetic fixture')
def git_fixture(role='sdd-verifier'):
    names=sorted({os.fsdecode(x) for x in git('ls-files','--cached','--others','--exclude-standard','-z').split(b'\0') if x})
    files={}
    for name in names:
        p=gitroot/name
        if not p.exists() and not p.is_symlink(): files[name]={'kind':'absent'}
        elif p.is_symlink(): files[name]={'kind':'symlink','target':os.readlink(p),'mode':p.lstat().st_mode & 0o777}
        else: files[name]={'kind':'file','sha256':sha(p.read_bytes()),'mode':p.stat().st_mode & 0o777}
    pin={'root':str(gitroot),'head':git('rev-parse','HEAD').decode().strip(),'branch':git('branch','--show-current').decode().strip(),'status':git('status','--porcelain=v1','--untracked-files=all').decode(), 'diff_head_sha256':sha(git('diff','--binary','HEAD')),'cached_diff_sha256':sha(git('diff','--binary','--cached')),'index_sha256':sha((gitroot/'.git/index').read_bytes()),'files':files}
    pin['identity']=sha(enc(pin)); put(pin_path,enc(pin)); pinfield={'path':str(pin_path),'sha256':sha(pin_path.read_bytes()),'identity':pin['identity']}
    return '\n'.join(['role: '+role,'feature: '+json.dumps(str(feature)),'source revision: '+json.dumps(pin['head']),'source pin: '+json.dumps(pinfield,separators=(',',':')),'goal sha256: '+json.dumps(sha((feature/'goal.md').read_bytes())),'allowed files: '+json.dumps([str(gitroot/'AGENTS.md'),str(gitroot/'commands/sdd.md'),str(gitroot/'agents'/f'{role}.md'),str(feature),str(pin_path)]),'return: "role Output"'])+'\n'
clean=git_fixture(); dispatch('clean Git identity',clean,0)
head=git('rev-parse','HEAD').decode().strip(); dispatch('stale Git source revision',clean.replace(head,'a'*len(head),1),1)
put(gitroot/'AGENTS.md','modified tracked bytes\n'); put(gitroot/'new-untracked.md','untracked bytes\n')
dirty=git_fixture(); dispatch('dirty Git tracked and untracked identity',dirty,0)
put(gitroot/'new-untracked.md','changed untracked bytes\n'); dispatch('dirty Git changed untracked bytes',dirty,1); put(gitroot/'new-untracked.md','untracked bytes\n')
(gitroot/'new-untracked.md').unlink(); dispatch('dirty Git deleted untracked file',dirty,1); put(gitroot/'new-untracked.md','untracked bytes\n')
put(gitroot/'extra-untracked.md','new\n'); dispatch('dirty Git added untracked file',dirty,1); (gitroot/'extra-untracked.md').unlink()
(gitroot/'AGENTS.md').chmod(0o600); dispatch('dirty Git changed tracked mode',dirty,1); (gitroot/'AGENTS.md').chmod(0o644)
git('add','AGENTS.md'); dispatch('dirty Git changed index',dirty,1)
git('add','--all'); git('commit','-qm','synthetic next revision'); dispatch('dirty Git stale HEAD',dirty,1)

if failures: print("RESULT: FAIL ("+str(len(failures))+" host evidence checks)"); sys.exit(1)
print("RESULT: PASS (synthetic host evidence contract)")
PY
