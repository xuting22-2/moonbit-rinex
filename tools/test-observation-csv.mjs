import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {exportObservationCsv} from './export-observation-csv.mjs';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..'),fixtures=path.join(root,'examples/observation-csv');
const reference=JSON.parse(await fs.readFile(path.join(fixtures,'REFERENCE.json'),'utf8'));
const build=await fs.realpath(path.join(root,'_build')),retained=!!process.argv[2];
const directory=retained?path.resolve(process.argv[2]):await fs.mkdtemp(path.join(build,'observation-csv-'));
if(retained)await fs.mkdir(directory);
const sha=b=>createHash('sha256').update(b).digest('hex'),json=async p=>JSON.parse(await fs.readFile(p,'utf8'));
const before=Object.fromEntries(await Promise.all((await fs.readdir(fixtures)).map(async n=>[n,sha(await fs.readFile(path.join(fixtures,n)))])));
const cases=[];const python=process.env.RINEX_TEST_PYTHON||'python';
async function exists(p){try{await fs.stat(p);return true;}catch(e){if(e.code==='ENOENT')return false;throw e;}}
async function scenario(name,source='raw-obs'){
  const dir=path.join(directory,name);await fs.mkdir(dir);const input=path.join(dir,'input.rnx'),output=path.join(dir,'table');
  await fs.copyFile(path.join(fixtures,source+'.rnx'),input);return {dir,input,output};
}
async function proc(name,command,args,exit){
  const result=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:30000,maxBuffer:2097152});assert.ifError(result.error);
  await fs.writeFile(path.join(directory,name+'.stdout.log'),result.stdout);await fs.writeFile(path.join(directory,name+'.stderr.log'),result.stderr);
  assert.equal(result.status,exit,result.stderr||result.stdout);return result;
}
const produce=(name,item,exit=0)=>proc(name,process.execPath,[path.join(root,'tools/export-observation-csv.mjs'),item.input,item.output],exit);
const consume=(name,item,exit=0)=>proc(name,python,['-B',path.join(root,'examples/read-observation-csv.py'),item.output],exit);
async function caseRun(name,action){const actual=await action();cases.push({name,...actual});}
async function verifyOutput(item,manifest,expectedName='expected.csv',summary=reference.nativeSummary,expectedHeader=reference.header_lines){
  assert.equal(manifest.schema,'raw-observation-csv-v1');assert.equal(manifest.complete,true);
  const input=await fs.readFile(item.input);assert.equal(manifest.input.bytes,input.length);assert.equal(manifest.input.sha256,sha(input));
  assert.deepEqual(manifest.table,summary);
  const bytes=await fs.readFile(path.join(item.output,'observations.csv')),expected=await fs.readFile(path.join(fixtures,expectedName));
  assert.deepEqual(bytes,expected);assert.equal(manifest.output.sha256,sha(bytes));assert.equal(manifest.output.bytes,bytes.length);assert.equal(manifest.output.lines,summary.rows+1);
  assert.equal(await exists(path.join(item.output,'observations.csv.part')),false);
  const native=await json(path.join(item.output,'report.json')),header=await json(path.join(item.output,'header.json'));
  assert.deepEqual(header.parsed,native.input_report.header);assert.equal(native.input_report.complete,true);
  assert.deepEqual({epochs:native.epochs,satellite_records:native.satellite_records,observation_rows:native.observation_rows,rows:native.rows},summary);
  assert.equal(native.input_report.epochs,summary.epochs);assert.equal(native.input_report.records,summary.satellite_records);
  if(expectedName==='expected.csv')assert.deepEqual(header.raw_lines,expectedHeader);
  return {csvBytes:bytes.length,csvSHA256:sha(bytes),nativeInputAcceptable:native.input_report.acceptable};
}
let passed=false;
try{
  await caseRun('api-and-source-absent-decimal-recipient',async()=>{
    const item=await scenario('api'),manifest=await exportObservationCsv(item.input,item.output),identity=await verifyOutput(item,manifest);
    const native=(await json(path.join(item.output,'report.json'))).input_report;
    for(const [key,value] of Object.entries(reference.nativeQuality))assert.deepEqual(native[key],value);
    await fs.rename(item.input,path.join(item.dir,'source-retained-away.rnx'));assert.equal(await exists(item.input),false);
    const recipient=await consume('api-recipient',item);assert.equal(recipient.stderr,'');assert.deepEqual(JSON.parse(recipient.stdout),reference.expectedConsumer);
    return {...identity,sourceAbsentAtOriginalPath:true,independentDecimalTotals:true,fullCSVByteEquality:true};
  });
  await caseRun('cli-complete-native-output',async()=>{
    const item=await scenario('cli'),result=await produce('cli-producer',item);assert.equal(result.stderr,'');const manifest=JSON.parse(result.stdout);
    assert.deepEqual(manifest,await json(path.join(item.output,'manifest.json')));const actual=await verifyOutput(item,manifest);
    const recipient=await consume('cli-recipient',item);assert.deepEqual(JSON.parse(recipient.stdout),reference.expectedConsumer);return {...actual,producerExit:0,recipientExit:0};
  });
  await caseRun('complete-native-quality-not-accepted-statistics',async()=>{
    const item=await scenario('quality','quality'),producer=await produce('quality-producer',item,2);assert.equal(producer.stderr,'');
    const manifest=JSON.parse(producer.stdout);assert.equal(manifest.complete,true);assert.equal(manifest.inputAcceptable,false);
    const qualityHeader=(await fs.readFile(path.join(fixtures,'quality.rnx'),'ascii')).split('\n').slice(0,reference.header_lines.length);
    await verifyOutput(item,manifest,'expected.csv',reference.nativeSummary,qualityHeader);
    const native=(await json(path.join(item.output,'report.json'))).input_report;assert.equal(native.finding_counts['header-last'],1);
    const recipient=await consume('quality-recipient',item,2);assert.equal(recipient.stderr,'');const denied=JSON.parse(recipient.stdout);
    assert.equal(denied.complete,false);assert.equal(denied.nativeInputComplete,true);assert.equal(denied.acceptedStatistics,false);assert.equal(denied.inputAcceptable,false);assert(!Object.hasOwn(denied,'groups'));
    return {producerExit:2,nativeComplete:true,nativeAcceptable:false,recipientExit:2,acceptedStatistics:false};
  });
  for(const name of ['truncated','bad-number']){
    await caseRun(name+'-no-success-table',async()=>{
      const item=await scenario(name,name),producer=await produce(name+'-producer',item,1);assert.equal(producer.stdout,'');assert.equal(JSON.parse(producer.stderr).complete,false);
      const manifest=await json(path.join(item.output,'manifest.json'));assert.equal(manifest.complete,false);assert.equal(await exists(path.join(item.output,'observations.csv')),false);
      const part=await fs.readFile(path.join(item.output,'observations.csv.part'));
      const expected=await fs.readFile(path.join(fixtures,'expected.csv'),'ascii');const prefix=expected.split('\n').slice(0,name==='truncated'?10:1).join('\n')+'\n';
      assert.deepEqual(part,Buffer.from(prefix));const recipient=await consume(name+'-recipient',item,1);assert.equal(recipient.stdout,'');assert.equal(JSON.parse(recipient.stderr).complete,false);
      return {producerExit:1,recipientExit:1,partialCSVBytes:part.length,exactProvisionalPrefix:true,successTableAbsent:true};
    });
  }
  await caseRun('occupied-output-preserved',async()=>{
    const item=await scenario('occupied');await fs.mkdir(item.output);const sentinel=path.join(item.output,'mine.txt');await fs.writeFile(sentinel,'user-owned');
    const before=await fs.readFile(item.input),producer=await produce('occupied-producer',item,1);assert.equal(producer.stdout,'');assert.match(JSON.parse(producer.stderr).error,/EEXIST/);
    assert.deepEqual(await fs.readdir(item.output),['mine.txt']);assert.equal(await fs.readFile(sentinel,'utf8'),'user-owned');assert.deepEqual(await fs.readFile(item.input),before);
    return {occupiedDirectoryAndInputUnchanged:true};
  });
  await caseRun('line-endings-and-exact-tick-text',async()=>{
    const original=await fs.readFile(path.join(fixtures,'raw-obs.rnx'));
    for(const [name,bytes] of [['crlf',Buffer.from(original.toString('ascii').replaceAll('\n','\r\n'))],['no-final-lf',original.subarray(0,-1)]]){
      const item=await scenario(name);await fs.writeFile(item.input,bytes);const manifest=await exportObservationCsv(item.input,item.output);await verifyOutput(item,manifest);
      const recipient=await consume(name+'-recipient',item);assert.deepEqual(JSON.parse(recipient.stdout),reference.expectedConsumer);
    }
    return {actualRecipients:2,fullExpectedCSVUnchanged:true,oddTickAbove2Pow53Preserved:true};
  });
  await caseRun('cross-buffer-small-volume',async()=>{
    const item=await scenario('volume','cross-buffer'),manifest=await exportObservationCsv(item.input,item.output);
    const {epochs,satellite_records,observation_rows,rows}=reference.volume;const identity=await verifyOutput(item,manifest,'cross-buffer.expected.csv',{epochs,satellite_records,observation_rows,rows});
    const recipient=await consume('volume-recipient',item),actual=JSON.parse(recipient.stdout);
    assert.deepEqual({epochs:actual.epochs,satellite_records:actual.satellite_records,observation_rows:actual.observation_rows},{epochs,satellite_records,observation_rows});
    assert.equal(actual.empty_epochs,0);assert.equal(actual.first_gps_ticks,reference.expectedConsumer.first_gps_ticks);assert.equal(actual.last_gps_ticks,String(BigInt(actual.first_gps_ticks)+1023n*300000000n));
    assert.deepEqual(actual.groups,[{satellite:'G01',code:'C1C',rows:1024,blank_values:0,zero_values:1024,lli_nonzero:0,sum_stored_raw:'0.000'},{satellite:'G01',code:'L1C',rows:1024,blank_values:0,zero_values:0,lli_nonzero:1024,sum_stored_raw:'1280.000'}]);
    return {...identity,actualEpochs:1024,actualCSVRows:3072,independentWholeCSV:true,bigBudgetRun:false};
  });
  await caseRun('same-length-CSV-change-no-accepted-statistics',async()=>{
    const item=await scenario('identity');await exportObservationCsv(item.input,item.output);const file=path.join(item.output,'observations.csv'),raw=await fs.readFile(file);
    const changed=Buffer.from(raw.toString('ascii').replaceAll('-12.250','-13.250'));assert.equal(changed.length,raw.length);assert.notEqual(sha(changed),sha(raw));await fs.writeFile(file,changed);
    const recipient=await consume('changed-csv-recipient',item,1);assert.equal(recipient.stdout,'');assert.match(JSON.parse(recipient.stderr).error,/identity mismatch/);
    return {actualSameLengthChangeRejected:true,acceptedStatisticsEscaped:false};
  });
  await caseRun('CSV-context-checked-beyond-identity',async()=>{
    const item=await scenario('context');await exportObservationCsv(item.input,item.output);const file=path.join(item.output,'observations.csv'),raw=await fs.readFile(file,'ascii');
    const changed=Buffer.from(raw.replace('"epoch","3"','"epoch","9"'));assert.notEqual(changed.toString('ascii'),raw);await fs.writeFile(file,changed);
    const manifest=await json(path.join(item.output,'manifest.json'));manifest.output.sha256=sha(changed);await fs.writeFile(path.join(item.output,'manifest.json'),JSON.stringify(manifest));
    const recipient=await consume('bad-context-recipient',item,1);assert.equal(recipient.stdout,'');assert.match(JSON.parse(recipient.stderr).error,/epoch index sequence/);
    return {tableGrammarAndContextIndependentlyChecked:true,metadataHashNotSoleAcceptance:true};
  });
  assert.deepEqual(Object.fromEntries(await Promise.all((await fs.readdir(fixtures)).map(async n=>[n,sha(await fs.readFile(path.join(fixtures,n)))]))),before);
  const result={status:'passed',cases,fullIndependentCSVAndDecimalExpectations:true,actualPythonCSVRecipients:true,originalFixturesUnchanged:true,bigBudgetRun:false,thirdPartyAdoption:false};
  await fs.writeFile(path.join(directory,'RESULT.json'),JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result));passed=true;
}finally{
  if(!retained&&passed){const actual=await fs.realpath(directory),relative=path.relative(build,actual);assert(relative&&!path.isAbsolute(relative)&&relative!=='..'&&!relative.startsWith('..'+path.sep));await fs.rm(actual,{recursive:true,force:true});}
}
