import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
import {extractObservations} from '../tools/extract-observations.mjs';
import {queryNavigationBatch} from '../tools/nav-query.mjs';

const directory=process.argv[2];
if(!directory)throw Error('Usage: node examples/obs-tick-query.mjs NEW_EXTRACTION_DIRECTORY');
const obs=fileURLToPath(new URL('./obs-query-time.rnx',import.meta.url));
const nav=fileURLToPath(new URL('./catalog-synthetic.nav',import.meta.url));
const manifest=await extractObservations(obs,directory);
if(!manifest.complete||!manifest.inputAcceptable)throw Error('observation input must finish and be acceptable before this example queries navigation');
const epochFile=path.join(directory,'epochs.ndjson');
if((await fs.stat(epochFile)).size>1048576)throw Error('fixed example epoch output exceeds 1MiB');
const epochs=(await fs.readFile(epochFile,'utf8')).trim().split('\n').map(line=>JSON.parse(line));
assert.equal(epochs.length,1);
const epoch=epochs[0];
const requests=epoch.satellites.map(({satellite})=>({satellite,gps_ticks:epoch.gps_ticks}));
const batch=await queryNavigationBatch(nav,requests);
assert.equal(epoch.gps_ticks,'14774005000000000');
assert.equal(batch.results[0].result.selection.record.record_index,1);
assert.equal(batch.results[0].result.selection.report.at.gps_ticks,epoch.gps_ticks);
console.log(JSON.stringify({observation:{complete:manifest.complete,inputAcceptable:manifest.inputAcceptable,
  source:manifest.source,gps_ticks:epoch.gps_ticks},...batch}));
