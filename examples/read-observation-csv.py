"""Read a completed raw OBS table through Python csv/Decimal, without the source RNX.

This is a project-authored physical table recipient, not an independent RINEX parser
or an authentication service. It accepts no statistics before native quality,
complete CSV structure, actual streamed byte identity and totals all agree.
"""
from pathlib import Path
from decimal import Decimal, InvalidOperation
import csv, hashlib, json, os, re, sys

COLUMNS=['row_kind','epoch_index','gps_ticks','epoch_flag','source_line','satellite','observation_code','source_column','raw_field','value_text','lli','ssi','receiver_clock_raw']
LIMIT=536870912
def metadata(path):
    with path.open('rb') as f:
        raw=f.read(1048577)
    if len(raw)>1048576:raise ValueError('metadata limit')
    return json.loads(raw.decode('utf-8-sig'))
def consume_observation_csv(directory):
    directory=Path(directory);manifest=metadata(directory/'manifest.json');report=metadata(directory/'report.json');header=metadata(directory/'header.json')
    if manifest.get('schema')!='raw-observation-csv-v1' or manifest.get('complete') is not True:raise ValueError('incomplete table delivery')
    native=report['input_report']
    if native.get('complete') is not True:raise ValueError('native input incomplete')
    if manifest.get('inputAcceptable') is not native.get('acceptable'):raise ValueError('native quality mismatch')
    if native['acceptable'] is not True:
        return {'complete':False,'inputAcceptable':False,'acceptedStatistics':False,'nativeInputComplete':True,'native_report':native}
    if header['parsed']!=native['header']:raise ValueError('header/report mismatch')
    if manifest['source']!={k:header['parsed'][k] for k in ['license','doi','marker']}:raise ValueError('source context mismatch')
    expected=manifest['table']
    if expected!={k:report[k] for k in ['epochs','satellite_records','observation_rows','rows']}:raise ValueError('native table summary mismatch')
    if manifest['output']['file']!='observations.csv':raise ValueError('fixed table filename required')
    epochs=observations=records=empty_epochs=0;current=None;seen=set();groups={};first=last=None
    digest=hashlib.sha256();byte_count=line_count=0
    with (directory/'observations.csv').open('rb') as f:
        before=os.fstat(f.fileno())
        if before.st_size>LIMIT:raise ValueError('CSV byte limit')
        def lines():
            nonlocal byte_count,line_count
            for raw in f:
                byte_count+=len(raw);line_count+=1
                if byte_count>LIMIT or len(raw)>8192:raise ValueError('CSV byte/line limit')
                digest.update(raw);yield raw.decode('ascii')
        reader=csv.DictReader(lines(),strict=True)
        if reader.fieldnames!=COLUMNS:raise ValueError('CSV columns mismatch')
        for row in reader:
            if None in row or any(v is None for v in row.values()):raise ValueError('CSV width mismatch')
            index=int(row['epoch_index']);ticks=row['gps_ticks'];flag=row['epoch_flag'];source_line=int(row['source_line'])
            if not re.fullmatch(r'[0-9]{1,17}',ticks) or flag not in ['0','1'] or source_line<1:raise ValueError('invalid epoch context')
            if row['row_kind']=='epoch':
                if index!=epochs+1:raise ValueError('epoch index sequence')
                if any(row[k] for k in ['satellite','observation_code','source_column','raw_field','value_text','lli','ssi']):raise ValueError('epoch carries observation fields')
                if current is not None and not seen:empty_epochs+=1
                epochs+=1;current=(index,ticks,flag);seen=set()
                if first is None:first=ticks
                last=ticks
            elif row['row_kind']=='observation':
                if current!=(index,ticks,flag) or row['receiver_clock_raw']:raise ValueError('orphan observation context')
                sat=row['satellite'];code=row['observation_code'];column=int(row['source_column']);raw=row['raw_field'];value=row['value_text'];lli=row['lli'];ssi=row['ssi']
                if not re.fullmatch(r'[GRECJIS][0-9]{2}',sat) or not re.fullmatch(r'[CLDS][1-9][A-Z]',code):raise ValueError('invalid satellite/code cell')
                codes=header['parsed']['observation_types'].get(sat[0],[])
                if code not in codes or column!=4+16*codes.index(code):raise ValueError('source slot context mismatch')
                if (sat,code) in seen:raise ValueError('duplicate observation cell')
                if not any(a==sat for a,_ in seen):records+=1
                seen.add((sat,code));observations+=1
                if len(raw)>16 or raw[:14].strip()!=value or raw[14:15].strip()!=lli or raw[15:16].strip()!=ssi:raise ValueError('raw slot/value/flags mismatch')
                if (lli and not re.fullmatch('[0-7]',lli)) or (ssi and not re.fullmatch('[0-9]',ssi)):raise ValueError('flag cell range')
                g=groups.setdefault((sat,code),{'satellite':sat,'code':code,'rows':0,'blank_values':0,'zero_values':0,'lli_nonzero':0,'sum_stored_raw':Decimal(0)})
                g['rows']+=1
                if value:
                    numeric=Decimal(value.replace('D','E').replace('d','e'))
                    if not numeric.is_finite():raise ValueError('nonfinite numeric cell')
                    g['zero_values']+=numeric==0;g['sum_stored_raw']+=numeric
                else:g['blank_values']+=1
                g['lli_nonzero']+=bool(lli and lli!='0')
            else:raise ValueError('unknown row kind')
        after=os.fstat(f.fileno())
    if current is not None and not seen:empty_epochs+=1
    actual={'bytes':byte_count,'lines':line_count,'sha256':digest.hexdigest()}
    if actual!={k:manifest['output'][k] for k in actual}:raise ValueError('actual CSV read identity mismatch')
    if before.st_size!=after.st_size or before.st_mtime_ns!=after.st_mtime_ns or byte_count!=before.st_size:raise ValueError('CSV changed during read')
    if expected!={'epochs':epochs,'satellite_records':records,'observation_rows':observations,'rows':epochs+observations}:raise ValueError('actual row counts mismatch')
    if (epochs,records,first,last)!=(native['epochs'],native['records'],native['first'],native['last']):raise ValueError('native input/table coverage mismatch')
    result_groups=[]
    for _,group in sorted(groups.items()):group['sum_stored_raw']=str(group['sum_stored_raw']);result_groups.append(group)
    return {'complete':True,'inputAcceptable':True,'epochs':epochs,'satellite_records':records,'observation_rows':observations,'empty_epochs':empty_epochs,'first_gps_ticks':first,'last_gps_ticks':last,'groups':result_groups}

if __name__=='__main__':
    try:
        if len(sys.argv)!=2:raise ValueError('Usage: python examples/read-observation-csv.py DIRECTORY')
        result=consume_observation_csv(sys.argv[1]);print(json.dumps(result,ensure_ascii=False));sys.exit(0 if result['inputAcceptable'] else 2)
    except (OSError,ValueError,KeyError,TypeError,InvalidOperation,csv.Error) as error:
        print(json.dumps({'complete':False,'inputAcceptable':False,'error':str(error)}),file=sys.stderr);sys.exit(1)
