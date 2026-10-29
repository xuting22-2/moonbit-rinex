import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {extractObservations,extractGzipObservations} from './extract-observations.mjs';
import {readExtractedEpochs} from './extracted-epoch.mjs';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..'),fixtures=path.join(root,'examples/gzip-observations');
const reference=JSON.parse(await fs.readFile(path.join(fixtures,'REFERENCE.json'),'utf8'));
const containers=JSON.parse(await fs.readFile(path.join(fixtures,'PYTHON-CONTAINER-CHECKS.json'),'utf8'));
const build=await fs.realpath(path.join(root,'_build')),retained=!!process.argv[2];
const directory=retained?path.resolve(process.argv[2]):await fs.mkdtemp(path.join(build,'gzip-observations-'));
if(retained)await fs.mkdir(directory);
const sha=b=>createHash('sha256').update(b).digest('hex'),json=async p=>JSON.parse(await fs.readFile(p,'utf8'));
const cases=[],processes=[];
async function files(dir,prefix=''){
  const entries=[];
  for(const name of (await fs.readdir(dir)).sort()){
    const file=path.join(dir,name),relative=prefix+name;
    if((await fs.stat(file)).isDirectory())entries.push(...await files(file,relative+'/'));else entries.push([relative,sha(await fs.readFile(file))]);
  }
  return entries;
}
const before=await files(fixtures);
async function exists(file){try{await fs.stat(file);return true;}catch(e){if(e.code==='ENOENT')return false;throw e;}}
async function scenario(name,source='valid'){
  const dir=path.join(directory,name);await fs.mkdir(dir);const input=path.join(dir,source+'.rnx.gz'),output=path.join(dir,'package');
  await fs.copyFile(path.join(fixtures,source+'.rnx.gz'),input);return {dir,input,output,source};
}
async function proc(name,file,args,exit){
  const result=spawnSync(process.execPath,[path.join(root,file),...args],{cwd:root,encoding:'utf8',timeout:30000,maxBuffer:2097152});
  const stdout=result.stdout??'',stderr=result.stderr??'';
  await fs.writeFile(path.join(directory,name+'.stdout.log'),stdout);await fs.writeFile(path.join(directory,name+'.stderr.log'),stderr);
  processes.push({name,command:process.execPath,args:[file,...args],exitCode:result.status,signal:result.signal,error:result.error?.message??null,stdoutBytes:Buffer.byteLength(stdout),stdoutSHA256:sha(stdout),stderrBytes:Buffer.byteLength(stderr),stderrSHA256:sha(stderr)});
  await fs.writeFile(path.join(directory,'PROCESSES.json'),JSON.stringify(processes,null,2)+'\n');
  assert.ifError(result.error);assert.equal(result.status,exit,stderr||stdout);return result;
}
const produce=(name,item,exit=0,ticks=[])=>proc(name,'tools/extract-gzip-observations.mjs',[item.input,item.output,...ticks],exit);
async function recipient(name,item,epochs){
  const result=await proc(name,'tools/read-extracted-epochs.mjs',[item.output,'1',String(epochs.length),'--header'],0);
  assert.equal(result.stderr,'');const value=JSON.parse(result.stdout);assert.deepEqual(value.epochs,epochs);assert.equal(value.observation.complete,true);assert.equal(value.observation.inputAcceptable,true);
  return value;
}
async function rejectRecipient(name,item){const result=await proc(name,'tools/read-extracted-epochs.mjs',[item.output,'1','1'],1);assert.equal(result.stdout,'');assert.equal(JSON.parse(result.stderr).complete,false);}
async function verifyPackage(item,manifest,label='plain',epochs=reference.epochs){
  const compressed=await fs.readFile(item.input),decoded=containers[item.source].decoded;
  assert.equal(manifest.complete,true);assert.deepEqual(manifest.compressedInput,{encoding:'gzip',file:path.basename(item.input),bytes:compressed.length,sha256:sha(compressed),complete:true});
  assert.deepEqual({bytes:manifest.input.bytes,sha256:manifest.input.sha256},decoded);
  assert.equal(manifest.input.file,path.basename(item.input));assert.equal(manifest.selectedEpochs,epochs.length);
  const plain=path.join(fixtures,label+'-expected');
  for(const name of ['epochs.ndjson','header.json','report.json'])assert.deepEqual(await fs.readFile(path.join(item.output,name)),await fs.readFile(path.join(plain,name)));
  const expected=await json(path.join(plain,'manifest.json'));
  const comparable={...manifest,input:{...manifest.input,file:expected.input.file,bytes:expected.input.bytes,sha256:expected.input.sha256}};delete comparable.compressedInput;
  assert.deepEqual(comparable,expected);
  const actual=(await fs.readFile(path.join(item.output,'epochs.ndjson'),'utf8')).split('\n').filter(Boolean).map(JSON.parse);assert.deepEqual(actual,epochs);
  const header=await json(path.join(item.output,'header.json'));assert.deepEqual(header.raw_lines,label==='large-range'?reference.large.header_lines:label==='plain'?reference.header_lines:(await json(path.join(plain,'header.json'))).raw_lines);
  return {compressedBytes:compressed.length,compressedSHA256:sha(compressed),decodedBytes:manifest.input.bytes,decodedSHA256:manifest.input.sha256,selectedEpochs:epochs.length};
}
async function caseRun(name,action){const value=await action();cases.push({name,...value});await fs.writeFile(path.join(directory,'PROGRESS.json'),JSON.stringify(cases,null,2)+'\n');}
let passed=false;
try{
  await caseRun('gzip-api-existing-recipient-source-absent',async()=>{
    const item=await scenario('api'),manifest=await extractGzipObservations(item.input,item.output),identity=await verifyPackage(item,manifest);
    const report=await json(path.join(item.output,'report.json'));for(const [key,value] of Object.entries(reference.expectedNative))assert.deepEqual(report[key],value);
    await fs.rename(item.input,path.join(item.dir,'compressed-source-retained-away.gz'));assert.equal(await exists(item.input),false);
    const api=await readExtractedEpochs(item.output,1,3,{includeHeader:true});assert.deepEqual(api.epochs,reference.epochs);assert.deepEqual(api.header.raw_lines,reference.header_lines);assert.deepEqual(api.observation.reported_input,manifest.input);
    await recipient('api-file-recipient',item,reference.epochs);return {...identity,sourceAbsentAtOriginalPath:true,actualExistingApiAndCLIRecipients:true};
  });
  await caseRun('gzip-cli-qualified',async()=>{
    const item=await scenario('cli'),result=await produce('cli-producer',item);assert.equal(result.stderr,'');const manifest=JSON.parse(result.stdout);
    assert.deepEqual(manifest,await json(path.join(item.output,'manifest.json')));const identity=await verifyPackage(item,manifest);await recipient('cli-recipient',item,reference.epochs);return {...identity,producerExit:0,recipientExit:0};
  });
  await caseRun('old-plain-api-cli-full-byte-compatibility',async()=>{
    const dir=path.join(directory,'plain');await fs.mkdir(dir);const input=path.join(dir,'logical.rnx');await fs.copyFile(path.join(fixtures,'logical.rnx'),input);
    const output=path.join(dir,'api'),manifest=await extractObservations(input,output);assert(!Object.hasOwn(manifest,'compressedInput'));
    for(const name of ['epochs.ndjson','header.json','report.json','manifest.json'])assert.deepEqual(await fs.readFile(path.join(output,name)),await fs.readFile(path.join(fixtures,'plain-expected',name)));
    const cli=path.join(dir,'cli'),result=await proc('plain-cli','tools/extract-observations.mjs',[input,cli],0);assert.equal(result.stderr,'');assert.equal(result.stdout,JSON.stringify(manifest)+'\n');
    for(const name of ['epochs.ndjson','header.json','report.json','manifest.json'])assert.deepEqual(await fs.readFile(path.join(cli,name)),await fs.readFile(path.join(output,name)));
    return {allFourPackageFilesByteExact:true,oldCLISuccessBytesExact:true,compressedMetadataAbsent:true};
  });
  await caseRun('concatenated-members-one-logical-OBS',async()=>{
    const item=await scenario('members','members'),manifest=await extractGzipObservations(item.input,item.output),identity=await verifyPackage(item,manifest);
    await recipient('members-recipient',item,reference.epochs);return {...identity,splitInsideHeaderLine:true};
  });
  await caseRun('decoded-CRLF-and-no-final-LF',async()=>{
    for(const name of ['crlf','no-final-lf']){
      const item=await scenario(name,name),manifest=await extractGzipObservations(item.input,item.output);await verifyPackage(item,manifest);await recipient(name+'-recipient',item,reference.epochs);
    }
    return {actualLogicalVariants:2,nativeOutputByteExact:true,rawDecodedSHASeparatelyPreserved:true};
  });
  await caseRun('container-complete-native-quality-refused',async()=>{
    const item=await scenario('quality','quality'),result=await produce('quality-producer',item,2);assert.equal(result.stderr,'');const manifest=JSON.parse(result.stdout);
    assert.equal(manifest.complete,true);assert.equal(manifest.compressedInput.complete,true);assert.equal(manifest.inputAcceptable,false);await verifyPackage(item,manifest,'quality');
    const report=await json(path.join(item.output,'report.json'));assert.equal(report.complete,true);assert.equal(report.finding_counts['header-last'],1);await rejectRecipient('quality-recipient',item);
    return {producerExit:2,containerComplete:true,nativeComplete:true,nativeAcceptable:false,recipientExit:1};
  });
  for(const name of ['crc-error','size-error','truncated','garbage']){
    await caseRun(name+'-no-complete-package',async()=>{
      assert.equal(containers[name].status,'rejected');const item=await scenario(name,name),result=await produce(name+'-producer',item,1);assert.equal(result.stdout,'');const error=JSON.parse(result.stderr);assert.equal(error.complete,false);assert(['Z_DATA_ERROR','Z_BUF_ERROR'].includes(error.code));
      const manifest=await json(path.join(item.output,'manifest.json'));assert.equal(manifest.complete,false);assert.equal(await exists(path.join(item.output,'report.json')),false);
      const partial=await fs.readFile(path.join(item.output,'epochs.ndjson'),'utf8');const epochs=partial.split('\n').filter(Boolean).map(JSON.parse);assert.deepEqual(epochs,reference.epochs.slice(0,epochs.length));
      await rejectRecipient(name+'-recipient',item);return {producerExit:1,code:error.code,provisionalEpochs:epochs.length,nativeFinalReportAbsent:true,recipientExit:1};
    });
  }
  await caseRun('stored-gzip-cross-chunk-selected-range-full-validation',async()=>{
    const item=await scenario('large','large-stored'),manifest=await extractGzipObservations(item.input,item.output,reference.rangeFirstOnly),identity=await verifyPackage(item,manifest,'large-range',reference.large.selectedEpochs);
    assert.equal(manifest.compressedInput.bytes,reference.large.compressed.bytes);assert(manifest.compressedInput.bytes>65536);assert.deepEqual(manifest.gpsRange,reference.rangeFirstOnly);
    const report=await json(path.join(item.output,'report.json'));assert.equal(report.epochs,128);assert.equal(report.records,2048);assert.equal(report.first,reference.large.first);assert.equal(report.last,reference.large.last);
    const [code,phase]=report.systems[0].signals;assert.equal(code.nonempty_fields,2048);assert.equal(phase.nonempty_fields,2048);assert.equal(phase.lli_nonzero,1792);assert.equal(phase.lli_bit0,1024);assert.equal(phase.lli_bit1,1024);assert.equal(phase.lli_bit2,1024);
    await recipient('large-range-recipient',item,reference.large.selectedEpochs);return {...identity,allInputEpochs:128,allInputSatelliteRecords:2048,allInputSlots:4096,selectedEpochs:1};
  });
  await caseRun('selected-first-epoch-late-CRC-still-refused',async()=>{
    const item=await scenario('late-crc','large-late-crc'),result=await produce('late-crc-producer',item,1,reference.rangeFirstOnly);assert.equal(result.stdout,'');assert.equal(JSON.parse(result.stderr).code,'Z_DATA_ERROR');
    const manifest=await json(path.join(item.output,'manifest.json'));assert.equal(manifest.complete,false);assert.equal(manifest.selectedEpochs,1);assert.equal(await exists(path.join(item.output,'report.json')),false);
    const raw=await fs.readFile(path.join(item.output,'epochs.ndjson'));assert.deepEqual(raw,await fs.readFile(path.join(fixtures,'large-range-expected/epochs.ndjson')));assert.deepEqual(JSON.parse(raw.toString('utf8')),reference.large.selectedEpochs[0]);
    await rejectRecipient('late-crc-recipient',item);return {producerExit:1,selectedCompleteCorrectEpochBeforeError:1,qualified:false,exactRetainedNativePrefixBytes:raw.length,recipientExit:1};
  });
  await caseRun('gzip-valid-native-truncated-refused',async()=>{
    assert.equal(containers['native-truncated'].status,'decoded');const item=await scenario('native-truncated','native-truncated'),result=await produce('native-truncated-producer',item,1);assert.equal(result.stdout,'');assert.match(JSON.parse(result.stderr).error,/truncated-epoch/);
    const manifest=await json(path.join(item.output,'manifest.json'));assert.equal(manifest.complete,false);assert.equal(await exists(path.join(item.output,'report.json')),false);
    const rows=(await fs.readFile(path.join(item.output,'epochs.ndjson'),'utf8')).split('\n').filter(Boolean).map(JSON.parse);assert.deepEqual(rows,reference.epochs.slice(0,2));await rejectRecipient('native-truncated-recipient',item);
    return {producerExit:1,independentGzipComplete:true,provisionalNativeEpochs:2,nativeCompletionRequired:true,recipientExit:1};
  });
  await caseRun('occupied-output-and-source-preserved',async()=>{
    const item=await scenario('occupied'),source=await fs.readFile(item.input);await fs.mkdir(item.output);await fs.writeFile(path.join(item.output,'mine.txt'),'user-owned');
    const result=await produce('occupied-producer',item,1);assert.equal(result.stdout,'');assert.match(JSON.parse(result.stderr).error,/EEXIST/);assert.deepEqual(await fs.readdir(item.output),['mine.txt']);assert.equal(await fs.readFile(path.join(item.output,'mine.txt'),'utf8'),'user-owned');assert.deepEqual(await fs.readFile(item.input),source);
    return {occupiedDirectoryAndSourceUnchanged:true};
  });
  assert.deepEqual(await files(fixtures),before);
  const result={status:'passed',cases,processes:processes.length,actualExistingFileRecipients:true,independentPythonContainerAndFullEpochExpectations:true,oldPlainByteCompatibility:true,originalFixturesUnchanged:true,bigBudgetRun:false,oldScientificGeneratorsRun:false,thirdPartyAdoption:false};
  await fs.writeFile(path.join(directory,'RESULT.json'),JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result));passed=true;
}finally{
  if(!retained&&passed){const actual=await fs.realpath(directory),relative=path.relative(build,actual);assert(relative&&!path.isAbsolute(relative)&&relative!=='..'&&!relative.startsWith('..'+path.sep));await fs.rm(actual,{recursive:true,force:true});}
}
