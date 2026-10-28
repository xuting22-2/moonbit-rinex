import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {extractObservations} from './extract-observations.mjs';
import {readExtractedEpoch} from './extracted-epoch.mjs';
import {queryExtractedEpoch} from './query-extracted-epoch.mjs';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const buildRoot=await fs.promises.realpath(path.join(root,'_build')),retained=!!process.argv[2];
const directory=retained?path.resolve(process.argv[2]):await fs.promises.mkdtemp(path.join(buildRoot,'read-extracted-'));
if(retained)await fs.promises.mkdir(directory);
const input=path.join(root,'examples/obs-raw-values.rnx'),nav=path.join(root,'examples/catalog-synthetic.nav');
const artifact=path.join(directory,'artifact'),sha=b=>createHash('sha256').update(b).digest('hex');
const json=async file=>JSON.parse(await fs.promises.readFile(file,'utf8'));
const writeJson=(file,value)=>fs.promises.writeFile(file,JSON.stringify(value,null,2)+'\n');
const names=['manifest.json','report.json','header.json','epochs.ndjson'];
async function identity(dir){return Object.fromEntries(await Promise.all(names.map(async name=>{
  const bytes=await fs.promises.readFile(path.join(dir,name));return [name,{bytes:bytes.length,sha256:sha(bytes)}];
})));}
async function audit(operation){
  const original=fs.promises.open,trace={opened:0,closed:0,navigationOpens:0,originalObservationOpens:0};
  fs.promises.open=async function(file,...args){
    const absolute=path.resolve(String(file));if(absolute===nav)trace.navigationOpens++;if(absolute===input)trace.originalObservationOpens++;
    const handle=await original.call(this,file,...args);trace.opened++;
    const close=handle.close.bind(handle);let didClose=false;
    handle.close=async function(){try{return await close();}finally{if(!didClose){didClose=true;trace.closed++;}}};return handle;
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
  const reference=await json(path.join(root,'examples/EXTRACTED-RAW-REFERENCE.json'));
  assert.equal(sha(await fs.promises.readFile(input)),reference.input.sha256);
  const manifest=await extractObservations(input,artifact),report=await json(path.join(artifact,'report.json'));
  assert.equal(manifest.complete,true);assert.equal(manifest.inputAcceptable,true);assert.equal(manifest.selectedSatelliteRecords,3);
  assert.equal(report.acceptable,true);assert(report.findings.some(item=>item.code==='power-failure'&&!item.error));
  const before=await identity(artifact);
  const read=await audit(()=>readExtractedEpoch(artifact,1));assert.ifError(read.error);
  assert.deepEqual(read.value.epoch,reference.epoch);assert.equal(read.trace.opened,4);assert.equal(read.trace.navigationOpens,0);assert.equal(read.trace.originalObservationOpens,0);
  const observation=read.value.observation;
  assert.deepEqual(observation.source,manifest.source);assert.deepEqual(observation.reported_input,manifest.input);
  assert.deepEqual(observation.verified_output,{...manifest.output,epochs:1});assert.deepEqual(observation.native_report.findings,report.findings);
  assert.equal(observation.native_report.acceptable,true);
  await writeJson(path.join(directory,'api-result.json'),read.value);

  // Copy only the pure IO reader and CLI: no native bridge, NAV or original OBS.
  const standalone=path.join(directory,'standalone','tools');await fs.promises.mkdir(standalone,{recursive:true});
  for(const name of ['extracted-epoch.mjs','read-extracted-epoch.mjs'])await fs.promises.copyFile(path.join(root,'tools',name),path.join(standalone,name));
  assert(!fs.existsSync(path.join(directory,'standalone','_build')));
  const rawCli=path.join(standalone,'read-extracted-epoch.mjs');
  const plain=await run('standalone',rawCli,[artifact,'1'],0);assert.equal(plain.stderr,'');assert.deepEqual(JSON.parse(plain.stdout),read.value);
  const example=await run('example',path.join(root,'examples/read-extracted-epoch.mjs'),[artifact],0);
  assert.deepEqual(JSON.parse(example.stdout).observed_satellites,['G01','C06','E25']);

  // The existing query shares precisely this observation metadata; native query
  // semantics are checked only as an ordinary missing satellite, no orbit oracle.
  const query=await audit(()=>queryExtractedEpoch(artifact,nav,1,['G99']));assert.ifError(query.error);
  assert.deepEqual(query.value.observation,observation);assert.equal(query.value.results[0].result.status,'unavailable');
  assert.equal(query.value.receipt.complete,true);assert.equal(query.value.receipt.unavailable,1);assert.equal(query.trace.navigationOpens,1);assert.equal(query.trace.originalObservationOpens,0);
  await writeJson(path.join(directory,'query-result.json'),query.value);

  const corrupted=path.join(directory,'same-length-corruption');await fs.promises.cp(artifact,corrupted,{recursive:true});
  const output=path.join(corrupted,'epochs.ndjson'),bytes=await fs.promises.readFile(output),at=bytes.indexOf('-123.250');assert(at>=0);
  bytes[at+7]=49;await fs.promises.writeFile(output,bytes);
  const badQuery=await audit(()=>queryExtractedEpoch(corrupted,nav,1,['G99']));assert(badQuery.error);assert.match(badQuery.error.message,/SHA256 mismatch/);assert.equal(badQuery.trace.navigationOpens,0);assert.equal(badQuery.value,undefined);
  const failed=await run('corrupted',rawCli,[corrupted,'1'],1);assert.equal(failed.stdout,'');assert.match(JSON.parse(failed.stderr).error,/SHA256 mismatch/);

  const unacceptable=path.join(directory,'unacceptable');await fs.promises.cp(artifact,unacceptable,{recursive:true});
  const rejectedManifest={...manifest,inputAcceptable:false};await writeJson(path.join(unacceptable,'manifest.json'),rejectedManifest);
  const quality=await audit(()=>readExtractedEpoch(unacceptable,1));assert(quality.error);assert.match(quality.error.message,/manifest must be complete and acceptable/);assert.equal(quality.trace.opened,1);assert.equal(quality.trace.navigationOpens,0);assert.equal(quality.value,undefined);
  const bounds=await audit(()=>readExtractedEpoch(artifact,0));assert(bounds.error);assert.match(bounds.error.message,/epoch index/);assert.equal(bounds.trace.opened,0);
  const invalid=await run('index-zero',rawCli,[artifact,'0'],1);assert.equal(invalid.stdout,'');assert.match(JSON.parse(invalid.stderr).error,/epoch index/);
  assert.deepEqual(await identity(artifact),before);
  const result={status:'passed',scenarios:4,extractionInvocations:1,rawSlotsCompared:5,observedSatellites:3,
    exactIndependentEpochMatched:true,zeroNegativeNullAndRawIndicatorsPreserved:true,noSatelliteFiltering:true,
    acceptableWarningPreserved:true,standaloneCliWithoutNativeBridge:true,standaloneFiles:await fs.promises.readdir(standalone),
    originalObservationOpensDuringRead:read.trace.originalObservationOpens,artifactUnchanged:true,
    audits:{rawRead:read.trace,coupledQuery:query.trace,corruptedQuery:badQuery.trace,unacceptableRead:quality.trace,indexZero:bounds.trace},
    cli,identities:before,nativeTestsBuildsOrOldStateOraclesRerun:false};
  await writeJson(path.join(directory,'RESULT.json'),result);console.log(JSON.stringify(result));
}finally{
  if(!retained){
    const actual=await fs.promises.realpath(directory),relative=path.relative(buildRoot,actual);
    assert(relative&&!path.isAbsolute(relative)&&relative!=='..'&&!relative.startsWith('..'+path.sep));
    await fs.promises.rm(actual,{recursive:true,force:true});
  }
}
