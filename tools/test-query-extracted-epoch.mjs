import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {extractObservations} from './extract-observations.mjs';
import {queryExtractedEpoch} from './query-extracted-epoch.mjs';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const retained=!!process.argv[2],buildRoot=await fs.promises.realpath(path.join(root,'_build'));
const directory=retained?path.resolve(process.argv[2]):await fs.promises.mkdtemp(path.join(buildRoot,'extracted-query-'));
if(retained)await fs.promises.mkdir(directory);
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const json=async file=>JSON.parse(await fs.promises.readFile(file,'utf8'));
const writeJson=(file,value)=>fs.promises.writeFile(file,JSON.stringify(value,null,2)+'\n');
const identities=async dir=>Object.fromEntries(await Promise.all(['manifest.json','header.json','report.json','epochs.ndjson'].map(async name=>{
  const bytes=await fs.promises.readFile(path.join(dir,name));return [name,{bytes:bytes.length,sha256:sha(bytes)}];
})));
const nav=path.join(root,'examples/catalog-synthetic.nav'),reference=await json(path.join(root,'examples/EXTRACTED-EPOCH-REFERENCE.json'));
const originalOpen=fs.promises.open;
let navigationOpens=0,opened=0,closed=0,artifactBytesRead=0,artifactReadEnded=false;
try{
  // A new actual two-epoch extraction, with an acceptable power-failure warning.
  // The second row's time/state come from independent datetime/RTKLIB reference.
  const rows=(await fs.promises.readFile(path.join(root,'examples/obs-query-time.rnx'),'ascii')).trimEnd().split(/\r?\n/);
  const raw=Buffer.from(rows.concat(['> 2026 10 25 13 02 10.0000000  1  1','G01  20000001.000 7']).join('\n')+'\n');
  assert.equal(sha(raw),reference.inputs['two-epochs.rnx'].sha256);
  const input=path.join(directory,'two-epochs.rnx'),valid=path.join(directory,'valid');
  await fs.promises.writeFile(input,raw);await extractObservations(input,valid);
  const manifest=await json(path.join(valid,'manifest.json')),nativeReport=await json(path.join(valid,'report.json'));
  assert.equal(manifest.selectedEpochs,2);assert.equal(manifest.inputAcceptable,true);
  assert.equal(nativeReport.power_failure_epochs,1);assert(nativeReport.findings.some(finding=>finding.code==='power-failure'&&!finding.error));
  const before=await identities(valid);
  fs.promises.open=async function(file,...args){
    if(path.resolve(String(file))===nav){assert(artifactReadEnded);assert.equal(artifactBytesRead,manifest.output.bytes);navigationOpens++;}
    const handle=await originalOpen.call(this,file,...args);opened++;
    const close=handle.close.bind(handle);let didClose=false;
    handle.close=async function(){try{return await close();}finally{if(!didClose){closed++;didClose=true;}}};
    if(path.basename(String(file))==='epochs.ndjson'){
      const stream=handle.createReadStream.bind(handle);
      // Force row boundaries across many chunks without manufacturing huge data.
      handle.createReadStream=function(options){
        return (async function*(){for await(const chunk of stream({...options,highWaterMark:13})){artifactBytesRead+=chunk.length;yield chunk;}artifactReadEnded=true;})();
      };
    }
    return handle;
  };
  const satellites=['G01','G99'],pending=queryExtractedEpoch(valid,nav,2,satellites);satellites[0]='G99';
  const result=await pending;
  assert.equal(navigationOpens,1);assert.equal(opened,closed);
  assert.deepEqual(result.observation.native_report.findings,nativeReport.findings);
  assert.equal(result.observation.inputAcceptable,true);assert.equal(result.observation.native_report.acceptable,true);
  assert.equal(result.observation.selected_epoch.index,2);assert.equal(result.observation.selected_epoch.gps_ticks,reference.gps_ticks);
  assert.equal(result.observation.selected_epoch.line,reference.observationSourceLine);
  assert.equal(result.observation.selected_epoch.end_line,reference.observationEndLine);
  assert.equal(result.observation.selected_epoch.flag,1);
  assert.deepEqual(result.observation.verified_output,{...manifest.output,epochs:2});
  assert.deepEqual(result.observation.source,manifest.source);assert.deepEqual(result.observation.reported_input,manifest.input);
  assert.equal(result.receipt.selected,1);assert.equal(result.receipt.unavailable,1);assert.equal(result.receipt.all_selected,false);
  assert.equal(result.results[1].result.status,'unavailable');
  const selected=result.results[0].result;assert.equal(selected.status,'selected');
  assert.equal(selected.selection.record.record_index,reference.selectedRecordIndex);
  assert.equal(selected.selection.record.source_line,reference.selectedSourceLine);
  const deltas={};
  for(const key of ['x','y','z','clock_seconds']){
    const difference=Math.abs(selected.selection.state[key]-reference.state[key]);deltas[key]=difference;
    assert(difference<=(key==='clock_seconds'?reference.clockToleranceSeconds:reference.xyzComponentToleranceMeters));
  }
  await writeJson(path.join(directory,'api-result.json'),result);
  fs.promises.open=originalOpen;
  assert.deepEqual(await identities(valid),before);

  const failures=[];
  async function rejectsArtifact(name,edit,pattern){
    const target=path.join(directory,name);await fs.promises.cp(valid,target,{recursive:true});
    await edit(target);const identity=await identities(target);navigationOpens=0;opened=closed=0;
    fs.promises.open=async function(file,...args){
      if(path.resolve(String(file))===nav)navigationOpens++;
      const handle=await originalOpen.call(this,file,...args);opened++;
      const close=handle.close.bind(handle);let didClose=false;
      handle.close=async function(){try{return await close();}finally{if(!didClose){closed++;didClose=true;}}};return handle;
    };
    try{await assert.rejects(queryExtractedEpoch(target,nav,1,['G01']),pattern);}
    finally{fs.promises.open=originalOpen;}
    assert.equal(navigationOpens,0);assert.equal(opened,closed);assert.deepEqual(await identities(target),identity);
    failures.push({name,navigationOpens,opened,closed,readOnly:true});
  }
  const editJson=async(dir,name,edit)=>{const file=path.join(dir,name),value=await json(file);edit(value);await writeJson(file,value);};
  await rejectsArtifact('manifest-string-flag',dir=>editJson(dir,'manifest.json',value=>{value.inputAcceptable='true';}),/manifest must be complete and acceptable/);
  await rejectsArtifact('report-unacceptable',dir=>editJson(dir,'report.json',value=>{value.acceptable=false;}),/report must be complete and acceptable/);
  await rejectsArtifact('time-tag-mismatch',dir=>editJson(dir,'header.json',value=>{value.parsed.time_system='UTC';}),/native GPS time/);
  await rejectsArtifact('source-mismatch',dir=>editJson(dir,'manifest.json',value=>{value.source.marker='changed';}),/source metadata disagree/);
  await rejectsArtifact('same-length-corruption',async dir=>{
    const file=path.join(dir,'epochs.ndjson'),bytes=await fs.promises.readFile(file),at=bytes.indexOf('20000001');
    assert(at>=0);bytes[at+7]=57;await fs.promises.writeFile(file,bytes);
  },/SHA256 mismatch/);
  await rejectsArtifact('byte-count-mismatch',dir=>editJson(dir,'manifest.json',value=>{value.output.bytes++;}),/byte count mismatch/);
  await rejectsArtifact('row-count-mismatch',dir=>editJson(dir,'manifest.json',value=>{value.selectedEpochs=1;}),/epoch count mismatch/);
  navigationOpens=0;fs.promises.open=async function(file,...args){if(path.resolve(String(file))===nav)navigationOpens++;return originalOpen.call(this,file,...args);};
  try{await assert.rejects(queryExtractedEpoch(valid,nav,3,['G01']),/epoch is absent/);}finally{fs.promises.open=originalOpen;}
  assert.equal(navigationOpens,0);failures.push({name:'absent-row',navigationOpens});

  const cli=[];
  for(const [name,dir,satellite,exit] of [['selected',valid,'G01',0],['unavailable',valid,'G99',2],['corrupt',path.join(directory,'same-length-corruption'),'G01',1]]){
    const proc=spawnSync(process.execPath,[path.join(root,'tools/query-extracted-epoch.mjs'),dir,nav,'2',satellite],{cwd:root,encoding:'utf8',timeout:20000});
    assert.ifError(proc.error);assert.equal(proc.status,exit,proc.stderr);
    await fs.promises.writeFile(path.join(directory,name+'.stdout'),proc.stdout);await fs.promises.writeFile(path.join(directory,name+'.stderr'),proc.stderr);
    if(exit===1){assert.equal(proc.stdout,'');assert.match(JSON.parse(proc.stderr).error,/SHA256 mismatch/);}
    else{const output=JSON.parse(proc.stdout);assert.equal(output.receipt.all_selected,exit===0);assert.equal(output.observation.selected_epoch.gps_ticks,reference.gps_ticks);}
    cli.push({name,exit:proc.status,stdoutEmpty:proc.stdout===''});
  }
  assert.deepEqual(await identities(valid),before);
  const summary={status:'passed',scenarios:3,actualExtractionEpochs:2,acceptableWarningPreserved:true,
    apiSelected:1,apiUnavailable:1,independentReferenceDeltas:deltas,chunkBytes:13,
    fullArtifactReadBeforeNavigation:true,argumentSnapshotPreserved:true,artifactUnchanged:true,
    artifactFailures:failures,cli,identities:before};
  await writeJson(path.join(directory,'RESULT.json'),summary);console.log(JSON.stringify(summary));
}finally{
  fs.promises.open=originalOpen;
  if(!retained){
    const actual=await fs.promises.realpath(directory),relative=path.relative(buildRoot,actual);
    assert(relative&&!path.isAbsolute(relative)&&relative!=='..'&&!relative.startsWith('..'+path.sep));
    await fs.promises.rm(actual,{recursive:true,force:true});
  }
}
