import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {queryNavigationWithSource} from './nav-query.mjs';
import {replaySelectedNavigation} from '../examples/nav-source-replay.mjs';
import * as api from '../_build/js/release/build/cmd/bridge/bridge.js';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const fixtures=path.join(root,'examples/nav-source');
const reference=JSON.parse(await fs.readFile(path.join(fixtures,'REFERENCE.json'),'utf8'));
const retained=!!process.argv[2],build=await fs.realpath(path.join(root,'_build'));
const directory=retained?path.resolve(process.argv[2]):await fs.mkdtemp(path.join(build,'nav-source-'));
if(retained)await fs.mkdir(directory);
const sha=b=>createHash('sha256').update(b).digest('hex');
const before=Object.fromEntries(await Promise.all((await fs.readdir(fixtures)).map(async n=>[n,sha(await fs.readFile(path.join(fixtures,n)))])));
const cases=[];
const input=name=>path.join(fixtures,name+'.nav');
const output=name=>path.join(directory,name+'.nav');
const gps={satellite:'G01',week:2442,sow:50500};
async function exists(p){try{await fs.stat(p);return true;}catch(e){if(e.code==='ENOENT')return false;throw e;}}
async function save(name,value){await fs.writeFile(path.join(directory,name+'.json'),JSON.stringify(value,null,2)+'\n');}
async function caseRun(name,action){const actual=await action();cases.push({name,...actual});}
function state(got,ref){
  assert.deepEqual(Object.keys(got),['x','y','z','clock_seconds','group_delay_seconds','frame','iterations']);
  for(const axis of ['x','y','z'])assert(Math.abs(got[axis]-ref[axis])<=reference.positionToleranceMeters,axis);
  assert(Math.abs(got.clock_seconds-ref.clock_seconds)<=reference.clockToleranceSeconds);
  assert.equal(got.group_delay_seconds,1e-9);assert.equal(got.frame,ref.satellite[0]==='G'?'WGS84':'CGCS2000');
  assert(Number.isInteger(got.iterations)&&got.iterations>=1&&got.iterations<=20);
}
async function payload(result,ref,{recordIndex=ref.expectedRecordIndex,firstLine=reference.modernFirstLines[recordIndex-1],header=reference.header_lines,record=reference.records[recordIndex-1]}={}){
  assert.equal(result.complete,true);assert.equal(result.original.receipt.complete,true);
  assert.equal(result.original.result.status,'selected');
  const selected=result.original.result.selection,source=result.original.source;
  assert.deepEqual(source,{record_index:recordIndex,first_line:firstLine,last_line:firstLine+7,header_lines:header,record_lines:record});
  assert.equal(selected.record.record_index,recordIndex);assert.equal(selected.record.source_line,firstLine);
  assert.equal(selected.record.satellite,ref.satellite);assert.equal(selected.record.message,ref.satellite[0]==='G'?'LNAV':'B1I-D1/D2');assert.equal(selected.record.health,0);
  assert.equal(selected.report.at.gps_ticks,reference.independentCalendarTicks[ref.case]);
  state(selected.state,ref);
  assert(result.replay);assert.equal(result.replay.receipt.complete,true);assert.equal(result.replay.receipt.stored_records,1);
  assert.equal(result.replay.result.selection.record.record_index,1);
  assert.equal(result.replay.result.selection.record.source_line,header.length+1);
  assert.deepEqual(result.replay.result.selection.state,selected.state);
  state(result.replay.result.selection.state,ref);
  const raw=await fs.readFile(result.replay.file),expected=Buffer.from([...header,...record].join('\n')+'\n','ascii');
  assert.deepEqual(raw,expected);
  return {actualReceiverFileBytes:raw.length,actualReceiverFileSHA256:sha(raw),originalRecord:recordIndex,originalFirstLine:firstLine,replayRecord:1,replayFirstLine:header.length+1};
}
function run(name,file,args,exit){
  const proc=spawnSync(process.execPath,[path.join(root,file),...args],{cwd:root,encoding:'utf8',timeout:30000,maxBuffer:2097152});
  assert.ifError(proc.error);assert.equal(proc.status,exit,proc.stderr);
  return Promise.all([fs.writeFile(path.join(directory,name+'.stdout.log'),proc.stdout),fs.writeFile(path.join(directory,name+'.stderr.log'),proc.stderr)]).then(()=>proc);
}
let passed=false;
try{
  for(const ref of reference.stateReferences){
    await caseRun(ref.case,async()=>{
      const query={satellite:ref.satellite,week:ref.week,sow:ref.sow,bdt:ref.bdt,orbit:ref.bdsOrbit==='MEO_IGSO'?2:0};
      const result=await replaySelectedNavigation(input('modern'),output(ref.case),query);
      await save(ref.case,result);return payload(result,ref);
    });
  }
  await caseRun('opaque-skipped-lines',async()=>{
    const result=await replaySelectedNavigation(input('skip'),output('skip'),{...gps,skip:true});await save('skip',result);
    assert.equal(result.original.receipt.skipped_unsupported,1);
    return payload(result,reference.stateReferences[1],{firstLine:26});
  });
  await caseRun('nav2-original-text',async()=>{
    const ref=reference.stateReferences[0],result=await replaySelectedNavigation(input('legacy'),output('legacy'),{satellite:'G01',week:2442,sow:46900});await save('legacy',result);
    return payload(result,ref,{recordIndex:1,firstLine:5,header:reference.legacyHeader,record:reference.legacyRecord});
  });
  await caseRun('equivalent-first-lexical-source',async()=>{
    const ref=reference.stateReferences[0],result=await replaySelectedNavigation(input('equivalent'),output('equivalent'),{satellite:'G01',week:2442,sow:46900});await save('equivalent',result);
    assert.equal(result.original.result.selection.equivalent_records,2);assert.equal(result.replay.result.selection.equivalent_records,1);
    return payload(result,ref,{recordIndex:1,firstLine:5,record:reference.equivalentFirstRecord});
  });
  await caseRun('line-separators-and-eof',async()=>{
    const raw=await fs.readFile(input('modern'));
    for(const [name,bytes] of [['crlf',Buffer.from(raw.toString('ascii').replaceAll('\n','\r\n'))],['no-final-lf',raw.subarray(0,-1)]]){
      const file=path.join(directory,name+'-input.nav');await fs.writeFile(file,bytes);
      const result=await replaySelectedNavigation(file,output(name),gps);await save(name,result);
      await payload(result,reference.stateReferences[1]);assert.equal(result.original.receipt.bytes,bytes.length);
    }
    return {actualReceiverFiles:2,rawTextAndTrailingBlanksPreserved:true};
  });
  await caseRun('no-unique-selection-no-file',async()=>{
    for(const [name,file,query,status] of [
      ['ambiguous',input('ambiguous'),{satellite:'G01',week:2442,sow:46800},'ambiguous'],
      ['empty',input('empty'),gps,'unavailable'],
      ['orbit-required',input('modern'),{satellite:'C06',week:1086,sow:0,bdt:true},'unavailable']]){
      const request=path.join(directory,name+'-query.json');await fs.writeFile(request,JSON.stringify(query));
      const proc=await run(name,'examples/nav-source-replay.mjs',[file,output(name),request],2);
      assert.equal(proc.stderr,'');const result=JSON.parse(proc.stdout);
      assert.equal(result.complete,true);assert.equal(result.original.result.status,status);assert.equal(result.original.source,null);assert.equal(result.replay,null);assert.equal(await exists(output(name)),false);
      const point=await run(name+'-point','tools/nav-query.mjs',[file,query.satellite,String(query.week),String(query.sow),...(query.bdt?['--bdt']:[]),'--source'],2);
      assert.equal(JSON.parse(point.stdout).source,null);assert.equal(JSON.parse(point.stderr).complete,true);
    }
    return {cliCases:6,sourceNull:true,replayFilesCreated:0};
  });
  await caseRun('late-failure-and-capacity-no-payload',async()=>{
    for(const [name,file,flags] of [['truncated',input('truncated'),[]],['capacity',input('modern'),['--capacity','2']]]){
      const proc=await run(name,'tools/nav-query.mjs',[file,'G01','2442','50500','--source',...flags],1);
      assert.equal(proc.stdout,'');assert.equal(JSON.parse(proc.stderr).complete,false);
      const query={...gps,...(name==='capacity'?{capacity:2}:{})};
      const request=path.join(directory,name+'-query.json');await fs.writeFile(request,JSON.stringify(query));
      const receiver=await run(name+'-receiver','examples/nav-source-replay.mjs',[file,output(name),request],1);
      assert.equal(receiver.stdout,'');assert.equal(JSON.parse(receiver.stderr).complete,false);assert.equal(await exists(output(name)),false);
    }
    return {cliCases:4,partialPayloads:0,replayFilesCreated:0};
  });
  await caseRun('exclusive-receiver-and-cli',async()=>{
    const file=output('occupied'),original=Buffer.from('user-owned existing file');await fs.writeFile(file,original);
    const query=path.join(root,'examples/nav-source-query.json');
    const fail=await run('occupied','examples/nav-source-replay.mjs',[input('modern'),file,query],1);
    assert.equal(fail.stdout,'');assert.match(JSON.parse(fail.stderr).error,/EEXIST/);assert.deepEqual(await fs.readFile(file),original);
    const proc=await run('selected-cli','examples/nav-source-replay.mjs',[input('modern'),output('selected-cli'),query],0);assert.equal(proc.stderr,'');
    await payload(JSON.parse(proc.stdout),reference.stateReferences[1]);
    const source=await run('selected-source-cli','tools/nav-query.mjs',[input('modern'),'G01','2442','50500','--source'],0);
    assert.deepEqual(JSON.parse(source.stdout),{result:JSON.parse(proc.stdout).original.result,source:JSON.parse(proc.stdout).original.source});
    assert.deepEqual(JSON.parse(source.stderr),JSON.parse(proc.stdout).original.receipt);
    return {existingBytesPreserved:true,actualReceiverCLI:true,sourceCLI:true};
  });
  await caseRun('native-completion-and-capture-gates',async()=>{
    const rows=(await fs.readFile(input('modern'),'ascii')).split('\n').slice(0,-1);
    const session=api.nav_catalog_create_with_source(8,false);
    for(const row of rows.slice(0,12))api.nav_catalog_feed(session,row);
    assert.throws(()=>api.nav_catalog_query_source(session,'G01',2442,46900,false,0,7200),/successfully finished/);
    for(const row of rows.slice(12))api.nav_catalog_feed(session,row);
    api.nav_catalog_finish(session);
    const got=JSON.parse(api.nav_catalog_query_source(session,'G01',2442,50500,false,0,7200));
    assert.equal(got.source.record_index,3);assert.equal(got.source.first_line,21);
    got.source.record_lines[0]='caller mutation';
    assert.equal(JSON.parse(api.nav_catalog_query_source(session,'G01',2442,50500,false,0,7200)).source.record_lines[0],reference.records[2][0]);
    const plain=api.nav_catalog_create(8,false);for(const row of rows)api.nav_catalog_feed(plain,row);api.nav_catalog_finish(plain);
    assert.throws(()=>api.nav_catalog_query_source(plain,'G01',2442,50500,false,0,7200),/not enabled/);
    return {noEarlyPayload:true,oldSessionNoCapture:true,sourceSnapshotsIndependent:true};
  });
  await caseRun('old-default-byte-compatibility',async()=>{
    for(const expected of reference.baseCLICompatibility){
      const proc=await run('default-'+expected.name,'tools/nav-query.mjs',[input('modern'),...expected.arguments],expected.exit);
      assert.equal(proc.stdout,expected.stdout);assert.equal(proc.stderr,expected.stderr);
    }
    return {wholeStdoutAndStderrCases:2};
  });
  assert.deepEqual(Object.fromEntries(await Promise.all((await fs.readdir(fixtures)).map(async n=>[n,sha(await fs.readFile(path.join(fixtures,n)))]))),before);
  const result={status:'passed',cases,actualFilesystemReceiver:true,independentRawAndStateExpectations:true,originalFixturesUnchanged:true};
  await save('RESULT',result);console.log(JSON.stringify(result));passed=true;
}finally{
  if(!retained&&passed){const actual=await fs.realpath(directory),relative=path.relative(build,actual);assert(relative&&!path.isAbsolute(relative)&&relative!=='..'&&!relative.startsWith('..'+path.sep));await fs.rm(actual,{recursive:true,force:true});}
}
