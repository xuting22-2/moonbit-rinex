"""Independent fixed-column/Decimal oracle for the unchanged BRUX selection.

No MoonBit code or JSON values are used to derive source observations. The
pinned Rust reader supplies a second, mature-parser check of populated values.
This compares stored numbers; it does not apply corrections or assess quality.
"""
from pathlib import Path
from datetime import datetime
from decimal import Decimal
import argparse, hashlib, json

def gps_ticks(line):
    value=datetime(*(int(line[a:b]) for a,b in ((2,6),(7,9),(10,12),(13,15),(16,18))))
    delta=value-datetime(1980,1,1)
    seconds=Decimal(delta.days*86400+delta.seconds)+Decimal(line[18:29].strip())
    ticks=seconds*10_000_000
    assert ticks==ticks.to_integral_value()
    return int(ticks)

def number(text):
    value=text.strip()
    return None if not value else float(Decimal(value.replace('D','E').replace('d','e')))

def source_selection(source,start,stop):
    header=[];types={};active=None;epoch=None;selected=[];all_epochs=0;all_records=0
    with source.open('r',encoding='ascii',newline='') as handle:
        for line_no,terminated in enumerate(handle,1):
            raw=terminated.removesuffix('\n').removesuffix('\r')
            if epoch is None and (not header or header[-1][60:80].strip()!='END OF HEADER'):
                header.append(raw)
                if raw[60:80].strip()=='SYS / # / OBS TYPES':
                    if raw[0]!=' ':
                        active=raw[0];types[active]=[]
                    assert active is not None
                    types[active].extend(raw[6:60].split())
                continue
            if raw.startswith('>'):
                if epoch is not None:
                    assert len(epoch['satellites'])==count
                    if start<=int(epoch['gps_ticks'])<stop:selected.append(epoch)
                count=int(raw[32:35]);all_epochs+=1
                epoch=dict(gps_ticks=str(gps_ticks(raw)),flag=int(raw[31]),line=line_no,end_line=line_no,
                    raw_record=raw,receiver_clock=number(raw[41:56]),receiver_clock_raw=raw[41:56],satellites=[])
            else:
                assert epoch is not None
                all_records+=1
                # Derive all slots in the selected epochs, preserving physically
                # omitted trailing columns rather than pretending they existed.
                if start<=int(epoch['gps_ticks'])<stop:
                    fields=[]
                    for i,code in enumerate(types[raw[0]]):
                        at=3+16*i;field=raw[at:at+16]
                        fields.append(dict(code=code,column=at+1,raw_field=field,value=number(field[:14]),
                            lli=int(field[14]) if len(field)>14 and field[14]!=' ' else None,
                            ssi=int(field[15]) if len(field)>15 and field[15]!=' ' else None))
                    epoch['satellites'].append(dict(satellite=raw[:3],line=line_no,raw_record=raw,observations=fields))
                    epoch['end_line']=line_no
                else:
                    # Counts alone suffice outside the requested selection.
                    epoch['satellites'].append(None)
    assert epoch is not None and len(epoch['satellites'])==count
    if start<=int(epoch['gps_ticks'])<stop:selected.append(epoch)
    return header,types,selected,all_epochs,all_records

def compare(source,directory,rust=None):
    manifest=json.loads((directory/'manifest.json').read_text('utf-8'))
    assert manifest['complete'] is True
    digest=hashlib.sha256(source.read_bytes()).hexdigest()
    assert digest==manifest['input']['sha256']
    start,stop=map(int,manifest['gpsRange'])
    raw_header,types,expected,epoch_count,record_count=source_selection(source,start,stop)
    actual=[json.loads(line) for line in (directory/'epochs.ndjson').read_text('utf-8').splitlines()]
    assert actual==expected,'raw slots, values, indicators, times or source positions differ'
    header=json.loads((directory/'header.json').read_text('utf-8'))
    assert header['raw_lines']==raw_header and header['parsed']['observation_types']==types
    report=json.loads((directory/'report.json').read_text('utf-8'))
    assert report['complete'] is True and report['epochs']==epoch_count and report['records']==record_count
    values={};raw_fields={};slots=blank=lli_count=ssi_count=0
    for epoch in expected:
        for sat in epoch['satellites']:
            for field in sat['observations']:
                slots+=1;blank+=field['value'] is None;lli_count+=field['lli'] is not None;ssi_count+=field['ssi'] is not None
                if field['value'] is not None:
                    key=(int(epoch['gps_ticks']),sat['satellite'],field['code'])
                    assert key not in values
                    values[key]=(field['value'],field['lli'])
                    raw_fields[key]=field['raw_field']
    mature=None
    if rust:
        parsed={};rust_epochs=None
        for line in rust.read_text('utf-8-sig').splitlines():
            if line.startswith('epochs='):rust_epochs=int(line[7:])
            if not line.startswith('value\t'):continue
            _,stamp,sv,code,value,lli=line.split('\t')
            date=datetime.strptime(stamp,'%Y-%m-%dT%H:%M:%S GPST')
            delta=date-datetime(1980,1,1);tick=(delta.days*86400+delta.seconds)*10_000_000
            key=(tick,sv,code);assert key not in parsed
            parsed[key]=(float(value),None if lli=='absent' else int(lli))
        assert rust_epochs==len(expected)
        assert set(parsed)==set(values),'mature-parser populated observation keys differ'
        differences=[]
        for key,(value,lli) in values.items():
            if parsed[key][0]!=value:
                # Preserve the observed disagreement, rather than loosening
                # numerical tolerance or modifying the mature parser/input.
                differences.append(dict(gpsTicks=str(key[0]),satellite=key[1],code=key[2],
                    rawField=raw_fields[key],f14Text=raw_fields[key][:14],
                    productValue=value,referenceValue=parsed[key][0],lli=lli))
            if key[2].startswith('L'):assert parsed[key][1]==lli,('mature-parser phase LLI differs',key)
        assert differences==[dict(gpsTicks='14745888300000000',satellite='E25',code='L7Q',
            rawField=' 114931467.86314',f14Text=' 114931467.863',productValue=114931467.863,
            referenceValue=114931467.8631,lli=1)],'Unexpected mature-parser disagreement'
        mature=dict(reference='rinex@0.22.0',populatedValuesCompared=len(values),
            exactValueMatches=len(values)-len(differences),allNumericValuesAgree=False,
            differences=differences,phaseLliCompared=sum(k[2].startswith('L') for k in values),
            differenceExplanation='Pinned parse_sig_v3 starts numeric slice at SVNN_SIZE + 1; its 14-byte slice includes the LLI byte. Fixed-column/Decimal and MoonBit use the declared F14 field.',
            source='https://docs.rs/crate/rinex/0.22.0/source/src/observation/parsing.rs',
            outputSha256=hashlib.sha256(rust.read_bytes()).hexdigest())
    return dict(passed=True,sourceSha256=digest,wholeInputEpochs=epoch_count,wholeInputSatelliteRecords=record_count,
        selectedEpochs=len(expected),selectedSatelliteRecords=sum(len(e['satellites']) for e in expected),
        allRawSlotsCompared=slots,populatedValuesCompared=len(values),blankValuesCompared=blank,
        presentLliCompared=lli_count,presentSsiCompared=ssi_count,rawHeaderLinesCompared=len(raw_header),
        complete=True,inputAcceptable=report['acceptable'],matureReader=mature,
        limits=['stored values only; no scale, phase or receiver-clock corrections applied',
            ('Rust checked populated values and phase LLI' if mature else 'mature-parser check not run in this receipt'),
            'fixed-column oracle checked blank slots, SSI and raw positions',
            'project-authored reference adapters; no independent adoption or positioning acceptance'])

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('source',type=Path);p.add_argument('directory',type=Path)
    p.add_argument('--rust',type=Path);p.add_argument('--report',type=Path);args=p.parse_args()
    result=compare(args.source,args.directory,args.rust);text=json.dumps(result,indent=2)+'\n'
    if args.report:args.report.write_text(text,'utf-8',newline='\n')
    print(text,end='')
