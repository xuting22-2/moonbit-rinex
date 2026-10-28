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
  // Same process/API instance, real independent files, no awaits between calls.
  // Legal header comments make both successful streams cross a 64KiB block.
  const intactRows=raw.toString('ascii').split('\n');assert.equal(intactRows.pop(),'');
  const intactHeader=intactRows.slice(0,3);
  const intactRecords=Array.from({length:5},(_,i)=>intactRows.slice(3+i*8,11+i*8));
  const comments=(count,name)=>Array.from({length:count},(_,i)=>
    ('CONCURRENT '+name+' '+String(i).padStart(4,'0')).padEnd(60)+'COMMENT'.padEnd(20));
  const encode=lines=>Buffer.from(lines.join('\n')+'\n','ascii');
  const isolationCases=[
    {name:'truncated',bytes:encode(intactHeader.concat(intactRecords[0],intactRecords[4].slice(0,7))),
      requests:[{satellite:'G01',week:2442,sow:46900}]},
    {name:'full',bytes:encode(intactHeader.slice(0,-1).concat(comments(1000,'FULL'),intactHeader.at(-1),...intactRecords)),
      requests:[{satellite:'G01',week:2442,sow:50500}],records:5,lines:1043,
      expected:[{ref:'gps-fallback',record:3,line:1020}]},
    {name:'subset',bytes:encode(intactHeader.slice(0,-1).concat(comments(900,'SUBSET'),intactHeader.at(-1),intactRecords[4],intactRecords[0])),
      requests:[{satellite:'C06',week:1086,sow:1200,bdt:true,orbit:2},{satellite:'G01',week:2442,sow:46900}],records:2,lines:919,
      expected:[{ref:'bds-igso-bdt',record:1,line:904},{ref:'gps-old',record:2,line:912}]},
  ];
  for(const item of isolationCases){
    item.file=await fixture('parallel-'+item.name+'.nav',item.bytes);
    item.requestSnapshot=JSON.stringify(item.requests);
  }
  assert(isolationCases[1].bytes.length>65536&&isolationCases[2].bytes.length>65536);
  const audits=Object.fromEntries(isolationCases.map(item=>[item.name,{opens:0,closeCalls:0,closed:0,
    fdAfterClose:null,delivered:false,closedAtSettlement:false}]));
  const events=[];
  let launched=0,inFlight=0,maxInFlight=0,handles=0,maxHandles=0,failureWithOtherCallPending=false;
  const previousOpen=fs.open;
  // Observe actual handles only: no mocked API, stream, failure or scheduling.
  fs.open=async function(file,...args){
    const handle=await previousOpen.call(this,file,...args);
    const item=isolationCases.find(item=>path.resolve(String(file))===item.file);
    if(item){
      const audit=audits[item.name],close=handle.close.bind(handle);let recorded=false;
      audit.opens++;handles++;maxHandles=Math.max(maxHandles,handles);
      events.push({event:'open',name:item.name,handles});
      handle.close=async function(...args){
        audit.closeCalls++;
        const value=await close(...args);
        if(!recorded){
          recorded=true;audit.closed++;audit.fdAfterClose=handle.fd;handles--;
          events.push({event:'close',name:item.name,handles});
        }
        return value;
      };
    }
    return handle;
  };
  let outcomes;
  try{
    const pending=isolationCases.map(item=>{
      launched++;inFlight++;maxInFlight=Math.max(maxInFlight,inFlight);
      events.push({event:'start',name:item.name,launched,inFlight});
      return queryNavigationBatch(item.file,item.requests).then(value=>{
        audits[item.name].delivered=true;
        audits[item.name].closedAtSettlement=audits[item.name].closed===1&&audits[item.name].fdAfterClose===-1;
        events.push({event:'fulfilled',name:item.name,launched,inFlight});inFlight--;return value;
      },error=>{
        audits[item.name].closedAtSettlement=audits[item.name].closed===1&&audits[item.name].fdAfterClose===-1;
        if(item.name==='truncated')failureWithOtherCallPending=inFlight>1;
        events.push({event:'rejected',name:item.name,launched,inFlight});inFlight--;throw error;
      });
    });
    assert.equal(launched,3);assert.equal(inFlight,3);
    outcomes=await Promise.allSettled(pending);apiCases+=3;
  }finally{fs.open=previousOpen;}
  assert.deepEqual(outcomes.map(item=>item.status),['rejected','fulfilled','fulfilled']);
  assert(outcomes[0].reason instanceof Error);assert.match(outcomes[0].reason.message,/truncated/i);
  assert(!Object.hasOwn(outcomes[0],'value'));
  assert(!Object.hasOwn(outcomes[0].reason,'results')&&!Object.hasOwn(outcomes[0].reason,'receipt'));
  assert.equal(audits.truncated.delivered,false);
  assert.equal(maxInFlight,3);assert(maxHandles>=2);assert.equal(handles,0);assert.equal(inFlight,0);
  assert.equal(failureWithOtherCallPending,true);
  for(const audit of Object.values(audits)){
    assert.equal(audit.opens,1);assert(audit.closeCalls>=1);assert.equal(audit.closed,1);
    assert.equal(audit.fdAfterClose,-1);assert.equal(audit.closedAtSettlement,true);
  }
  const isolationComparisons=[];
  for(let i=1;i<isolationCases.length;i++){
    const item=isolationCases[i],actual=outcomes[i].value;
    assert.equal(actual.results.length,item.expected.length);
    for(const [key,value] of Object.entries({complete:true,stored_records:item.records,lines:item.lines,bytes:item.bytes.length,
      queries:item.expected.length,selected:item.expected.length,unavailable:0,ambiguous:0,all_selected:true})){
      assert.equal(actual.receipt[key],value);
    }
    for(let j=0;j<item.expected.length;j++){
      const expected=item.expected[j],ref=refs.find(ref=>ref.case===expected.ref),entry=actual.results[j];
      assert(ref);assert.equal(entry.query_index,j+1);assert.equal(entry.result.status,'selected');
      const selected=entry.result.selection;
      assert.equal(selected.record.record_index,expected.record);assert.equal(selected.record.source_line,expected.line);
      const errors=Object.fromEntries(['x','y','z'].map(axis=>[axis,Math.abs(selected.state[axis]-ref[axis])]));
      assert(Object.values(errors).every(error=>error<=1e-5));
      const clockError=Math.abs(selected.state.clock_seconds-ref.clock_seconds);assert(clockError<=1e-13);
      isolationComparisons.push({input:item.name,reference:expected.ref,record:expected.record,sourceLine:expected.line,errors,clockError});
    }
  }
  for(const item of isolationCases){
    assert.equal(digest(await fs.readFile(item.file)),digest(item.bytes));
    assert.equal(JSON.stringify(item.requests),item.requestSnapshot);
  }
  const concurrentIsolation={maxCallsInFlight:maxInFlight,maxOpenHandles:maxHandles,failureWithOtherCallPending,
    outcomes:outcomes.map(item=>item.status),failure:outcomes[0].reason.message,audits,events,
    comparisons:isolationComparisons,inputsAndRequestsUnchanged:true,
    inputs:isolationCases.map(item=>({name:item.name,bytes:item.bytes.length,sha256:digest(item.bytes),
      expectedRecords:item.records??null,expectedLines:item.lines??18}))};
  assert.equal(digest(await fs.readFile(input)),digest(raw));
  summary={status:'passed',cliCases,apiCases,bridgeGateCases:3,independentReferenceCases:refs.length,navigationOpensPerObservedBatch:1,
    maximumQueriesAccepted:256,requestSnapshotVerified:true,mixedStatusesPreserved:true,noPartialResultOnFailure:true,inputUnchanged:true,
    utf8ByteBoundary:byteBoundary,concurrentIsolation};
} finally {
  const actual=await fs.realpath(directory),relative=path.relative(buildRoot,actual);
  assert(relative&&!path.isAbsolute(relative)&&relative!=='..'&&!relative.startsWith('..'+path.sep));
  await fs.rm(actual,{recursive:true,force:true});
}
console.log(JSON.stringify(summary));
