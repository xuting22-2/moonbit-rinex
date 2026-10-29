import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {consumeFormats} from './formats.mjs';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..'),fixtures=path.join(root,'examples/crinex-empty-recovery');
const read=async p=>JSON.parse(await fs.readFile(p,'utf8')),sha=b=>createHash('sha256').update(b).digest('hex');
const reference=await read(path.join(fixtures,'REFERENCE.json')),baseline=await read(path.join(fixtures,'BASELINE-CHARACTERIZATION.json'));
const before=Object.fromEntries(await Promise.all((await fs.readdir(fixtures)).map(async n=>[n,sha(await fs.readFile(path.join(fixtures,n)))])));
const retained=!!process.argv[2],build=await fs.realpath(path.join(root,'_build'));
const directory=retained?path.resolve(process.argv[2]):await fs.mkdtemp(path.join(build,'crinex-empty-recovery-'));
if(retained)await fs.mkdir(directory);
const processes=[],cases=[];let passed=false;
async function proc(name,file,args,exit){
 const p=spawnSync(process.execPath,[path.join(root,file),...args],{cwd:root,encoding:'utf8',timeout:30000,maxBuffer:8388608});
 const stdout=p.stdout??'',stderr=p.stderr??'';
 await fs.writeFile(path.join(directory,name+'.stdout.log'),stdout);await fs.writeFile(path.join(directory,name+'.stderr.log'),stderr);
 processes.push({name,command:process.execPath,args:[file,...args],exitCode:p.status,expectedExitCode:exit,signal:p.signal,error:p.error?.message??null,stdoutBytes:Buffer.byteLength(stdout),stdoutSHA256:sha(stdout),stderrBytes:Buffer.byteLength(stderr),stderrSHA256:sha(stderr)});
 await fs.writeFile(path.join(directory,'PROCESSES.json'),JSON.stringify(processes,null,2)+'\n');
 assert.ifError(p.error);assert.equal(p.status,exit,stderr||stdout);return {stdout,stderr};
}
function projection(objects,rows,modern){
 return objects.map(object=>{
  const e=modern?object:(assert.equal(object[0],'Epoch'),object[1]),raw=rows[e.line-1];
  return {gps_ticks:e.gps_ticks,flag:e.flag,line:e.line,end_line:e.end_line,raw_record:raw,receiver_clock:e.receiver_clock??null,receiver_clock_raw:raw.slice(modern?41:68,modern?56:80),
   satellites:e.satellites.map(s=>{const v=modern?s.observations[0]:s.values[0].observation;
    assert.equal(v.column,modern?4:1);assert.equal(v.code,modern?'L1C':'L1');
    return {satellite:s.satellite,raw_record:rows[s.line-1],line:s.line,value:v.value,raw_field:v.raw_field,lli:v.lli,ssi:v.ssi};})};
 });
}
function expectedProjection(item){return item.independentProjection.map(e=>({...e,receiver_clock:e.receiver_clock===null?null:Number(e.receiver_clock),satellites:e.satellites.map(s=>({...s,value:Number(s.value)}))}));}
try{
 for(const [key,item] of Object.entries(reference.case)){
  const caseDir=path.join(directory,key);await fs.mkdir(caseDir);
  const input=path.join(caseDir,'input.crx');await fs.copyFile(path.join(fixtures,item.input),input);
  let text='',report,error=null;
  try{report=await consumeFormats('crx',input,s=>{text+=s;},{recover:true});}catch(e){error=String(e.message??e);}
  await fs.writeFile(path.join(caseDir,'api-output.rnx'),text);
  await fs.writeFile(path.join(caseDir,'api-result.json'),JSON.stringify({report:report??null,error},null,2)+'\n');
  const cli=await proc(key+'-producer','tools/formats.mjs',['crx',input,'--recover'],item.expectedProducerExit);
  assert.equal(cli.stdout,text);
  if(!item.expectedRNX){
   assert(error?.includes(item.expectedError));const r=JSON.parse(cli.stderr);assert(!r.complete&&!r.acceptable);assert(r.error.includes(item.expectedError));
   assert.equal(text.split('\n').filter(Boolean).length,7);
   cases.push({name:key,producerExit:1,clockCompletionRequired:true,onlyHeaderProvisional:true});continue;
  }
  assert.equal(error,null);const expected=await fs.readFile(path.join(fixtures,item.expectedRNX));assert(Buffer.from(text).equals(expected));
  assert.equal(report.epochs,item.expectedEpochs);assert.equal(report.recovered_epochs,item.expectedRecoveredEpochs);
  assert.equal(report.complete,item.expectedComplete);assert.equal(report.acceptable,item.expectedAcceptable);
  assert.deepEqual(report.findings,baseline[key].report.findings);
  const cliReport=JSON.parse(cli.stderr);assert.deepEqual(cliReport,report);
  // Persist the actual provisional stdout, then reopen that physical file using
  // the existing consumer. Parser completion does not erase the producer loss.
  const actual=path.join(caseDir,'actual.rnx');await fs.writeFile(actual,cli.stdout);
  const native=await read(path.join(fixtures,key+'.expected-native.json'));let objects;
  if(item.version==='modern'){
   const out=path.join(caseDir,'parsed');
   await proc(key+'-recipient','tools/extract-observations.mjs',[actual,out],native.finish.acceptable?0:2);
   const ndjson=await fs.readFile(path.join(out,'epochs.ndjson'),'utf8');objects=ndjson.trim().split('\n').filter(Boolean).map(s=>JSON.parse(s));
   assert.deepEqual(await read(path.join(out,'report.json')),native.finish);
  }else{
   const parsed=await proc(key+'-recipient','tools/formats.mjs',['legacy',actual],0);
   objects=parsed.stdout.trim().split('\n').filter(Boolean).map(s=>JSON.parse(s));assert.equal(JSON.parse(parsed.stderr).complete,native.finish.complete);
  }
  assert.deepEqual(objects,native.objects);
  assert.deepEqual(projection(objects,text.slice(0,-1).split('\n'),item.version==='modern'),expectedProjection(item));
  cases.push({name:key,actualRNXBytes:expected.length,actualRNXSHA256:sha(expected),fullIndependentRNXEquality:true,fullExistingNativeObjectsEqual:true,allIndependentRawDecimalIntegerFieldsEqual:true,epochs:report.epochs,recoveredEpochs:report.recovered_epochs,complete:report.complete,acceptable:report.acceptable,actualPhysicalRecipient:true});
 }
 for(const version of ['modern','legacy']){
  const loss=reference.case[version+'-loss'],input=path.join(fixtures,loss.input);
  const failed=await proc(version+'-default-failfast','tools/formats.mjs',['crx',input],1);
  assert(JSON.parse(failed.stderr).error.includes('crx-uninitialized'));
  const header=(await fs.readFile(input,'ascii')).split('\n').slice(2,9).join('\n')+'\n';assert.equal(failed.stdout,header);
  const good=reference.case[version+'-clean'];const clean=await proc(version+'-default-clean','tools/formats.mjs',['crx',path.join(fixtures,good.input)],0);
  assert.equal(clean.stdout,await fs.readFile(path.join(fixtures,good.expectedRNX),'ascii'));assert.equal(JSON.parse(clean.stderr).recovered_epochs,0);
 }
 assert.equal(cases.length,10);assert.equal(processes.length,20);
 for(const [name,v] of Object.entries(before))assert.equal(sha(await fs.readFile(path.join(fixtures,name))),v,name);
 const result={status:'passed',cases,processes:processes.length,formats:['CRINEX1.0','CRINEX3.0'],originalFixturesUnchanged:true,newTestsUseFrozenPreimplementationExpected:true,lossNeverQualified:true,defaultFailFastUnchanged:true,noninitializedEmptyDoesNotSynchronize:true,badOrMissingClockDoesNotSynchronize:true,actualPhysicalRecipients:true,outputBudgetRun:false,oldScientificGeneratorsRun:false,externalAdoption:false};
 await fs.writeFile(path.join(directory,'RESULT.json'),JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result));passed=true;
}finally{
 if(!retained&&passed){const real=await fs.realpath(directory);assert(!path.relative(build,real).startsWith('..'));await fs.rm(real,{recursive:true,force:true});}
}
