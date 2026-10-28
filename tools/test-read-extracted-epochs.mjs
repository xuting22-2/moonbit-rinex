import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {extractObservations} from './extract-observations.mjs';
import {readExtractedEpoch,readExtractedEpochs} from './extracted-epoch.mjs';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const buildRoot=await fs.promises.realpath(path.join(root,'_build')),retained=!!process.argv[2];
const directory=retained?path.resolve(process.argv[2]):await fs.promises.mkdtemp(path.join(buildRoot,'read-epochs-'));
if(retained)await fs.promises.mkdir(directory);
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const json=async file=>JSON.parse(await fs.promises.readFile(file,'utf8'));
const writeJson=(file,value)=>fs.promises.writeFile(file,JSON.stringify(value,null,2)+'\n');
const names=['manifest.json','report.json','header.json','epochs.ndjson'],audits={},cli=[];
async function identity(artifact){
  return Object.fromEntries(await Promise.all(names.map(async name=>{
    const raw=await fs.promises.readFile(path.join(artifact,name));
    return [name,{bytes:raw.length,sha256:sha(raw)}];
  })));
}
async function audit(name,artifact,action){
  const original=fs.promises.open,outputFile=path.join(artifact,'epochs.ndjson');
  const trace={opened:0,closed:0,outputOpens:0,outputBytesRead:0,outputChunks:0,outputEnded:false,
    originalObservationOpens:0,navigationOpens:0,allClosedDescriptors:true};
  fs.promises.open=async function(file,...args){
    const absolute=path.resolve(String(file));
    if(absolute.endsWith('.rnx'))trace.originalObservationOpens++;
    if(absolute.endsWith('.nav'))trace.navigationOpens++;
    const handle=await original.call(this,file,...args);trace.opened++;
    const close=handle.close.bind(handle);let recorded=false;
    handle.close=async function(...args){
      const result=await close(...args);
      if(!recorded){recorded=true;trace.closed++;trace.allClosedDescriptors&&=handle.fd===-1;}
      return result;
    };
    if(absolute===outputFile){
      trace.outputOpens++;
      const stream=handle.createReadStream.bind(handle);
      handle.createReadStream=options=>(async function*(){
        for await(const chunk of stream(options)){trace.outputBytesRead+=chunk.length;trace.outputChunks++;yield chunk;}
        trace.outputEnded=true;
      })();
    }
    return handle;
  };
  let value,error;
  try{value=await action();}catch(caught){error=caught;}finally{fs.promises.open=original;}
  assert.equal(trace.opened,trace.closed);assert.equal(trace.allClosedDescriptors,true);
  assert.equal(trace.originalObservationOpens,0);assert.equal(trace.navigationOpens,0);
  audits[name]=trace;
  return {value,error,trace};
}
function run(name,module,args,exit){
  const proc=spawnSync(process.execPath,[module,...args],{cwd:directory,encoding:'utf8',timeout:20000});
  assert.ifError(proc.error);
  fs.writeFileSync(path.join(directory,name+'.stdout.log'),proc.stdout);
  fs.writeFileSync(path.join(directory,name+'.stderr.log'),proc.stderr);
  assert.equal(proc.status,exit,proc.stderr||proc.stdout);
  cli.push({name,exit:proc.status,stdoutEmpty:proc.stdout===''});
  return proc;
}
function reject(proc,pattern){
  assert.equal(proc.stdout,'');const error=JSON.parse(proc.stderr);
  assert.equal(error.complete,false);assert.match(error.error,pattern);
}
try{
  const input=path.join(root,'examples/obs-series.rnx');
  const reference=await json(path.join(root,'examples/EXTRACTED-SERIES-REFERENCE.json'));
  const inputBytes=await fs.promises.readFile(input);
  assert.equal(sha(inputBytes),reference.input.sha256);
  const artifact=path.join(directory,'artifact');
  const manifest=await extractObservations(input,artifact),report=await json(path.join(artifact,'report.json'));
  assert.equal(manifest.complete,true);assert.equal(manifest.inputAcceptable,true);
  assert.equal(manifest.selectedEpochs,4);assert.equal(manifest.selectedSatelliteRecords,3);
  for(const [key,value] of Object.entries(reference.report))assert.equal(report[key],value);
  const before=await identity(artifact),header=await json(path.join(artifact,'header.json'));
  const batch=await audit('window',artifact,()=>readExtractedEpochs(artifact,2,2));assert.ifError(batch.error);
  assert.deepEqual(batch.value.epochs,reference.epochs.slice(1,3));
  assert.deepEqual(batch.value.observation.selected_epochs.map(item=>item.index),[2,3]);
  assert(!Object.hasOwn(batch.value,'header'));
  assert.deepEqual(batch.value.observation.native_report.findings,report.findings);
  assert.deepEqual(batch.value.observation.verified_output,{...manifest.output,epochs:4});
  assert.equal(batch.trace.outputOpens,1);assert.equal(batch.trace.outputBytesRead,manifest.output.bytes);
  assert.equal(batch.trace.outputEnded,true);
  const one=await readExtractedEpoch(artifact,2);
  assert.deepEqual(one.epoch,reference.epochs[1]);
  const {selected_epochs,...common}=batch.value.observation;
  assert.deepEqual(one.observation,{...common,selected_epoch:selected_epochs[0]});
  const context=await audit('header',artifact,()=>readExtractedEpochs(artifact,4,1,{includeHeader:true}));assert.ifError(context.error);
  assert.deepEqual(context.value.epochs,[reference.epochs[3]]);
  assert.deepEqual(context.value.header,header);assert.equal(context.trace.outputEnded,true);

  // Consumer copy contains no original OBS, NAV, bridge or other project module.
  const standalone=path.join(directory,'standalone','tools');await fs.promises.mkdir(standalone,{recursive:true});
  for(const name of ['extracted-epoch.mjs','read-extracted-epochs.mjs'])await fs.promises.copyFile(path.join(root,'tools',name),path.join(standalone,name));
  assert.deepEqual((await fs.promises.readdir(standalone)).sort(),['extracted-epoch.mjs','read-extracted-epochs.mjs']);
  const cliFile=path.join(standalone,'read-extracted-epochs.mjs');
  const plain=run('standalone',cliFile,[artifact,'1','4'],0);assert.equal(plain.stderr,'');
  assert.deepEqual(JSON.parse(plain.stdout).epochs,reference.epochs);
  const withHeader=run('standalone-header',cliFile,[artifact,'2','2','--header'],0);
  assert.deepEqual(JSON.parse(withHeader.stdout).header,header);
  const example=run('example',path.join(root,'examples/read-extracted-epochs.mjs'),[artifact],0);
  assert.deepEqual(JSON.parse(example.stdout).epochs,reference.epochs.slice(1,3));

  for(const [start,count,options,pattern] of [[0,1,{},/epoch index/],[1,0,{},/epoch count/],
    [1,257,{},/epoch count/],[1,1.5,{},/epoch count/],[1000000,2,{},/epoch range/],
    [1,1,{includeHeader:'true'},/includeHeader must be boolean/]]){
    const name='arguments-'+Object.keys(audits).length;
    const bad=await audit(name,path.join(directory,'absent'),()=>readExtractedEpochs(path.join(directory,'absent'),start,count,options));
    assert(bad.error);assert.match(bad.error.message,pattern);assert.equal(bad.value,undefined);assert.equal(bad.trace.opened,0);
  }
  const absent=await audit('absent-range',artifact,()=>readExtractedEpochs(artifact,4,2));
  assert(absent.error);assert.match(absent.error.message,/epoch is absent/);assert.equal(absent.value,undefined);assert.equal(absent.trace.outputOpens,0);
  reject(run('absent-range',cliFile,[artifact,'4','2'],1),/epoch is absent/);
  reject(run('invalid-count',cliFile,[artifact,'1','257'],1),/epoch count/);

  const badInput=path.join(directory,'bad-series.rnx'),lines=inputBytes.toString('ascii').trimEnd().split('\n');
  const end=lines.findIndex(line=>line.slice(60).trim()==='END OF HEADER');
  lines.splice(end,0,'     2'.padEnd(60)+'# OF SATELLITES');
  await fs.promises.writeFile(badInput,lines.join('\n')+'\n');
  const badArtifact=path.join(directory,'quality-failure'),badManifest=await extractObservations(badInput,badArtifact);
  const badReport=await json(path.join(badArtifact,'report.json'));
  assert.equal(badManifest.complete,true);assert.equal(badManifest.inputAcceptable,false);
  assert(badReport.findings.some(item=>item.code==='header-satellite-total'&&item.error));
  const quality=await audit('quality',badArtifact,()=>readExtractedEpochs(badArtifact,2,2));
  assert(quality.error);assert.match(quality.error.message,/manifest must be complete and acceptable/);
  assert.equal(quality.value,undefined);assert.equal(quality.trace.outputOpens,0);
  reject(run('quality',cliFile,[badArtifact,'2','2'],1),/manifest must be complete and acceptable/);

  const corrupt=path.join(directory,'unselected-tail-corruption');await fs.promises.cp(artifact,corrupt,{recursive:true});
  const outputFile=path.join(corrupt,'epochs.ndjson'),output=await fs.promises.readFile(outputFile);
  const changed=Buffer.from(output),at=changed.indexOf(reference.epochs[3].gps_ticks);assert(at>=0);
  changed[at+reference.epochs[3].gps_ticks.length-1]=51;assert.equal(changed.length,output.length);
  await fs.promises.writeFile(outputFile,changed);
  const corruption=await audit('tail-corruption',corrupt,()=>readExtractedEpochs(corrupt,2,2,{includeHeader:true}));
  assert(corruption.error);assert.match(corruption.error.message,/SHA256 mismatch/);assert.equal(corruption.value,undefined);
  assert.equal(corruption.trace.outputEnded,true);assert.equal(corruption.trace.outputBytesRead,manifest.output.bytes);
  reject(run('tail-corruption',cliFile,[corrupt,'2','2','--header'],1),/SHA256 mismatch/);

  const late=path.join(directory,'later-selected-shape');await fs.promises.cp(artifact,late,{recursive:true});
  const stored=output.toString('utf8').trimEnd().split('\n');stored[2]='null';
  const lateBytes=Buffer.from(stored.join('\n')+'\n');await fs.promises.writeFile(path.join(late,'epochs.ndjson'),lateBytes);
  const lateManifest=await json(path.join(late,'manifest.json'));
  lateManifest.output={bytes:lateBytes.length,sha256:sha(lateBytes)};await writeJson(path.join(late,'manifest.json'),lateManifest);
  const malformed=await audit('later-shape',late,()=>readExtractedEpochs(late,2,2));
  assert(malformed.error);assert.match(malformed.error.message,/invalid extracted epoch shape/);assert.equal(malformed.value,undefined);
  assert.equal(malformed.trace.outputEnded,true);
  reject(run('later-shape',cliFile,[late,'2','2'],1),/invalid extracted epoch shape/);
  // The old one-row contract does not reinterpret unselected stored JSON.
  assert.deepEqual((await readExtractedEpoch(late,2)).epoch,reference.epochs[1]);

  const withoutLF=path.join(directory,'last-line-without-lf');await fs.promises.cp(artifact,withoutLF,{recursive:true});
  const noLF=output.subarray(0,-1);await fs.promises.writeFile(path.join(withoutLF,'epochs.ndjson'),noLF);
  const noLFManifest=await json(path.join(withoutLF,'manifest.json'));
  noLFManifest.output={bytes:noLF.length,sha256:sha(noLF)};await writeJson(path.join(withoutLF,'manifest.json'),noLFManifest);
  assert.deepEqual((await readExtractedEpochs(withoutLF,3,2)).epochs,reference.epochs.slice(2));

  // A real 260-epoch extraction exercises 256 returned rows and chunk boundaries.
  const manyLines=inputBytes.toString('ascii').split('\n').slice(0,7);
  const manyEpochLines=[];
  for(let i=0;i<260;i++){
    const seconds=i*30,hour=12+Math.floor(seconds/3600),minute=Math.floor(seconds%3600/60),second=seconds%60;
    const stamp='> 2026 10 25 '+String(hour).padStart(2,'0')+' '+String(minute).padStart(2,'0')+' '+
      String(second).padStart(2,'0')+'.0000001  0  1';
    manyEpochLines.push(stamp);manyLines.push(stamp,'G01        10.50007');
  }
  const manyInput=path.join(directory,'many.rnx');await fs.promises.writeFile(manyInput,manyLines.join('\n')+'\n');
  const manyArtifact=path.join(directory,'many'),manyManifest=await extractObservations(manyInput,manyArtifact);
  assert.equal(manyManifest.inputAcceptable,true);assert.equal(manyManifest.selectedEpochs,260);
  assert(manyManifest.output.bytes>65536);
  const maximum=await audit('maximum',manyArtifact,()=>readExtractedEpochs(manyArtifact,2,256));assert.ifError(maximum.error);
  assert.equal(maximum.value.epochs.length,256);assert.equal(maximum.trace.outputOpens,1);
  assert(maximum.trace.outputChunks>=2);assert.equal(maximum.trace.outputEnded,true);
  assert.equal(maximum.trace.outputBytesRead,manyManifest.output.bytes);
  assert.equal(maximum.value.observation.verified_output.epochs,260);
  for(let i=0;i<256;i++){
    const index=i+2,epoch=maximum.value.epochs[i],tag=maximum.value.observation.selected_epochs[i];
    assert.equal(epoch.gps_ticks,(14773968000000001n+BigInt(index-1)*300000000n).toString());
    assert.equal(epoch.line,6+2*index);assert.equal(epoch.end_line,7+2*index);
    assert.equal(epoch.raw_record,manyEpochLines[index-1]);assert.equal(tag.index,index);
    assert.equal(epoch.satellites[0].observations[0].value,10.5);
  }
  assert.deepEqual(await identity(artifact),before);assert.equal(sha(await fs.promises.readFile(input)),reference.input.sha256);
  const result={status:'passed',scenarios:8,window:{start:2,count:2,independentEpochsMatched:true,
    dataOpens:batch.trace.outputOpens,bytesRead:batch.trace.outputBytesRead},
    maximumCountAccepted:256,largeArtifactEpochs:260,selectedLaterShapeAtomicFailure:true,
    unselectedTailCorruptionRejected:true,oldSingleShapeCompatible:true,standaloneWithoutBridge:true,
    nativeWarningsPreserved:true,inputAndArtifactUnchanged:true,cli,audits};
  await writeJson(path.join(directory,'RESULT.json'),result);console.log(JSON.stringify(result));
}finally{
  if(!retained){
    const actual=await fs.promises.realpath(directory),relative=path.relative(buildRoot,actual);
    assert(relative&&!path.isAbsolute(relative)&&relative!=='..'&&!relative.startsWith('..'+path.sep));
    await fs.promises.rm(actual,{recursive:true,force:true});
  }
}
