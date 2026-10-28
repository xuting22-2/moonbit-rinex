"""Run a cold separate public-API consumer of the unchanged BRUX prefix."""
from pathlib import Path
import argparse, hashlib, json, shutil, subprocess

p=argparse.ArgumentParser();p.add_argument('directory',type=Path);p.add_argument('--expected',type=Path,required=True)
p.add_argument('--target',choices=('js','wasm-gc'),default='js');a=p.parse_args()
root=Path(__file__).resolve().parents[1];output=a.directory.resolve()
assert not output.exists() and not output.is_relative_to(root)
raw=(root/'examples/brux-first-two-epochs.rnx').read_bytes()
assert hashlib.sha256(raw).hexdigest()=='ac515f3d762a12e255aaef49fa889272eab3b36e4fec4e6f9211cce0a7882896'
output.mkdir(parents=True);workspace=output/'workspace';workspace.mkdir();vendor=workspace/'vendor/rinex';vendor.mkdir(parents=True)
if (root/'.git').exists():
 names=subprocess.check_output(['git','ls-files','--cached','--others','--exclude-standard','-z'],cwd=root).decode().split('\0')
 names=sorted({n for n in names if n});origin='git checkout including non-ignored new files'
else:
 excluded={'.git','.mooncakes','_build','node_modules','__pycache__'}
 names=sorted(file.relative_to(root).as_posix() for file in root.rglob('*') if file.is_file() and not excluded.intersection(file.relative_to(root).parts))
 origin='exported source without git metadata'
for name in names:
 source=(root/name).resolve();assert source.is_file() and source.is_relative_to(root)
 destination=vendor/name;destination.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,destination)
app=workspace/'app';shutil.copytree(root/'examples/observation-consumer',app,ignore=shutil.ignore_patterns('.git','.mooncakes','_build','node_modules','__pycache__'))
(workspace/'moon.work').write_text('members = ["./vendor/rinex", "./app"]\n','utf-8',newline='\n')
lines=raw.decode('ascii').splitlines()
(app/'fixture.mbt').write_text('///|\nfn fixture() -> Array[String] {\n  [\n    '+',\n    '.join(json.dumps(line) for line in lines)+'\n  ]\n}\n','utf-8',newline='\n')
moon=shutil.which('moon');assert moon
run=subprocess.run([moon,'run','.','--target',a.target,'--deny-warn'],cwd=app,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=240)
(output/'stdout.log').write_text(run.stdout,'utf-8',newline='\n');(output/'stderr.log').write_text(run.stderr,'utf-8',newline='\n')
assert run.returncode==0,'Inspect retained consumer logs'
result=json.loads(run.stdout);expected={key:json.loads((a.expected/(key+'.json')).read_text('utf-8')) for key in ('header','report')}
expected['epochs']=[json.loads(line) for line in (a.expected/'epochs.ndjson').read_text('utf-8').splitlines()]
assert result==expected,'Complete public module result differs from Node host'
names=['moon.mod','moon.pkg','types.mbt','time.mbt','header.mbt','checker.mbt','reader.mbt','observation_types.mbt','pkg.generated.mbti',
 'examples/observation-consumer/main.mbt','examples/observation-consumer/moon.mod','examples/observation-consumer/moon.pkg','tools/run-observation-consumer.py']
receipt=dict(target=a.target,separateModule=True,sourceOrigin=origin,exitCode=0,wholeReportMatches=True,
 inputSha256=hashlib.sha256(raw).hexdigest(),selectedEpochs=len(result['epochs']),selectedSatelliteRecords=sum(len(e['satellites']) for e in result['epochs']),
 complete=result['report']['complete'],inputAcceptable=result['report']['acceptable'],
 sourceSha256={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in names},
 limits=['project-authored separate module, not external adoption','prefix has complete epochs but retains full-day header; unacceptable input is not hidden',
 'stored numbers, exact GPS ticks, raw slots and header retained; no positioning or corrections applied'])
(output/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n','utf-8',newline='\n')
print(json.dumps(dict(directory=str(output),target=a.target,separateModule=True,wholeReportMatches=True,epochs=len(result['epochs']))))
