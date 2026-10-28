import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {extractObservations} from './extract-observations.mjs';
import {readExtractedEpoch} from './extracted-epoch.mjs';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const buildRoot=await fs.promises.realpath(path.join(root,'_build')),retained=!!process.argv[2];
const directory=retained?path.resolve(process.argv[2]):await fs.promises.mkdtemp(path.join(buildRoot,'extracted-header-'));
if(retained)await fs.promises.mkdir(directory);
const input=path.join(root,'examples/obs-header-context.rnx'),artifact=path.join(directory,'artifact');
const sha=b=>createHash('sha256').update(b).digest('hex'),json=async file=>JSON.parse(await fs.promises.readFile(file,'utf8'));
const names=['manifest.json','report.json','header.json','epochs.ndjson'];
async function identity(dir){return Object.fromEntries(await Promise.all(names.map(async name=>{
  const b=await fs.promises.readFile(path.join(dir,name));return [name,{bytes:b.length,sha256:sha(b)}];
})));}
async function audit(operation){
  const original=fs.promises.open,trace={opened:0,closed:0,navigationOpens:0,originalObservationOpens:0,outputBytesRead:0,outputEnded:false};
  fs.promises.open=async function(file,...args){
    const absolute=path.resolve(String(file));if(absolute.endsWith('.nav'))trace.navigationOpens++;if(absolute===input)trace.originalObservationOpens++;
    const handle=await original.call(this,file,...args);trace.opened++;
    const close=handle.close.bind(handle);let didClose=false;
    handle.close=async function(){try{return await close();}finally{if(!didClose){didClose=true;trace.closed++;}}};
    if(path.basename(absolute)==='epochs.ndjson'){
      const stream=handle.createReadStream.bind(handle);
      handle.createReadStream=options=>(async function*(){for await(const chunk of stream(options)){trace.outputBytesRead+=chunk.length;yield chunk;}trace.outputEnded=true;})();
    }
    return handle;
  };
  let value,error;
  try{value=await operation();}catch(caught){error=caught;}finally{fs.promises.open=original;}
  assert.equal(trace.opened,trace.closed);return {value,error,trace};
}
const cli=[];
async function run(name,module,args,exit){
  const proc=spawnSync(process.execPath,[module,...args],{cwd:directory,encoding:'utf8',timeout:20000});
  assert.ifError(proc.error);await fs.promises.writeFile(path.join(directory,name+'.stdout'),proc.stdout);await fs.promises.writeFile(path.join(directory,name+'.stderr'),proc.stderr);
  assert.equal(proc.status,exit,proc.stderr);cli.push({name,exit:proc.status,stdoutEmpty:proc.stdout===''});return proc;
}
try{
  const reference=await json(path.join(root,'examples/EXTRACTED-HEADER-REFERENCE.json'));
  assert.equal(sha(await fs.promises.readFile(input)),reference.input.sha256);
  const manifest=await extractObservations(input,artifact),nativeReport=await json(path.join(artifact,'report.json'));
  assert.equal(manifest.complete,true);assert.equal(manifest.inputAcceptable,true);assert.equal(nativeReport.acceptable,true);
  const before=await identity(artifact),savedHeader=await json(path.join(artifact,'header.json'));
  const plain=await readExtractedEpoch(artifact,1);assert(!Object.hasOwn(plain,'header'));
  const context=await audit(()=>readExtractedEpoch(artifact,1,{includeHeader:true}));assert.ifError(context.error);
  assert.deepEqual(context.value.header,savedHeader);assert.deepEqual(context.value.header.raw_lines,reference.headerRawLines);
  assert.deepEqual(context.value.header.parsed,nativeReport.header);assert.deepEqual(context.value.header.parsed.observation_types.G,reference.observationTypes);
  assert.deepEqual(context.value.header.parsed.uninterpreted_labels,reference.uninterpretedLabels);
  assert.equal(context.value.epoch.gps_ticks,reference.gps_ticks);
  assert.deepEqual(context.value.epoch.satellites[0].observations.map(item=>item.value),reference.storedValues);
  const withoutHeader={...context.value};delete withoutHeader.header;
  assert.equal(JSON.stringify(withoutHeader),JSON.stringify(plain));
  assert.equal(context.trace.opened,4);assert.equal(context.trace.navigationOpens,0);assert.equal(context.trace.originalObservationOpens,0);
  assert(context.trace.outputEnded);assert.equal(context.trace.outputBytesRead,manifest.output.bytes);
  await fs.promises.writeFile(path.join(directory,'api-context.json'),JSON.stringify(context.value,null,2)+'\n');
  const rawCli=path.join(root,'tools/read-extracted-epoch.mjs');
  const expanded=await run('with-header',rawCli,[artifact,'1','--header'],0);assert.equal(expanded.stderr,'');assert.deepEqual(JSON.parse(expanded.stdout),context.value);
  const original=await run('default',rawCli,[artifact,'1'],0);assert.equal(original.stderr,'');assert.deepEqual(JSON.parse(original.stdout),plain);
  const example=await run('example',path.join(root,'examples/read-extracted-context.mjs'),[artifact],0);
  assert.deepEqual(JSON.parse(example.stdout).raw_header,reference.headerRawLines);assert.deepEqual(JSON.parse(example.stdout).stored_values,[1000,200]);

  // Even explicitly requested context is withheld until the whole output agrees.
  const corrupt=path.join(directory,'corrupt-output');await fs.promises.cp(artifact,corrupt,{recursive:true});
  const output=path.join(corrupt,'epochs.ndjson'),bytes=await fs.promises.readFile(output),at=bytes.indexOf('1000.000');assert(at>=0);bytes[at+7]=49;await fs.promises.writeFile(output,bytes);
  const rejected=await run('corrupt-with-header',rawCli,[corrupt,'1','--header'],1);assert.equal(rejected.stdout,'');assert.match(JSON.parse(rejected.stderr).error,/SHA256 mismatch/);
  const invalid=await audit(()=>readExtractedEpoch(path.join(directory,'absent'),1,{includeHeader:'true'}));assert(invalid.error);assert.match(invalid.error.message,/includeHeader must be boolean/);assert.equal(invalid.trace.opened,0);
  assert.deepEqual(await identity(artifact),before);
  const result={status:'passed',scenarios:3,extractionApiInvocations:1,readerApiChecks:3,cliAndExampleInvocations:4,
    independentRawHeaderRecordsCompared:9,storedValuesUnchanged:[1000,200],optionalHeaderMatchesStoredSnapshot:true,
    defaultApiAndCliJsonUnchanged:true,headerDeliveredAfterWholeOutput:true,corruptOutputWithholdsHeader:true,
    artifactUnchanged:true,headerAudit:context.trace,invalidOptionAudit:invalid.trace,cli,identities:before,
    prior23GroupsOrOldNavStateQualityFaultSuitesBuildsRerun:false,navigationQueriesRun:0};
  await fs.promises.writeFile(path.join(directory,'RESULT.json'),JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result));
}finally{
  if(!retained){
    const actual=await fs.promises.realpath(directory),relative=path.relative(buildRoot,actual);
    assert(relative&&!path.isAbsolute(relative)&&relative!=='..'&&!relative.startsWith('..'+path.sep));await fs.promises.rm(actual,{recursive:true,force:true});
  }
}
