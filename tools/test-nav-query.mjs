import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {queryNavigation} from './nav-query.mjs';
import * as api from '../_build/js/release/build/cmd/bridge/bridge.js';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const input=path.join(root,'examples/catalog-synthetic.nav'),raw=await fs.readFile(input);
const refs=JSON.parse(await fs.readFile(path.join(root,'examples/CATALOG-REFERENCE.json'),'utf8'));
const rows=raw.toString('ascii').trimEnd().split('\n'),header=rows.slice(0,3),records=Array.from({length:5},(_,i)=>rows.slice(3+i*8,3+(i+1)*8));
assert.equal(rows.length,43);
const buildRoot=await fs.realpath(path.join(root,'_build'));
const directory=await fs.mkdtemp(path.join(buildRoot,'catalog-host-'));
const digest=b=>createHash('sha256').update(b).digest('hex');
let cliCases=0,summary;
function run(file,satellite='G01',week='2442',sow='50500',flags=[]){
  const proc=spawnSync(process.execPath,[path.join(root,'tools/nav-query.mjs'),file,satellite,week,sow,...flags],{cwd:root,encoding:'utf8',timeout:20000});
  assert.ifError(proc.error);cliCases++;
  return {code:proc.status,stdout:proc.stdout,receipt:JSON.parse(proc.stderr),result:proc.stdout?JSON.parse(proc.stdout):null};
}
async function fixture(name,data){const file=path.join(directory,name+'.nav');await fs.writeFile(file,data);return file;}
function failed(result,pattern){assert.equal(result.code,1);assert.equal(result.stdout,'');assert.equal(result.receipt.complete,false);assert.match(result.receipt.error,pattern);}
try {
  for(const ref of refs){
    const flags=[...(ref.bdt?['--bdt']:[]),...(ref.bdsOrbit?['--meo-igso']:[])];
    const result=run(input,ref.satellite,String(ref.week),String(ref.sow),flags);
    assert.equal(result.code,0);assert.equal(result.result.status,'selected');assert.equal(result.receipt.complete,true);
    const selected=result.result.selection;assert.equal(selected.record.record_index,ref.expectedRecordIndex);
    assert.equal(selected.record.source_line,4+(ref.expectedRecordIndex-1)*8);
    for(const axis of ['x','y','z'])assert(Math.abs(selected.state[axis]-ref[axis])<1e-5);
    assert(Math.abs(selected.state.clock_seconds-ref.clock_seconds)<1e-13);
  }
  const imported=await queryNavigation(input,{satellite:'G01',week:2442,sow:50500});
  assert.equal(imported.result.selection.record.record_index,3);
  for(const [satellite,week,sow,flags,reason] of [
    ['C06','1086','0',['--bdt'],'orbit-type-required'],['G99','2442','50500',[],null],['G01','2442','64800',[],'expired']]){
    const result=run(input,satellite,week,sow,flags);assert.equal(result.code,2);assert.equal(result.result.status,'unavailable');
    if(reason)assert(result.result.report.rejection_counts[reason]>0);else assert.equal(result.result.report.candidates,0);
  }
  const equivalent=await fixture('equivalent',header.concat(records[0],records[0]).join('\n')+'\n');
  let result=run(equivalent,'G01','2442','46800');assert.equal(result.code,0);assert.equal(result.result.selection.equivalent_records,2);
  const changed=records[0].slice(),clock=' 1.200000000000E-04';assert.equal(clock.length,19);
  changed[0]=changed[0].slice(0,23)+clock+changed[0].slice(42);
  const conflict=await fixture('conflict',header.concat(records[0],changed).join('\n')+'\n');
  result=run(conflict,'G01','2442','46800');assert.equal(result.code,2);assert.equal(result.result.status,'ambiguous');assert.equal(result.result.conflict.tied_records,2);assert(!('selection' in result.result));
  const truncated=await fixture('truncated',rows.slice(0,-1).join('\n')+'\n');failed(run(truncated),/truncated/i);
  failed(run(input,'G01','2442','50500',['--capacity','2']),/CatalogCapacityExceeded/);
  const invalidByte=await fixture('invalid-byte',Buffer.concat([raw,Buffer.from([255,10])]));failed(run(invalidByte),/ASCII/);
  const longLine=await fixture('long-line',Buffer.concat([raw,Buffer.from('X'.repeat(9000)+'\n')]));failed(run(longLine),/line limit/);
  for(const [name,bytes] of [['crlf',Buffer.from(raw.toString('ascii').replaceAll('\n','\r\n'))],['no-final-lf',raw.subarray(0,-1)]]){
    const file=await fixture(name,bytes);assert.equal(run(file).result.selection.record.record_index,3);
  }
  const number=' 0.000000000000E+00';
  const opaqueR=['R01 2026 10 25 00 00 00'+number.repeat(3),...Array.from({length:4},()=> '    '+number.repeat(4))];
  const unsupported=await fixture('unsupported',header.concat(opaqueR,...records).join('\n')+'\n');
  failed(run(unsupported),/UnsupportedConstellation/);
  result=run(unsupported,'G01','2442','50500',['--skip-unsupported']);assert.equal(result.code,0);assert.equal(result.receipt.skipped_unsupported,1);assert.equal(result.result.selection.record.source_line,25);
  for(const flags of [['--capacity','0'],['--capacity','1.5'],['--max-age','0'],['--geo','--meo-igso'],['--bdt','--bdt'],['--capacity']])failed(run(input,'G01','2442','50500',flags),/./);
  failed(run(input,'G01','7001','0'),/out of range/);failed(run(input,'G01','2442','604800'),/out of range/);

  const partial=api.nav_catalog_create(1,false);
  assert.throws(()=>api.nav_catalog_query(partial,'G01',2442,50500,false,0,7200),/successfully finished/);
  for(const row of header.concat(records[0]))api.nav_catalog_feed(partial,row);
  assert.throws(()=>{for(const row of records[1])api.nav_catalog_feed(partial,row);},/CatalogCapacityExceeded/);
  assert.throws(()=>api.nav_catalog_query(partial,'G01',2442,46800,false,0,7200),/successfully finished/);
  assert.throws(()=>api.nav_catalog_finish(partial),/failed or finished/);
  const reusable=api.nav_catalog_create(6,false);
  for(const row of rows)api.nav_catalog_feed(reusable,row);
  assert.equal(JSON.parse(api.nav_catalog_finish(reusable)).stored_records,5);
  assert.throws(()=>api.nav_catalog_query(reusable,'G01',2442,50500,false,3,7200),/invalid BDS orbit/);
  assert.equal(JSON.parse(api.nav_catalog_query(reusable,'G01',2442,50500,false,0,7200)).selection.record.record_index,3);
  assert.equal(JSON.parse(api.nav_catalog_query(reusable,'C06',1086,0,true,2,7200)).selection.record.record_index,5);
  assert.equal(digest(await fs.readFile(input)),digest(raw));
  summary={cliCases,importedApiCases:1,bridgeGateCases:2,independentReferenceCases:refs.length,inputUnchanged:true,noPartialResultOnInputFailure:true,status:'passed'};
} finally {
  const actual=await fs.realpath(directory),relative=path.relative(buildRoot,actual);
  assert(relative&&!path.isAbsolute(relative)&&relative!=='..'&&!relative.startsWith('..'+path.sep));
  await fs.rm(actual,{recursive:true,force:true});
}
console.log(JSON.stringify(summary));
