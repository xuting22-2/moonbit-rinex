"""Compare the unchanged public CEDA fixture with GeoRinex 1.16.2 and MoonBit.

Run after `moon build --target js --release`; takes an uncompressed input path.
This is a fixed independent reference gate, not a second RINEX implementation.
"""
from pathlib import Path
import argparse,datetime,hashlib,importlib.metadata,json,platform,subprocess,time,warnings
import georinex as gr
import numpy as np

INPUT_SHA256='2563103ee2803a16f81c068658b6c7a210dd379f53327ff79b7de29afb034ee9'
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def check(ok,description):
    if not ok:raise AssertionError(description)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input',type=Path);parser.add_argument('--evidence',type=Path,required=True)
    args=parser.parse_args();repo=Path(__file__).resolve().parents[1]
    check(importlib.metadata.version('georinex')=='1.16.2','Use pinned GeoRinex 1.16.2')
    check(sha(args.input)==INPUT_SHA256,'Input must be the unmodified CEDA public fixture')
    started=time.monotonic()
    proc=subprocess.run(['node',str(repo/'tools/check-file.mjs'),str(args.input.resolve())],capture_output=True,check=False)
    check(proc.returncode==2,'CEDA has interval findings and must exit 2')
    moon=json.loads(proc.stdout);check(moon['complete'] and not moon['acceptable'],'Completed with findings')
    check(moon['input']['sha256']==INPUT_SHA256,'Both readers must receive the same bytes')
    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter('once',FutureWarning)
        obs=gr.load(args.input,useindicators=True)
    times=obs.time.values.astype('datetime64[ns]')
    ticks=(times-np.datetime64('1980-01-01','ns')).astype('timedelta64[ns]').astype(np.int64)//100
    check(len(times)==moon['epochs'],'Epoch count')
    check(str(ticks[0])==moon['first'] and str(ticks[-1])==moon['last'],'GPS calendar first/last ticks')
    interval_findings=int(np.count_nonzero(np.diff(ticks)!=int(moon['header']['interval'])))
    check(interval_findings==moon['finding_counts'].get('epoch-interval',0),'Every adjacent interval finding')
    svs=obs.sv.values.tolist();rows=[];lli_unavailable=[]
    for system in moon['systems']:
        key=system['system'];ids=[sv for sv in svs if sv.startswith(key)]
        check(ids==system['satellites'],key+' satellite IDs')
        for signal in system['signals']:
            code=signal['code'];values=obs[code].sel(sv=ids).values
            nonempty=int(np.count_nonzero(np.isfinite(values)));zero=int(np.count_nonzero(values==0))
            check(nonempty==signal['nonempty_fields'],key+':'+code+' nonempty')
            check(zero==signal['zero_values'],key+':'+code+' numeric zeros')
            row={'system':key,'code':code,'nonempty':nonempty,'zero':zero}
            # This reference exposes LLI only for L1/L2. Missing LLI arrays
            # are a reference limitation, never converted into invented zeros.
            if code.startswith('L'):
                if code+'lli' not in obs:lli_unavailable.append(key+':'+code)
                else:
                    values=obs[code+'lli'].sel(sv=ids).values
                    lli=np.where(np.isfinite(values),values,0).astype(np.int64)
                    row['lliNonzero']=int(np.count_nonzero(lli))
                    check(row['lliNonzero']==signal['lli_nonzero'],key+':'+code+' LLI nonzero')
                    for bit in range(3):
                        count=int(np.count_nonzero(lli&(1<<bit)));row['lliBit'+str(bit)]=count
                        check(count==signal['lli_bit'+str(bit)],key+':'+code+' LLI bit '+str(bit))
            rows.append(row)
    sources=['types.mbt','time.mbt','header.mbt','checker.mbt','cmd/bridge/main.mbt','tools/check-file.mjs','tools/compare-georinex.py','pkg.generated.mbti']
    report={'date':datetime.datetime.now(datetime.timezone.utc).isoformat(),'passed':True,
        'input':{'name':args.input.name,'sha256':INPUT_SHA256,'bytes':args.input.stat().st_size},
        'reference':{'project':'https://github.com/geospace-code/georinex','version':'1.16.2',
          'python':platform.python_version(),'dependencies':{x:importlib.metadata.version(x) for x in ['numpy','pandas','xarray','georinex']},
          'sourceSha256':{x:sha(Path(gr.__file__).parent/x) for x in ['base.py','obs3.py','rio.py']}},
        'epochs':len(times),'satellites':len(svs),'systemSignalsCompared':len(rows),
        'nonemptyValuesCompared':sum(r['nonempty'] for r in rows),'numericZerosCompared':sum(r['zero'] for r in rows),
        'intervalFindingsCompared':interval_findings,'lliSignalsCompared':sum('lliNonzero' in r for r in rows),
        'lliNotExposedByReference':lli_unavailable,'rows':rows,
        'moonbitExitCode':proc.returncode,'moonbitFindings':moon['finding_counts'],
        'sourceHashPolicy':'LF-normalized UTF8','sourceSha256':{s:hashlib.sha256((repo/s).read_bytes().replace(b'\r\n',b'\n')).hexdigest() for s in sources},
        'elapsedSeconds':round(time.monotonic()-started,3),'referenceWarnings':sorted(set(str(w.message) for w in caught)),
        'limits':['CEDA upstream test fixture, not an entire claimed daily production observation set',
          'Dataset NaN cannot distinguish absent satellite rows from all-blank records; raw row/blank-slot counts are not independently proved here',
          'GeoRinex 1.16.2 rejects BRUX RINEX 4.01; this new check does not replace the prior BRUX reference',
          'Reference does not expose LLI outside L1/L2; those counters remain outside this comparison',
          'Times are GPS calendar labels, not a UTC conversion; no physical observation/positioning validation']}
    args.evidence.parent.mkdir(parents=True,exist_ok=True)
    args.evidence.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:report[k] for k in ['passed','epochs','satellites','systemSignalsCompared','nonemptyValuesCompared','intervalFindingsCompared','lliSignalsCompared','elapsedSeconds']}))

if __name__=='__main__':main()
