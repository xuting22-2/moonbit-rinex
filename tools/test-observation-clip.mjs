import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {clipObservationFile} from './clip-observations.mjs';
import {consumeClippedObservations} from '../examples/consume-clipped-observations.mjs';
import {extractObservations} from './extract-observations.mjs';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..'),fixtures=path.join(root,'examples/observation-clip');
const reference=JSON.parse(await fs.readFile(path.join(fixtures,'REFERENCE.json'),'utf8'));
const baseline=JSON.parse(await fs.readFile(path.join(fixtures,'BASELINE-CHARACTERIZATION.json'),'utf8'));
const build=await fs.realpath(path.join(root,'_build')),retained=!!process.argv[2];
const directory=retained?path.resolve(process.argv[2]):await fs.mkdtemp(path.join(build,'observation-clip-'));
if(retained)await fs.mkdir(directory);
const sha=b=>createHash('sha256').update(b).digest('hex'),json=async p=>JSON.parse(await fs.readFile(p,'utf8'));
const before=Object.fromEntries(await Promise.all((await fs.readdir(fixtures)).map(async n=>[n,sha(await fs.readFile(path.join(fixtures,n)))])));
const cases=[],processes=[];
async function exists(p){try{await fs.stat(p);return true;}catch(e){if(e.code==='ENOENT')return false;throw e;}}
async function scenario(name,source='source.rnx'){
  const dir=path.join(directory,name);await fs.mkdir(dir);const input=path.join(dir,'input.rnx'),output=path.join(dir,'package');await fs.copyFile(path.join(fixtures,source),input);return {dir,input,output};
}
async function proc(name,file,args,exit){
  const result=spawnSync(process.execPath,[path.join(root,file),...args],{cwd:root,encoding:'utf8',timeout:30000,maxBuffer:2097152});
  const stdout=result.stdout??'',stderr=result.stderr??'';await fs.writeFile(path.join(directory,name+'.stdout.log'),stdout);await fs.writeFile(path.join(directory,name+'.stderr.log'),stderr);
  processes.push({name,command:process.execPath,args:[file,...args],exitCode:result.status,signal:result.signal,error:result.error?.message??null,stdoutBytes:Buffer.byteLength(stdout),stdoutSHA256:sha(stdout),stderrBytes:Buffer.byteLength(stderr),stderrSHA256:sha(stderr)});
  await fs.writeFile(path.join(directory,'PROCESSES.json'),JSON.stringify(processes,null,2)+'\n');assert.ifError(result.error);assert.equal(result.status,exit,stderr||stdout);return result;
}
const produce=(name,item,exit=0,range=reference.range)=>proc(name,'tools/clip-observations.mjs',[item.input,item.output,...range],exit);
const recipient=(name,item,exit=0)=>proc(name,'examples/consume-clipped-observations.mjs',[item.output],exit);
async function verify(item,manifest,{expected='clipped.expected.rnx',epochs=reference.expected_epochs,sourceHeader=reference.input_header,outputHeader=reference.expected_header}={}){
  assert.equal(manifest.complete,true);assert.equal(manifest.inputAcceptable,true);assert.equal(manifest.qualified,true);assert.equal(manifest.status,'written');
  assert.equal(manifest.selectedEpochs,epochs.length);assert.equal(manifest.selectedSatelliteRecords,epochs.reduce((n,e)=>n+e.satellites.length,0));assert.equal(manifest.omittedSummaryLines,4);
  const input=await fs.readFile(item.input);assert.equal(manifest.input.bytes,input.length);assert.equal(manifest.input.sha256,sha(input));
  const file=path.join(item.output,'clipped.rnx'),raw=await fs.readFile(file);assert.deepEqual(raw,await fs.readFile(path.join(fixtures,expected)));assert.equal(manifest.output.bytes,raw.length);assert.equal(manifest.output.sha256,sha(raw));
  const source=await json(path.join(item.output,'source-header.json')),report=await json(path.join(item.output,'report.json')),outReport=await json(path.join(item.output,'output-report.json'));
  assert.deepEqual(source.raw_lines,sourceHeader);assert.deepEqual(source.parsed,report.input_report.header);assert.deepEqual(report.output_header,outputHeader);
  assert.equal(outReport.complete,true);assert.equal(outReport.acceptable,true);assert.equal(outReport.epochs,epochs.length);assert.equal(outReport.records,manifest.selectedSatelliteRecords);
  const expectedNative=baseline.find(item=>item.name===expected.slice(0,-4));assert(expectedNative);assert.deepEqual(outReport,expectedNative.report);
  assert(!Object.hasOwn(outReport.header,'declared_satellites'));assert(!outReport.header.uninterpreted_labels.includes('PRN / # OF OBS'));
  for(const label of ['SYS / SCALE FACTOR','RCV CLOCK OFFS APPL','LICENSE OF USE','COMMENT']){
    const original=sourceHeader.find(line=>line.slice(60).trim()===label);assert(outputHeader.includes(original),label);
  }
  assert.equal(outReport.first,epochs[0].gps_ticks);assert.equal(outReport.last,epochs.at(-1).gps_ticks);
  // This physically reopens the final RINEX through the old Reader, then checks
  // every stored slot/clock/flag/line against the independently authored output.
  const extraction=path.join(item.dir,'actual-reader');await extractObservations(file,extraction);
  const actual=(await fs.readFile(path.join(extraction,'epochs.ndjson'),'utf8')).split('\n').filter(Boolean).map(JSON.parse);assert.deepEqual(actual,epochs);
  return {actualRNXBytes:raw.length,actualRNXSHA256:sha(raw),actualReaderEpochs:actual.length,actualReaderRecords:manifest.selectedSatelliteRecords,fullIndependentRNXByteEquality:true};
}
async function caseRun(name,action){const actual=await action();cases.push({name,...actual});await fs.writeFile(path.join(directory,'PROGRESS.json'),JSON.stringify(cases,null,2)+'\n');}
let passed=false;
try{
  await caseRun('native-window-file-real-reader-source-absent',async()=>{
    const item=await scenario('api'),manifest=await clipObservationFile(item.input,item.output,reference.range),actual=await verify(item,manifest);
    const source=(await json(path.join(item.output,'report.json'))).input_report;for(const [key,value] of Object.entries(reference.sourceNativeCounts))assert.deepEqual(source[key],value);
    assert.deepEqual(manifest.gpsRange,reference.range);assert.equal(manifest.firstGPS,reference.range[0]);assert.equal(manifest.lastGPS,reference.outputNativeCounts.last);
    await fs.rename(item.input,path.join(item.dir,'source-retained-away.rnx'));assert.equal(await exists(item.input),false);
    const accepted=await consumeClippedObservations(item.output);assert.equal(accepted.qualified,true);assert.equal(accepted.output_report.records,3);
    const receiver=await recipient('api-recipient',item);assert.equal(receiver.stderr,'');assert.deepEqual(JSON.parse(receiver.stdout),accepted);return {...actual,sourceAbsentAtOriginalPath:true,qualifiedExistingCheckerAndReader:true};
  });
  await caseRun('cli-cross-midnight-exclusive-upper-bound',async()=>{
    const item=await scenario('cli'),producer=await produce('cli-producer',item);assert.equal(producer.stderr,'');const manifest=JSON.parse(producer.stdout);assert.deepEqual(manifest,await json(path.join(item.output,'manifest.json')));
    const actual=await verify(item,manifest);const receiver=await recipient('cli-recipient',item);assert.equal(JSON.parse(receiver.stdout).output_report.epochs,3);
    return {...actual,producerExit:0,recipientExit:0,firstDate:'2026-11-01',excludedOriginalFinalEpoch:true};
  });
  await caseRun('optional-last-remains-absent',async()=>{
    const item=await scenario('no-last','no-last-source.rnx'),manifest=await clipObservationFile(item.input,item.output,reference.range);
    const actual=await verify(item,manifest,{expected:'no-last.expected.rnx',epochs:reference.noLastOutputEpochs,sourceHeader:reference.noLastInputHeader,outputHeader:reference.noLastOutputHeader});
    const report=await json(path.join(item.output,'output-report.json'));assert(!Object.hasOwn(report.header,'last'));assert.equal(reference.noLastOutputHeader.some(line=>line.slice(60).trim()==='TIME OF LAST OBS'),false);await recipient('no-last-recipient',item);return {...actual,optionalLastNotAdded:true};
  });
  await caseRun('selected-empty-epoch-is-real-file-not-measurements',async()=>{
    const item=await scenario('empty-epoch'),manifest=await clipObservationFile(item.input,item.output,reference.emptyEpochRange);
    const actual=await verify(item,manifest,{expected:'empty-epoch.expected.rnx',epochs:reference.emptyEpochObjects,outputHeader:reference.emptyEpochHeader});assert.equal(manifest.selectedEpochs,1);assert.equal(manifest.selectedSatelliteRecords,0);
    const receiver=await recipient('empty-epoch-recipient',item),report=JSON.parse(receiver.stdout).output_report;assert.equal(report.records,0);assert.equal(report.finding_counts['empty-epoch'],1);assert.equal(report.finding_counts['power-failure'],1);return {...actual,qualified:true,measurementRecords:0};
  });
  await caseRun('empty-selection-no-success-RINEX',async()=>{
    const item=await scenario('none'),producer=await produce('none-producer',item,2,reference.noSelectionRange);assert.equal(producer.stderr,'');const manifest=JSON.parse(producer.stdout);
    assert.equal(manifest.complete,true);assert.equal(manifest.inputAcceptable,true);assert.equal(manifest.qualified,false);assert.equal(manifest.status,'empty');assert.equal(manifest.selectedEpochs,0);assert.equal(manifest.output,null);assert.equal(await exists(path.join(item.output,'clipped.rnx')),false);
    assert.equal((await fs.readFile(path.join(item.output,'body.rnx.part'))).length,0);const receiver=await recipient('none-recipient',item,1);assert.equal(receiver.stdout,'');return {producerExit:2,sourceCompleteAcceptable:true,selectedEpochs:0,successRNXAbsent:true,recipientExit:1};
  });
  await caseRun('unacceptable-whole-source-not-promoted',async()=>{
    const item=await scenario('quality','source-quality.rnx'),producer=await produce('quality-producer',item,2);assert.equal(producer.stderr,'');const manifest=JSON.parse(producer.stdout);
    assert.equal(manifest.complete,true);assert.equal(manifest.inputAcceptable,false);assert.equal(manifest.qualified,false);assert.equal(manifest.status,'input-unacceptable');assert.equal(manifest.selectedEpochs,3);assert.equal(await exists(path.join(item.output,'clipped.rnx')),false);
    const report=await json(path.join(item.output,'report.json'));assert.equal(report.input_report.finding_counts['header-last'],1);assert(!Object.hasOwn(report,'output_header'));
    const expected=(await fs.readFile(path.join(fixtures,'clipped.expected.rnx'),'ascii')).split('\n').slice(reference.expected_header.length).join('\n');assert.equal(await fs.readFile(path.join(item.output,'body.rnx.part'),'ascii'),expected);
    const receiver=await recipient('quality-recipient',item,1);assert.equal(receiver.stdout,'');return {producerExit:2,correctSelectedBodyRetained:true,wholeSourceQualityRespected:true,successRNXAbsent:true,recipientExit:1};
  });
  await caseRun('late-truncation-outside-window-still-fails',async()=>{
    const item=await scenario('truncated','source-truncated.rnx'),producer=await produce('truncated-producer',item,1);assert.equal(producer.stdout,'');assert.match(JSON.parse(producer.stderr).error,/truncated-epoch/);
    assert.equal((await json(path.join(item.output,'manifest.json'))).qualified,false);assert.equal(await exists(path.join(item.output,'clipped.rnx')),false);assert.equal(await exists(path.join(item.output,'report.json')),false);
    const expected=(await fs.readFile(path.join(fixtures,'clipped.expected.rnx'),'ascii')).split('\n').slice(reference.expected_header.length).join('\n');assert.equal(await fs.readFile(path.join(item.output,'body.rnx.part'),'ascii'),expected);
    const receiver=await recipient('truncated-recipient',item,1);assert.equal(receiver.stdout,'');return {producerExit:1,allSelectedRawBodyCorrect:true,wholeFinishRequired:true,recipientExit:1};
  });
  await caseRun('other-current-modern-version-labels',async()=>{
    for(const version of Object.keys(reference.versions)){
      const item=await scenario('version-'+version,'source-'+version+'.rnx'),manifest=await clipObservationFile(item.input,item.output,reference.range);
      const sourceHeader=reference.input_header.slice();sourceHeader[0]=(await fs.readFile(item.input,'ascii')).split('\n')[0];const outputHeader=reference.expected_header.slice();outputHeader[0]=sourceHeader[0];
      await verify(item,manifest,{expected:'clipped-'+version+'.expected.rnx',sourceHeader,outputHeader});const receiver=await recipient('version-'+version+'-recipient',item);assert.equal(JSON.parse(receiver.stdout).output_report.header.version,version);
    }
    return {otherLabels:['3.03','3.04','4.00','4.01'],base305CheckedEarlier:true,fullExpectedBytesAndExistingReaders:true};
  });
  await caseRun('source-CRLF-and-no-final-LF-normalize-only-separators',async()=>{
    const raw=await fs.readFile(path.join(fixtures,'source.rnx'));
    for(const [name,data] of [['crlf',Buffer.from(raw.toString('ascii').replaceAll('\n','\r\n'))],['no-final-lf',raw.subarray(0,-1)]]){
      const item=await scenario(name);await fs.writeFile(item.input,data);const manifest=await clipObservationFile(item.input,item.output,reference.range);await verify(item,manifest);await recipient(name+'-recipient',item);
    }
    return {sourceVariants:2,entireExpectedOutputByteEqual:true};
  });
  await caseRun('occupied-directory-and-source-preserved',async()=>{
    const item=await scenario('occupied'),input=await fs.readFile(item.input);await fs.mkdir(item.output);await fs.writeFile(path.join(item.output,'mine.txt'),'user-owned');
    const result=await produce('occupied-producer',item,1);assert.equal(result.stdout,'');assert.match(JSON.parse(result.stderr).error,/EEXIST/);assert.deepEqual(await fs.readdir(item.output),['mine.txt']);assert.equal(await fs.readFile(path.join(item.output,'mine.txt'),'utf8'),'user-owned');assert.deepEqual(await fs.readFile(item.input),input);return {sourceAndOccupiedDirectoryUnchanged:true};
  });
  await caseRun('same-length-valid-RINEX-change-not-qualified',async()=>{
    const item=await scenario('tamper');await clipObservationFile(item.input,item.output,reference.range);const file=path.join(item.output,'clipped.rnx'),raw=await fs.readFile(file),changed=Buffer.from(raw.toString('ascii').replace('3.250','3.750'));
    assert.equal(changed.length,raw.length);assert.notEqual(sha(changed),sha(raw));await fs.writeFile(file,changed);const receiver=await recipient('tampered-recipient',item,1);assert.equal(receiver.stdout,'');assert.match(JSON.parse(receiver.stderr).error,/read differs|identity/);return {actualChangedRNXRejected:true,qualifiedResultEscaped:false};
  });
  await caseRun('invalid-range-before-output',async()=>{
    for(const [name,range] of [['equal',[reference.range[0],reference.range[0]]],['nonexact',['1.5',reference.range[1]]]]){
      const item=await scenario('invalid-'+name),result=await produce('invalid-'+name+'-producer',item,1,range);assert.equal(result.stdout,'');assert.equal(await exists(item.output),false);
    }
    return {invalidCases:2,outputDirectoriesCreated:0};
  });
  assert.deepEqual(Object.fromEntries(await Promise.all((await fs.readdir(fixtures)).map(async n=>[n,sha(await fs.readFile(path.join(fixtures,n)))]))),before);
  const result={status:'passed',cases,processes:processes.length,actualCheckerAndRawReaderFiles:true,independentFullRINEXAndEpochObjects:true,originalFixturesUnchanged:true,bigBudgetRun:false,oldScientificGeneratorsRun:false,thirdPartyAdoption:false};
  await fs.writeFile(path.join(directory,'RESULT.json'),JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result));passed=true;
}finally{
  if(!retained&&passed){const actual=await fs.realpath(directory),relative=path.relative(build,actual);assert(relative&&!path.isAbsolute(relative)&&relative!=='..'&&!relative.startsWith('..'+path.sep));await fs.rm(actual,{recursive:true,force:true});}
}
