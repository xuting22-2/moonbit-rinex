import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {extractObservations} from './extract-observations.mjs';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const buildRoot=await fs.realpath(path.join(root,'_build')),retained=!!process.argv[2];
const directory=retained?path.resolve(process.argv[2]):await fs.mkdtemp(path.join(buildRoot,'range-snapshot-'));
if(retained)await fs.mkdir(directory);
const json=async file=>JSON.parse(await fs.readFile(file,'utf8'));
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const files=['manifest.json','report.json','header.json','epochs.ndjson'];
async function artifact(at){
  return Object.fromEntries(await Promise.all(files.map(async name=>[name,await fs.readFile(path.join(at,name))])));
}
const epochs=bytes=>bytes.toString('utf8').trimEnd().split('\n').map(JSON.parse);
async function cli(name,args){
  const proc=spawnSync(process.execPath,[path.join(root,'tools/extract-observations.mjs'),...args],
    {cwd:directory,encoding:'utf8',timeout:20000});
  assert.ifError(proc.error);
  await writeLogs(name,proc);assert.equal(proc.status,0,proc.stderr||proc.stdout);assert.equal(proc.stderr,'');
  return JSON.parse(proc.stdout);
}
function writeLogs(name,proc){
  // spawnSync is complete; retain exact child stdout/stderr with other artifacts.
  return Promise.all([fs.writeFile(path.join(directory,name+'.stdout.log'),proc.stdout),
    fs.writeFile(path.join(directory,name+'.stderr.log'),proc.stderr)]);
}
try{
  const source=path.join(root,'examples/obs-series.rnx'),input=await fs.readFile(source);
  const reference=await json(path.join(root,'examples/EXTRACTED-SERIES-REFERENCE.json'));
  assert.equal(sha(input),reference.input.sha256);
  const requested=[reference.epochs[1].gps_ticks,reference.epochs[3].gps_ticks];
  const changed=[reference.epochs[0].gps_ticks,reference.epochs[1].gps_ticks];
  const caller=[...requested],at=path.join(directory,'mutable');
  const pending=extractObservations(source,at,caller);
  caller.splice(0,2,...changed);
  const output=await pending,before=await artifact(at);
  const saved=JSON.parse(before['manifest.json']);
  assert.deepEqual(epochs(before['epochs.ndjson']),reference.epochs.slice(1,3));
  assert.equal(saved.complete,true);assert.equal(saved.inputAcceptable,true);
  assert.equal(saved.selectedEpochs,2);assert.equal(saved.selectedSatelliteRecords,1);
  assert.deepEqual(saved.gpsRange,requested);assert.deepEqual(output.gpsRange,requested);
  assert.notEqual(output.gpsRange,caller);assert.deepEqual(caller,changed);
  const report=JSON.parse(before['report.json']);
  assert.equal(report.epochs,4);assert.equal(report.records,3);
  for(const [key,value] of Object.entries(reference.report))assert.equal(report[key],value);
  caller[0]='0';caller.push('later');
  assert.deepEqual(output.gpsRange,requested);
  assert.deepEqual(await artifact(at),before);

  const frozen=Object.freeze([...requested]),fixedAt=path.join(directory,'frozen');
  const fixed=await extractObservations(source,fixedAt,frozen);
  assert.deepEqual(fixed.gpsRange,requested);assert.notEqual(fixed.gpsRange,frozen);
  assert.deepEqual(await artifact(fixedAt),before);
  const cliAt=path.join(directory,'cli-range'),cliRange=await cli('cli-range',[source,cliAt,...requested]);
  assert.deepEqual(cliRange,output);assert.deepEqual(await artifact(cliAt),before);

  const fullAt=path.join(directory,'default'),full=await extractObservations(source,fullAt);
  assert.equal(full.gpsRange,null);assert.equal(full.selectedEpochs,4);
  const all=await artifact(fullAt);assert.deepEqual(epochs(all['epochs.ndjson']),reference.epochs);
  const cliFullAt=path.join(directory,'cli-default'),cliFull=await cli('cli-default',[source,cliFullAt]);
  assert.deepEqual(cliFull,full);assert.deepEqual(await artifact(cliFullAt),all);

  const invalidAt=path.join(directory,'invalid'),invalid=['bad','range'];
  const rejected=extractObservations(path.join(directory,'missing.rnx'),invalidAt,invalid);
  invalid.splice(0,2,...requested);
  await assert.rejects(rejected,/tick|range/i);
  await assert.rejects(fs.stat(invalidAt),{code:'ENOENT'});
  assert.deepEqual(invalid,requested);assert.equal(sha(await fs.readFile(source)),reference.input.sha256);
  const result={status:'passed',actualApiMutationWhilePending:true,manifestMatchesNativeRange:true,
    returnedRangeDetachedFromCaller:true,callerUnchangedByCallee:true,independentSelectedEpochsMatched:2,
    wholeInputReportEpochs:4,frozenArrayAndCliCompatible:true,defaultNullAndAllEpochsCompatible:true,
    originalInvalidRangeRejectedBeforeIO:true,inputAndSavedArtifactUnchanged:true,
    requestedRange:requested,mutatedCallerRange:changed,selectedTicks:reference.epochs.slice(1,3).map(epoch=>epoch.gps_ticks),
    mutableArtifact:Object.fromEntries(Object.entries(before).map(([name,bytes])=>[name,{bytes:bytes.length,sha256:sha(bytes)}]))};
  await fs.writeFile(path.join(directory,'RESULT.json'),JSON.stringify(result,null,2)+'\n');
  console.log(JSON.stringify(result));
}finally{
  if(!retained){
    const actual=await fs.realpath(directory),relative=path.relative(buildRoot,actual);
    assert(relative&&!path.isAbsolute(relative)&&relative!=='..'&&!relative.startsWith('..'+path.sep));
    await fs.rm(actual,{recursive:true,force:true});
  }
}
