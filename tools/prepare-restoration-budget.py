from pathlib import Path
from datetime import datetime,timedelta
import json,sys,hashlib

root=Path(__file__).resolve().parents[1]
reference=json.loads((root/'examples/restoration/REFERENCE.json').read_text())
budget=reference['budget'];hand=reference['hand']['modern']['expectedRinexLines']
def label(content,name):return content.ljust(60)+name
codes=budget['types'];sats=budget['satellites']
header=[label('     3.04           OBSERVATION DATA    G','RINEX VERSION / TYPE'),label('SYNTHETIC OUTPUT BUDGET','MARKER NAME'),label('MIT','LICENSE OF USE')]
for at in range(0,len(codes),13):
    prefix='G  '+f'{len(codes):3d}'+' ' if at==0 else '       '
    header.append(label(prefix+' '.join(codes[at:at+13]),'SYS / # / OBS TYPES'))
header += [hand[4],label('    30.000','INTERVAL'),label('','END OF HEADER')]
initial=[label('3.0                 COMPACT RINEX FORMAT','CRINEX VERS   / TYPE'),label('PROJECT AUTHORED BUDGET PATTERN','CRINEX PROG / DATE')]+header
digest=hashlib.sha256();size=0
with Path(sys.argv[1]).open('xb') as file:
    def emit(line):
        global size
        raw=(line+'\n').encode('ascii');file.write(raw);digest.update(raw);size+=len(raw)
    for line in initial:emit(line)
    for i in range(budget['epochs']):
        at=datetime(2026,10,29)+timedelta(seconds=30*i)
        emit(f'> {at:%Y %m %d %H %M} {at.second:2d}.0000001  0{len(sats):3d}'+'      '+''.join(sats));emit('')
        for _ in sats:emit(' '*(len(codes)-1)+'0&0 &&')
assert size==budget['input']['bytes'] and digest.hexdigest()==budget['input']['sha256']
print(json.dumps(dict(bytes=size,sha256=digest.hexdigest(),independentRecipe=True)))
