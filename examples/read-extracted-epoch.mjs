import assert from 'node:assert/strict';
import {readExtractedEpoch} from '../tools/extracted-epoch.mjs';

if(process.argv.length!==3)throw Error('Usage: node examples/read-extracted-epoch.mjs DIRECTORY_FROM_obs-raw-values.rnx');
const {observation,epoch}=await readExtractedEpoch(process.argv[2],1);
const gps=epoch.satellites.find(item=>item.satellite==='G01');
assert.equal(epoch.gps_ticks,'14773968000000001');
assert.deepEqual(epoch.satellites.map(item=>item.satellite),['G01','C06','E25']);
assert.deepEqual(gps.observations.map(item=>item.value),[0,-123.25,null]);
assert.equal(epoch.satellites[2].observations[0].raw_field,'');
console.log(JSON.stringify({complete:observation.complete,inputAcceptable:observation.inputAcceptable,
  gps_ticks:epoch.gps_ticks,observed_satellites:epoch.satellites.map(item=>item.satellite),
  gps_slots:gps.observations.map(({code,value,lli,ssi})=>({code,value,lli,ssi}))}));
