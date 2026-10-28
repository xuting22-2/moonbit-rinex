import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {queryNavigation,queryNavigationBatch} from './nav-query.mjs';
import * as api from '../_build/js/release/build/cmd/bridge/bridge.js';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const input=path.join(root,'examples/catalog-synthetic.nav');
const refs=JSON.parse(await fs.readFile(path.join(root,'examples/CATALOG-REFERENCE.json'),'utf8'));
const gps={satellite:'G01',gps_ticks:'14774005000000000'};
const geo={satellite:'C01',gps_ticks:'14773536140000000'};
const legacy={satellite:'C01',week:1086,sow:0,bdt:true};
const buildRoot=await fs.realpath(path.join(root,'_build'));
const directory=await fs.mkdtemp(path.join(buildRoot,'tick-query-host-'));
let cliCases=0,summary;
function compare(selection,reference){
  assert.equal(selection.record.record_index,reference.expectedRecordIndex);
  assert.equal(selection.record.source_line,4+(reference.expectedRecordIndex-1)*8);
  for(const axis of ['x','y','z'])assert(Math.abs(selection.state[axis]-reference[axis])<=1e-5);
  assert(Math.abs(selection.state.clock_seconds-reference.clock_seconds)<=1e-13);
}
async function requestFile(name,value){const file=path.join(directory,name+'.json');await fs.writeFile(file,JSON.stringify(value));return file;}
function run(file){
  const proc=spawnSync(process.execPath,[path.join(root,'tools/nav-query-batch.mjs'),input,file],{encoding:'utf8',timeout:20000});
  assert.ifError(proc.error);cliCases++;
  return {code:proc.status,stdout:proc.stdout,receipt:JSON.parse(proc.stderr),result:proc.stdout?JSON.parse(proc.stdout):null};
}
try {
  const batch=await queryNavigationBatch(input,[gps,legacy,geo,{satellite:'G99',week:2442,sow:46900}]);
  assert.deepEqual(batch.results.map(item=>item.result.status),['selected','selected','selected','unavailable']);
  assert.equal(batch.receipt.queries,4);assert.equal(batch.receipt.selected,3);assert.equal(batch.receipt.unavailable,1);
  const gpsRef=refs.find(item=>item.satellite==='G01'&&item.sow===46900);
  const geoRef=refs.find(item=>item.satellite==='C01'&&item.bdt===true&&item.sow===0);
  compare(batch.results[0].result.selection,gpsRef);compare(batch.results[1].result.selection,geoRef);compare(batch.results[2].result.selection,geoRef);
  assert.equal(batch.results[0].result.selection.report.at.gps_ticks,gps.gps_ticks);
  assert.equal(batch.results[2].result.selection.report.at.gps_ticks,geo.gps_ticks);
  const oldPoint=await queryNavigation(input,legacy);
  assert.deepEqual(oldPoint.result,batch.results[2].result);
  await assert.rejects(queryNavigationBatch(path.join(directory,'absent.nav'),[geo,{...gps,gps_ticks:14774005000000000}]),/query 2:.*requires a string/);
  for(const field of ['week','sow','bdt']){
    const value=field==='bdt'?false:0;
    await assert.rejects(queryNavigationBatch(path.join(directory,'absent.nav'),[{...gps,[field]:value}]),/cannot be combined/);
  }
  const authored=run(path.join(root,'examples/catalog-gps-ticks-queries.json'));
  assert.equal(authored.code,2);assert.equal(authored.receipt.queries,3);assert.equal(authored.receipt.selected,2);assert.equal(authored.receipt.unavailable,1);
  for(const [name,value,pattern] of [
    ['number',[geo,{...gps,gps_ticks:14774005000000000}],/query 2:.*requires a string/],
    ['mixed',[geo,{...gps,bdt:false}],/query 2:.*cannot be combined/],
    ['decimal',[geo,{...gps,gps_ticks:'1e16'}],/query 2:.*decimal strings/],
  ]){
    const result=run(await requestFile(name,value));
    assert.equal(result.code,1);assert.equal(result.stdout,'');assert.equal(result.receipt.complete,false);assert.match(result.receipt.error,pattern);
  }
  const session=api.nav_catalog_create(6,false);
  for(const row of (await fs.readFile(input,'utf8')).trimEnd().split('\n'))api.nav_catalog_feed(session,row);
  api.nav_catalog_finish(session);
  const normalized={...gps,orbit:0,maxAge:7200};
  assert.throws(()=>api.nav_catalog_query_batch(session,JSON.stringify([{...normalized,week:2442}])),/cannot be combined/);
  assert.throws(()=>api.nav_catalog_query_batch(session,JSON.stringify([{...normalized,gps_ticks:14774005000000000}])),/must be decimal strings/);
  const native=JSON.parse(api.nav_catalog_query_batch(session,JSON.stringify([normalized])));
  assert.equal(native.summary.selected,1);assert.equal(native.results[0].result.selection.report.at.gps_ticks,gps.gps_ticks);
  summary={status:'passed',cliCases,mixedApiBatchRequests:4,coupledLegacyPointCases:1,hostPreflightRejections:4,
    nativeRepresentationGateGroups:2,referenceStateComparisons:3,distinctIndependentStates:2,
    oldWeekFormPreserved:true,exactGpsCoordinatePreserved:true,noPartialResultOnInvalidTick:true};
} finally {
  const actual=await fs.realpath(directory),relative=path.relative(buildRoot,actual);
  assert(relative&&!path.isAbsolute(relative)&&relative!=='..'&&!relative.startsWith('..'+path.sep));
  await fs.rm(actual,{recursive:true,force:true});
}
console.log(JSON.stringify(summary));
