import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
import {queryNavigationBatch} from './nav-query.mjs';
import * as api from '../_build/js/release/build/cmd/bridge/bridge.js';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const input=path.join(root,'examples/catalog-synthetic.nav'),raw=await fs.readFile(input);
const refs=JSON.parse(await fs.readFile(path.join(root,'examples/CATALOG-REFERENCE.json'),'utf8')).reverse();
const rows=raw.toString('ascii').trimEnd().split('\n'),header=rows.slice(0,3);
const records=Array.from({length:5},(_,index)=>rows.slice(3+index*8,11+index*8));
const buildRoot=await fs.realpath(path.join(root,'_build'));
const directory=await fs.mkdtemp(path.join(buildRoot,'batch-host-'));
const digest=value=>createHash('sha256').update(value).digest('hex');
let cliCases=0,apiCases=0,summary;
const query={satellite:'G01',week:2442,sow:50500};
async function fixture(name,value){const file=path.join(directory,name);await fs.writeFile(file,value);return file;}
async function queries(name,value){return fixture(name+'.json',JSON.stringify(value));}
function run(nav,requests,flags=[]){
  const proc=spawnSync(process.execPath,[path.join(root,'tools/nav-query-batch.mjs'),nav,requests,...flags],{cwd:root,encoding:'utf8',timeout:20000});
  assert.ifError(proc.error);cliCases++;
  return {code:proc.status,stdout:proc.stdout,receipt:JSON.parse(proc.stderr),result:proc.stdout?JSON.parse(proc.stdout):null};
}
function failed(actual,pattern){
  assert.equal(actual.code,1);assert.equal(actual.stdout,'');assert.equal(actual.receipt.complete,false);assert.match(actual.receipt.error,pattern);
}
async function observed(action,onOpen=()=>{}){
  const original=fs.open;let opens=0;
  fs.open=async function(file,...args){if(path.resolve(file)===input){opens++;onOpen();}return original.call(this,file,...args);};
  try {const value=await action();assert.equal(opens,1);return value;}finally{fs.open=original;}
}
try {
  const requests=refs.map(ref=>({satellite:ref.satellite,week:ref.week,sow:ref.sow,bdt:!!ref.bdt,orbit:ref.bdsOrbit?2:0}));
  const batch=await observed(()=>queryNavigationBatch(input,requests));apiCases++;
  assert.equal(batch.receipt.queries,8);assert.equal(batch.receipt.selected,8);
  assert.equal(batch.receipt.bytes,raw.length);assert.equal(batch.receipt.lines,43);assert.equal(batch.receipt.stored_records,5);
  for(let index=0;index<refs.length;index++){
    const entry=batch.results[index],ref=refs[index],selected=entry.result.selection;
    assert.equal(entry.query_index,index+1);assert.equal(entry.result.status,'selected');
    assert.equal(selected.record.record_index,ref.expectedRecordIndex);assert.equal(selected.record.source_line,4+(ref.expectedRecordIndex-1)*8);
    for(const axis of ['x','y','z'])assert(Math.abs(selected.state[axis]-ref[axis])<=1e-5);
    assert(Math.abs(selected.state.clock_seconds-ref.clock_seconds)<=1e-13);
  }
  const mutable=[{...query}];
  const snapshot=await observed(()=>queryNavigationBatch(input,mutable),()=>{mutable[0].satellite='G99';mutable.push({...query});});apiCases++;
  assert.equal(snapshot.results.length,1);assert.equal(snapshot.results[0].result.selection.record.record_index,3);
  const maximum=await queryNavigationBatch(input,Array.from({length:256},()=>({...query,satellite:'G99'})));apiCases++;
  assert.equal(maximum.results.length,256);assert.equal(maximum.receipt.unavailable,256);assert.equal(maximum.results[255].query_index,256);
  const session=api.nav_catalog_create(6,false);
  assert.throws(()=>api.nav_catalog_query_batch(session,'[]'),/successfully finished/);
  for(const row of rows)api.nav_catalog_feed(session,row);
  api.nav_catalog_finish(session);
  const normalized={...query,bdt:false,orbit:0,maxAge:7200};
  for(const value of [[],Array(257).fill(normalized)])assert.throws(()=>api.nav_catalog_query_batch(session,JSON.stringify(value)),/1\.\.256/);
  assert.throws(()=>api.nav_catalog_query_batch(session,JSON.stringify([normalized,{...normalized,week:4294969738}])),/query 2:.*out of range/);
  const native=JSON.parse(api.nav_catalog_query_batch(session,JSON.stringify([normalized])));
  assert.equal(native.summary.selected,1);assert.equal(native.summary.all_selected,true);
  for(const [value,pattern] of [[[],/1\.\.256/],[Array(257).fill(query),/1\.\.256/],[{},/1\.\.256/],
    [[query,undefined],/query 2: query object/],[[{...query,skip:true}],/unknown query field skip/],
    [[{...query,week:Infinity}],/argument types/],[[{...query,bdt:'true'}],/argument types/]]){
    await assert.rejects(queryNavigationBatch(path.join(directory,'absent.nav'),value),pattern);apiCases++;
  }
  const authored=run(input,path.join(root,'examples/catalog-queries.json'));
  assert.equal(authored.code,2);assert.deepEqual(authored.result.results.map(item=>item.result.status),['selected','selected','unavailable','unavailable']);
  assert.equal(authored.receipt.selected,2);assert.equal(authored.receipt.unavailable,2);assert.equal(authored.stdout.trim().split('\n').length,1);
  const valid=await queries('valid',[query]);
  const selected=run(input,valid);assert.equal(selected.code,0);assert.equal(selected.receipt.selected,1);
  const changed=records[0].slice();changed[0]=changed[0].slice(0,23)+' 1.200000000000E-04'+changed[0].slice(42);
  const conflict=await fixture('conflict.nav',header.concat(records[0],changed,records[4]).join('\n')+'\n');
  const mixed=await queries('mixed',[{...query,satellite:'G99'},{...query,sow:46800},{satellite:'C06',week:1086,sow:0,bdt:true,orbit:2}]);
  const tied=run(conflict,mixed);assert.equal(tied.code,2);
  assert.deepEqual(tied.result.results.map(item=>item.result.status),['unavailable','ambiguous','selected']);
  assert.equal(tied.result.results[1].result.conflict.tied_records,2);assert.equal(tied.receipt.ambiguous,1);assert.equal(tied.receipt.selected,1);
  failed(run(input,await queries('late-native-error',[query,{...query,week:7001}]),[]),/query 2:.*out of range/);
  failed(run(input,await queries('late-type-error',[query,{...query,week:'2442'}])),/query 2:.*argument types/);
  failed(run(input,valid,['--capacity','2']),/CatalogCapacityExceeded/);
  const truncated=await fixture('truncated.nav',rows.slice(0,-1).join('\n')+'\n');failed(run(truncated,valid),/truncated/);
  const number=' 0.000000000000E+00';
  const opaque=['R01 2026 10 25 00 00 00'+number.repeat(3),...Array.from({length:4},()=> '    '+number.repeat(4))];
  const unsupported=await fixture('unsupported.nav',header.concat(opaque,...records).join('\n')+'\n');
  failed(run(unsupported,valid),/UnsupportedConstellation/);
  const skipped=run(unsupported,valid,['--skip-unsupported']);assert.equal(skipped.code,0);assert.equal(skipped.receipt.skipped_unsupported,1);
  assert.equal(skipped.result.results[0].result.selection.record.source_line,25);
  failed(run(input,await fixture('malformed.json','[')),/JSON/);
  // Both sides are the same valid request plus legal JSON whitespace. A size
  // rejection must not be explained by malformed JSON, including with a BOM.
  const boundaryRef=refs.find(ref=>ref.case==='gps-fallback'),byteBoundary=[];
  assert(boundaryRef);
  assert.equal(boundaryRef.satellite,query.satellite);assert.equal(boundaryRef.week,query.week);
  assert.equal(boundaryRef.sow,query.sow);assert.equal(boundaryRef.expectedRecordIndex,3);
  assert.equal(rows[19].slice(0,3),'G01');
  const byteLimit=1048576,payload=Buffer.from(JSON.stringify([query]),'utf8');
  for(const [encoding,bomBytes] of [['plain',Buffer.alloc(0)],['bom',Buffer.from([239,187,191])]]){
    const prefix=Buffer.concat([bomBytes,payload]);
    const exact=Buffer.concat([prefix,Buffer.alloc(byteLimit-prefix.length,' \t\r\n')]);
    const over=Buffer.concat([exact,Buffer.from('\t','utf8')]);
    assert.equal(exact.length,byteLimit);assert.equal(over.length,byteLimit+1);
    assert(over.subarray(0,byteLimit).equals(exact));
    for(const bytes of [exact,over])assert.deepEqual(JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes)),[query]);
    if(bomBytes.length)assert(exact.toString('utf8').length<exact.length);
    const exactFile=await fixture('byte-limit-'+encoding+'.json',exact);
    const overFile=await fixture('byte-limit-plus-one-'+encoding+'.json',over);
    const accepted=run(input,exactFile);
    assert.equal(accepted.code,0);assert.equal(accepted.stdout.trim().split('\n').length,1);
    assert.equal(accepted.result.results.length,1);assert.equal(accepted.result.results[0].query_index,1);
    assert.equal(accepted.result.results[0].result.status,'selected');
    const chosen=accepted.result.results[0].result.selection;
    assert.equal(chosen.record.record_index,3);assert.equal(chosen.record.source_line,20);
    const axisErrors=Object.fromEntries(['x','y','z'].map(axis=>[axis,Math.abs(chosen.state[axis]-boundaryRef[axis])]));
    for(const error of Object.values(axisErrors))assert(error<=1e-5);
    const clockError=Math.abs(chosen.state.clock_seconds-boundaryRef.clock_seconds);assert(clockError<=1e-13);
    for(const [key,value] of Object.entries({complete:true,stored_records:5,queries:1,selected:1,unavailable:0,ambiguous:0,all_selected:true})){
      assert.equal(accepted.receipt[key],value);
    }
    assert.equal(accepted.receipt.bytes,raw.length);assert.equal(accepted.receipt.lines,43);
    const rejected=run(input,overFile);failed(rejected,/1MiB/);
    assert.equal(digest(await fs.readFile(exactFile)),digest(exact));
    assert.equal(digest(await fs.readFile(overFile)),digest(over));
    assert.equal(digest(await fs.readFile(input)),digest(raw));
    byteBoundary.push({encoding,exactBytes:exact.length,overBytes:over.length,exactExit:accepted.code,overExit:rejected.code,
      bothValidUtf8Json:true,expectedReference:boundaryRef.case,recordIndex:3,sourceLine:20,axisErrorsMeters:axisErrors,
      clockErrorSeconds:clockError,overStdoutEmpty:rejected.stdout==='',requestAndNavUnchanged:true,
      exactSha256:digest(exact),overSha256:digest(over)});
  }
  failed(run(input,await fixture('oversize.json',Buffer.alloc(1048577,32))),/1MiB/);
  failed(run(input,await fixture('invalid-utf8.json',Buffer.from([255]))),/UTF-8/i);
  failed(run(input,await queries('not-array',{})),/1\.\.256/);
  const bom=await fixture('bom.json',Buffer.concat([Buffer.from([239,187,191]),Buffer.from(JSON.stringify([query]))]));
  assert.equal(run(input,bom).code,0);
  for(const flags of [['--capacity'],['--capacity','1.5'],['--skip-unsupported','--skip-unsupported'],['--other']])failed(run(input,valid,flags),/capacity|duplicate|unknown/);
  assert.equal(digest(await fs.readFile(input)),digest(raw));
  summary={status:'passed',cliCases,apiCases,bridgeGateCases:3,independentReferenceCases:refs.length,navigationOpensPerObservedBatch:1,
    maximumQueriesAccepted:256,requestSnapshotVerified:true,mixedStatusesPreserved:true,noPartialResultOnFailure:true,inputUnchanged:true,
    utf8ByteBoundary:byteBoundary};
} finally {
  const actual=await fs.realpath(directory),relative=path.relative(buildRoot,actual);
  assert(relative&&!path.isAbsolute(relative)&&relative!=='..'&&!relative.startsWith('..'+path.sep));
  await fs.rm(actual,{recursive:true,force:true});
}
console.log(JSON.stringify(summary));
