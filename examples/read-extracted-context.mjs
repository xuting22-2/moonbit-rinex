import assert from 'node:assert/strict';
import {readExtractedEpoch} from '../tools/extracted-epoch.mjs';

if(process.argv.length!==3)throw Error('Usage: node examples/read-extracted-context.mjs DIRECTORY_FROM_obs-header-context.rnx');
const {observation,epoch,header}=await readExtractedEpoch(process.argv[2],1,{includeHeader:true});
const values=epoch.satellites[0].observations.map(item=>item.value);
assert.equal(header.parsed.marker,'SYNTHETIC HEADER CONTEXT');
assert.deepEqual(values,[1000,200]);
console.log(JSON.stringify({complete:observation.complete,inputAcceptable:observation.inputAcceptable,
  gps_ticks:epoch.gps_ticks,observation_types:header.parsed.observation_types,
  raw_header:header.raw_lines,stored_values:values}));
