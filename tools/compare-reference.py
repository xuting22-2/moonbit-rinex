from pathlib import Path
import argparse,json
p=argparse.ArgumentParser();p.add_argument('moonbit',type=Path);p.add_argument('reference',type=Path);p.add_argument('--report',type=Path);a=p.parse_args()
x=json.loads(a.moonbit.read_text(encoding='utf-8'));y=json.loads(a.reference.read_text(encoding='utf-8'));body=y['body']
assert x['complete'] and not x['acceptable']
assert x['input']['sha256']==y['input']['sha256']
assert x['epochs']==body['normal_observation_epoch_count']==2880
assert x['records']==body['satellite_observation_record_count']==136993
assert x['power_failure_epochs']==body['power_failure_epoch_count']==0
assert x['missing_epoch_slots']==0 and body['gap_seconds_histogram']=={'30':2879}
assert x['header']['observation_types']=={k:v['types'] for k,v in y['header']['obs_types_by_system'].items()}
assert x['finding_counts']=={'header-satellite-total':1,'header-prn-details':1}
assert sum(len(s['satellites']) for s in x['systems'])==body['unique_sv_count']==127
fields=nonempty=blank=zero=0
for system in x['systems']:
 key=system['system'];ref=body['systems'][key]
 assert system['records']==body['satellite_observation_records_by_system'][key]
 assert system['satellites']==sorted(body['unique_sv_ids_by_system'][key])
 assert sum(v['zero_values'] for v in system['signals'])==ref['zero_numeric_fields']
 for signal in system['signals']:
  code=signal['code'];expected=ref['observation_values_by_type'][code]
  assert signal['nonempty_fields']==expected.get('nonempty_fields',0),(key,code,'nonempty')
  assert signal['blank_fields']==expected.get('blank_fields',0),(key,code,'blank')
  # The independent reference names this raw numerical-zero count separately.
  assert signal['zero_values']>=0
  lli=ref['lli_by_phase_type'].get(code,{})
  assert signal['lli_nonzero']==sum(n for k,n in lli.items() if k not in ('blank','0')),(key,code,'lli')
  bits=ref['lli_bits_by_phase_type'].get(code,{})
  for i in range(3):assert signal['lli_bit'+str(i)]==sum(n for k,n in bits.items() if k.startswith('bit'+str(i)+'_')),(key,code,i)
  fields+=signal['nonempty_fields']+signal['blank_fields'];nonempty+=signal['nonempty_fields'];blank+=signal['blank_fields'];zero+=signal['zero_values']
result=dict(complete=True,sourceSha256=x['input']['sha256'],epochs=x['epochs'],satelliteRecords=x['records'],signalSlots=fields,nonemptyFields=nonempty,blankFields=blank,zeroValues=zero,knownFailure='header 131 vs observed 127 satellites',reference='independent Python fixed-field/Decimal counter; not GeoRust or gnss-js',limits='slot statistics, not physical observation availability or positioning quality')
if a.report:a.report.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
print(json.dumps(result))
