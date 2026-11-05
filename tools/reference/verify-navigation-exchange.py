"""Independent file recipient: fixed columns, Decimal, datetime, hashlib.

Does not import MoonBit, JS, generated layouts or its expected output. Checks
every physical numeric/text slot, calendar, source span, file and count identity.
All expectations come from original source bytes and the RINEX table positions.
"""
from pathlib import Path
from decimal import Decimal
from datetime import datetime,timedelta
from collections import Counter
import hashlib,json,sys

def sha(b):return hashlib.sha256(b).hexdigest()
def verify(source,directory):
    root=Path(directory);original=Path(source).read_bytes();lines=original.decode('ascii').splitlines()
    manifest=json.loads((root/'manifest.json').read_text())
    assert manifest['complete'] is True
    assert manifest['input']['sha256']==sha(original)
    h=next(i+1 for i,s in enumerate(lines) if s[60:80].strip()=='END OF HEADER')
    version=lines[0][:9].strip();r4=version.startswith('4')
    assert manifest['headerLines']==lines[:h]
    exchanged=(root/'navigation.rnx').read_bytes();assert exchanged==('\n'.join(lines)+'\n').encode('ascii')
    for key,name in [('rnx','navigation.rnx'),('ndjson','messages.ndjson')]:
        b=(root/name).read_bytes();assert manifest['output'][key]['sha256']==sha(b);assert manifest['output'][key]['bytes']==len(b)
    if r4:
        offsets=[i for i in range(h,len(lines)) if lines[i].startswith('>')]+[len(lines)]
        blocks=[(a,b,lines[a:b]) for a,b in zip(offsets,offsets[1:])]
    else:
        blocks=[];a=h
        while a<len(lines):
            sysid=lines[a][0];n=5 if sysid=='R' and version=='3.05' else 4 if sysid in 'RS' else 8
            blocks.append((a,a+n,lines[a:a+n]));a+=n
        assert a==len(lines)
    nfields=0;counts=Counter();opaque=0
    with (root/'messages.ndjson').open(encoding='utf-8') as stream:
        for a,b,raw in blocks:
            row=stream.readline();assert row,'missing received record';m=json.loads(row)
            assert m['version']==version
            assert m['first_line']==a+1 and m['last_line']==b
            assert m['raw_lines']==raw
            if r4:
                d=raw[0].split();category,satellite,family=d[1:4];subtype=d[4] if len(d)>4 else ''
                assert (m['category'],m['satellite'],m['family'],m['subtype'])==(category,satellite,family,subtype)
                payload=raw[1:]
            else:
                category='EPH';satellite=raw[0][:3];sysid=satellite[0];subtype='';payload=raw
                if sysid=='E':
                    bits=int(Decimal(raw[5][23:42].replace('D','E')))
                    family='FNAV' if bits&2 and not bits&5 else 'INAV' if bits&5 and not bits&2 else 'IFNV'
                else:family={'G':'LNAV','R':'FDMA','C':'D1D2','J':'LNAV','S':'SBAS','I':'LNAV'}[sysid]
                assert (m['category'],m['satellite'],m['family'])==(category,satellite,family)
            assert m['system']==satellite[0]
            key=' '.join([category,satellite[0],family]+([subtype] if subtype else []));counts[key]+=1
            if not m['known']:
                assert not m['fields'];opaque+=1;continue
            first=payload[0];calendar=first[4:23];assert m['epoch']['calendar']==calendar
            parts=list(map(int,calendar.split()));leap=parts[-1]==60
            if leap:parts[-1]=59
            date=datetime(*parts)+(timedelta(seconds=1) if leap else timedelta())
            delta=date-datetime(1980,1,1);ticks=(delta.days*86400+delta.seconds)*10_000_000
            assert int(m['epoch']['calendar_ticks'])==ticks
            assert m['epoch']['leap_second']==leap
            scale={'G':'GPST','R':'UTC','E':'GST','C':'BDT','J':'QZSST','I':'IRNSST','S':'GPST'}[satellite[0]]
            if category=='STO':
                codes=first[23:42].strip();assert m['texts']['correction_type']==codes
                assert m['texts']['sbas_id']==first[42:61].strip()
                assert m['texts']['utc_id']==first[61:80].strip()
                scale={'GP':'GPST','GL':'UTC','GA':'GST','BD':'BDT','QZ':'QZSST','IR':'IRNSST','SB':'GPST','UT':'UTC'}[codes[:2]]
            assert m['epoch']['scale']==scale
            slots={}
            for r,s in enumerate(payload):
                if category=='STO' and r==0:continue
                start=23 if r==0 else 4;n=3 if r==0 else 4
                for c in range(n):slots[(r,c)]=s[start+c*19:start+(c+1)*19]
            assert len(slots)==len(m['fields'])
            names=set()
            for f in m['fields']:
                pos=(f['row'],f['column']);text=slots.pop(pos);assert f['raw']==text
                assert f['name'] not in names;names.add(f['name']);nfields+=1
                if not text.strip() or f['name'].startswith('spare_'):
                    assert f.get('value') is None;continue
                expected=Decimal(text.replace('D','E').replace('d','e'));actual=Decimal(str(f['value']))
                assert expected.is_finite() and actual.is_finite()
                assert abs(actual-expected)<=max(abs(expected)*Decimal('2e-15'),Decimal('1e-300')),(key,f['name'],actual,expected)
            assert not slots
            # Semantic anchors are separate from the physical-slot check.
            anchors={}
            if category=='EPH' and satellite[0]=='R':
                anchors={'clock_bias':(0,0,'s'),'clock_drift':(0,1,'s/s'),'x':(1,0,'km'),'vx':(1,1,'km/s'),'ax':(1,2,'km/s2'),'health':(1,3,'bits'),'y':(2,0,'km'),'z':(3,0,'km')}
                if family=='FDMA':anchors.update({'frequency_channel':(2,3,'integer'),'frame_time':(0,2,'s')})
                else:anchors.update({'clock_drift_rate':(0,2,'s/s2'),'data_validity':(2,3,'bits'),('tgd_l2ocp' if family=='L1OC' else 'isc_l3ocp'):(3,3,'s'),'transmission_time':(8,3,'s')})
            elif category=='EPH' and satellite[0] in 'GECJI' and family!='SBAS':
                anchors={'clock_bias':(0,0,'s'),'clock_drift':(0,1,'s/s'),'clock_drift_rate':(0,2,'s/s2'),'crs':(1,1,'m'),'delta_n':(1,2,'rad/s'),'m0':(1,3,'rad'),'eccentricity':(2,1,'1'),'sqrt_a':(2,3,'sqrt(m)'),'omega0':(3,2,'rad'),'i0':(4,0,'rad'),'omega_dot':(4,3,'rad/s'),'idot':(5,0,'rad/s')}
                if family in ['CNAV','CNV1','CNV2','CNV3','L1NV']:anchors.update({'a_dot':(1,0,'m/s'),'delta_n_dot':(5,1,'rad/s2')})
                if satellite[0]=='E':anchors.update({'data_sources':(5,1,'bits'),'week':(5,2,'week'),'sisa':(6,0,'m'),'health':(6,1,'bits'),'bgd_e5a_e1':(6,2,'s'),'bgd_e5b_e1':(6,3,'s')})
            elif category=='STO':anchors={'transmission_time':(1,0,'s'),'a0':(1,1,'s'),'a1':(1,2,'s/s'),'a2':(1,3,'s/s2')}
            elif category=='EOP':anchors={'xp':(0,0,'arcsec'),'xp_rate':(0,1,'arcsec/day'),'xp_accel':(0,2,'arcsec/day2'),'yp':(1,1,'arcsec'),'delta_ut1':(2,1,'s')}
            elif category=='ION' and satellite[0]=='E':anchors={'ai0':(0,0,'sfu'),'ai1':(0,1,'sfu/deg'),'ai2':(0,2,'sfu/deg2'),'disturbance_flags':(1,0,'bits')}
            byname={f['name']:f for f in m['fields']}
            for name,(r,c,unit) in anchors.items():
                f=byname[name];assert (f['row'],f['column'],f['unit'])==(r,c,unit),(key,name,f)
        assert not stream.readline(),'extra received record'
    assert len(blocks)==manifest['records'];assert dict(counts)==manifest['counts']
    assert opaque==manifest['unsupportedRecords'];assert manifest['allSupported']==(opaque==0)
    return {'status':'independent_navigation_recipient_passed','records':len(blocks),'fields':nfields,'opaqueRecords':opaque,'inputSha256':sha(original),'outputSha256':sha(exchanged),'version':version,'counts':dict(counts)}

if __name__=='__main__':
    if len(sys.argv)!=3:raise SystemExit('Usage: verify-navigation-exchange.py ORIGINAL.rnx EXCHANGE_DIRECTORY')
    print(json.dumps(verify(*sys.argv[1:]),sort_keys=True))
