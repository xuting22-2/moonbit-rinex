import assert from 'node:assert/strict';
import {readExtractedEpochs} from '../tools/extracted-epoch.mjs';

const directory=process.argv[2];
if(!directory)throw Error('Usage: node examples/read-extracted-epochs.mjs EXTRACTED_SERIES_DIRECTORY');
const output=await readExtractedEpochs(directory,2,2);
assert.deepEqual(output.epochs.map(epoch=>epoch.gps_ticks),['14773968300000001','14773968600000001']);
assert.deepEqual(output.observation.selected_epochs.map(epoch=>epoch.index),[2,3]);
const value=output.epochs[0].satellites[0].observations[0];
assert.equal(value.raw_field,'         0.00015');
assert.equal(value.value,0);assert.equal(value.lli,1);assert.equal(value.ssi,5);
assert.equal(output.epochs[1].flag,1);assert.deepEqual(output.epochs[1].satellites,[]);
assert(output.observation.native_report.findings.some(item=>item.code==='empty-epoch'&&!item.error));
assert.equal(output.observation.complete,true);assert.equal(output.observation.inputAcceptable,true);
console.log(JSON.stringify(output));
