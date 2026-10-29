import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const producer=path.join(root,'tools/restore-crinex.mjs'),receiver=path.join(root,'examples/consume-restored-file.mjs');
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
if(process.argv[2]==='--worker'){
  // Filesystem interception belongs only to this separate test process.
  // Production code has no test options, environment branches or altered budgets.
  const [mode,input,directory]=process.argv.slice(3),part=path.join(directory,'restored.rnx.part');
  const original={openSync:fs.openSync,closeSync:fs.closeSync,writeSync:fs.writeSync,renameSync:fs.renameSync,
    readFileSync:fs.readFileSync,writeFileSync:fs.writeFileSync,open:fs.promises.open};
  const fds=new Set();let corrupted=false,mutated=false;
  const trace={mode,shortWrites:0,outputWriteCalls:0,actualWrittenBytes:0,inputMutated:false,readbackCorrupted:false,rnxRenamed:false,metadataFaults:0};
  fs.openSync=function(file,...args){
    const name=path.basename(String(file));
    if((mode==='report-metadata'&&name==='report.json')||(mode==='metadata-unpersistable'&&name==='manifest.json')){
      trace.metadataFaults++;throw Object.assign(Error('injected metadata EIO'),{code:'EIO'});
    }
    const fd=original.openSync.call(this,file,...args);
    if(path.resolve(String(file))===part)fds.add(fd);
    return fd;
  };
  fs.writeSync=function(fd,buffer,...args){
    if(!fds.has(fd))return original.writeSync.call(this,fd,buffer,...args);
    trace.outputWriteCalls++;
    if(mode==='partial-eio'&&trace.outputWriteCalls===2)throw Object.assign(Error('injected EIO after actual prefix'),{code:'EIO'});
    const offset=args[0]??0,length=args[1]??buffer.length-offset;
    const count=mode==='short'?Math.max(1,Math.floor(length/2)):mode==='partial-eio'?Math.min(7,length):length;
    const written=original.writeSync.call(this,fd,buffer,offset,count,args[2]??null);
    trace.actualWrittenBytes+=written;if(written<length)trace.shortWrites++;return written;
  };
  fs.closeSync=function(fd){
    const output=fds.delete(fd);const result=original.closeSync.call(this,fd);
    if(output&&mode==='readback-mismatch'&&!corrupted){
      corrupted=true;const target=original.openSync(part,'r+');
      try{original.writeSync(target,Buffer.from('X'),0,1,0);}finally{original.closeSync(target);}
      trace.readbackCorrupted=true;
    }
    return result;
  };
  fs.renameSync=function(from,to){
    if(path.basename(String(from))==='manifest.json.part'&&['post-rename-metadata','metadata-unpersistable'].includes(mode)){
      trace.metadataFaults++;throw Object.assign(Error('injected final marker publication EACCES'),{code:'EACCES'});
    }
    const result=original.renameSync.call(this,from,to);
    if(path.basename(String(to))==='restored.rnx')trace.rnxRenamed=true;
    return result;
  };
  if(mode==='input-mutation'){
    fs.promises.open=async function(file,...args){
      const handle=await original.open.call(this,file,...args);
      if(path.resolve(String(file))===path.resolve(input)){
        const stream=handle.createReadStream.bind(handle);
        handle.createReadStream=options=>(async function*(){
          for await(const chunk of stream(options)){
            yield chunk;
            if(!mutated){
              mutated=true;const raw=original.readFileSync(input),at=raw.indexOf('0&1234');assert(at>=0);raw[at+2]=50;
              original.writeFileSync(input,raw);const future=new Date(Date.now()+3000);fs.utimesSync(input,future,future);trace.inputMutated=true;
            }
          }
        })();
      }
      return handle;
    };
  }
  process.argv=[process.execPath,producer,input,directory,...(mode==='loss'?['--recover']:[])];
  try{await import(pathToFileURL(producer).href);}
  finally{original.writeFileSync(path.join(path.dirname(directory),'TRACE.json'),JSON.stringify(trace,null,2)+'\n');}
}else{
  const build=await fs.promises.realpath(path.join(root,'_build')),retained=!!process.argv[2];
  const directory=retained?path.resolve(process.argv[2]):await fs.promises.mkdtemp(path.join(build,'crinex-file-'));
  if(retained)await fs.promises.mkdir(directory);
  const selection=process.argv[3],skipBudget=selection==='--skip-output-budget';
  const only=skipBudget?undefined:selection,fixtures=path.join(root,'examples/restoration');
  const reference=JSON.parse(await fs.promises.readFile(path.join(fixtures,'REFERENCE.json'),'utf8'));
  const cases=[],json=async p=>JSON.parse(await fs.promises.readFile(p,'utf8'));
  const {restoreCrinexFile}=await import(pathToFileURL(producer).href);
  const {consumeRestoredFile}=await import(pathToFileURL(receiver).href);
  const {consumeFormats}=await import('./formats.mjs');
  const before=Object.fromEntries(await Promise.all((await fs.promises.readdir(fixtures)).map(async name=>[name,sha(await fs.promises.readFile(path.join(fixtures,name)))])));
  async function fileHash(file){
    const hash=createHash('sha256');for await(const chunk of fs.createReadStream(file))hash.update(chunk);return hash.digest('hex');
  }
  async function scenario(name,source='modern'){
    const dir=path.join(directory,name);await fs.promises.mkdir(dir);
    const input=path.join(dir,'input.crx');await fs.promises.copyFile(path.join(fixtures,source+'.crx'),input);
    return {dir,input,package:path.join(dir,'package')};
  }
  function run(name,file,args,exit,timeout=30000){
    const proc=spawnSync(process.execPath,[file,...args],{cwd:directory,encoding:'utf8',timeout,maxBuffer:2097152});
    assert.ifError(proc.error);fs.writeFileSync(path.join(directory,name+'.stdout.log'),proc.stdout);fs.writeFileSync(path.join(directory,name+'.stderr.log'),proc.stderr);
    assert.equal(proc.status,exit,proc.stderr||proc.stdout);return proc;
  }
  async function worker(name,source='modern',mode=name,exit=1,timeout=30000){
    const item=await scenario(name,source);
    const proc=run(name,fileURLToPath(import.meta.url),['--worker',mode,item.input,item.package],exit,timeout);
    if(exit===1){assert.equal(proc.stdout,'');assert.equal(JSON.parse(proc.stderr).complete,false);}
    item.proc=proc;item.trace=await json(path.join(item.dir,'TRACE.json'));return item;
  }
  function rejectReceiver(name,item,mode='modern-check'){
    const proc=run(name+'-receiver',receiver,[item.package,'--consumer',mode],1);
    assert.equal(proc.stdout,'');assert.equal(JSON.parse(proc.stderr).complete,false);
    return proc;
  }
  async function caseRun(name,action){
    if(only&&only!==name)return;
    if(skipBudget&&name==='output-budget')return;
    process.stdout.write(JSON.stringify({case:name,status:'running'})+'\n');
    const value=await action();cases.push({name,...value});process.stdout.write(JSON.stringify({case:name,status:'passed'})+'\n');
  }
  let passed=false;
  try{
    await caseRun('modern-api',async()=>{
      const item=await scenario('modern-api'),out=await restoreCrinexFile(item.input,item.package);
      assert.equal(out.complete,true);assert.equal(out.inputReadComplete,true);assert.deepEqual(out.native_report,reference.cases.modern.nativeReport);
      assert.equal(out.input.sha256,reference.cases.modern.input.sha256);assert.equal(out.output.sha256,reference.cases.modern.output.sha256);
      assert.deepEqual(await fs.promises.readFile(path.join(item.package,'restored.rnx')),await fs.promises.readFile(path.join(fixtures,'modern.rnx')));
      await fs.promises.rename(item.input,path.join(item.dir,'original-moved-away.crx'));
      const result=await consumeRestoredFile(item.package,{consumer:'modern-check'});
      assert.equal(result.delivery.qualified,true);assert.equal(result.delivery.verified_output.sha256,out.output.sha256);
      assert.equal(result.downstream.report.complete,true);assert.equal(result.downstream.report.acceptable,true);
      assert.equal(result.downstream.report.epochs,1);assert.equal(result.downstream.report.records,1);
      await fs.promises.writeFile(path.join(item.dir,'receiver.json'),JSON.stringify(result,null,2)+'\n');
      const before=await fs.promises.readFile(path.join(item.package,'manifest.json'));
      await assert.rejects(restoreCrinexFile(path.join(fixtures,'modern.crx'),item.package),/exist/i);
      assert.deepEqual(await fs.promises.readFile(path.join(item.package,'manifest.json')),before);
      return {inputAbsentAtOriginalPath:true,verifiedOutput:out.output,existingDirectoryPreserved:true};
    });
    await caseRun('legacy-cli',async()=>{
      const item=await worker('legacy-cli','legacy','normal',0),out=JSON.parse(item.proc.stdout);
      assert.deepEqual(out.native_report,reference.cases.legacy.nativeReport);assert.equal(out.output.sha256,reference.cases.legacy.output.sha256);
      await fs.promises.rename(item.input,path.join(item.dir,'original-moved-away.crx'));
      const accepted=run('legacy-cli-receiver',receiver,[item.package,'--consumer','legacy'],0),result=JSON.parse(accepted.stdout);
      assert.equal(result.delivery.verified_output.sha256,out.output.sha256);assert.equal(result.downstream.report.complete,true);
      assert(!Object.hasOwn(result.downstream.report,'acceptable'));
      return {actualProducerExit:0,actualReceiverExit:0,inputAbsentAtOriginalPath:true,legacyQualityNotInvented:true};
    });
    await caseRun('quality',async()=>{
      const item=await worker('quality','quality','normal',0);
      const accepted=run('quality-receiver',receiver,[item.package,'--consumer','modern-check'],2),result=JSON.parse(accepted.stdout);
      assert.equal(result.delivery.qualified,true);assert.equal(result.downstream.report.complete,true);assert.equal(result.downstream.report.acceptable,false);
      assert(result.downstream.report.findings.some(x=>x.code==='header-satellite-total'&&x.error));
      return {restorationQualified:true,downstreamQualityAcceptable:false,actualReceiverExit:2};
    });
    await caseRun('late',async()=>{
      const item=await worker('late','late','normal',1),out=await json(path.join(item.package,'manifest.json'));
      assert.equal(out.complete,false);assert.equal(out.inputReadComplete,true);assert.equal(out.native_report,null);
      assert.equal(out.input.sha256,reference.cases.late.input.sha256);assert.equal(out.output.sha256,reference.cases.late.output.sha256);
      assert.match(JSON.parse(item.proc.stderr).error,/crx-truncated/);rejectReceiver('late',item);
      return {actualExit:1,priorPrefixBytes:out.output.bytes,inputEOFDistinctFromNativeFailure:true};
    });
    await caseRun('loss',async()=>{
      const item=await worker('loss','loss','loss',2),out=JSON.parse(item.proc.stdout);
      assert.equal(out.complete,false);assert.equal(out.inputReadComplete,true);assert.equal(out.native_report.complete,false);
      assert.equal(out.native_report.acceptable,false);assert.equal(out.native_report.epochs,2);assert.equal(out.native_report.recovered_epochs,1);
      assert.equal(out.native_report.findings[0].code,'crx-unsynchronized');assert.equal(out.output.file,'restored.rnx.part');
      assert.equal(out.output.sha256,reference.cases.loss.output.sha256);assert(!fs.existsSync(path.join(item.package,'restored.rnx')));
      rejectReceiver('loss',item);return {actualExit:2,lossNotQualified:true,originalNativeReport:out.native_report};
    });
    await caseRun('short',async()=>{
      const item=await worker('short','modern','short',0),out=JSON.parse(item.proc.stdout);
      assert(item.trace.shortWrites>0);assert.equal(item.trace.actualWrittenBytes,reference.cases.modern.output.bytes);
      assert.equal(out.output.sha256,reference.cases.modern.output.sha256);return {trace:item.trace,verifiedOutput:out.output};
    });
    for(const mode of ['partial-eio','input-mutation','readback-mismatch','report-metadata','post-rename-metadata','metadata-unpersistable']){
      await caseRun(mode,async()=>{
        const item=await worker(mode,'modern',mode,1),marker=path.join(item.package,'manifest.json');
        const out=fs.existsSync(marker)?await json(marker):null;
        assert(out===null||out.complete===false);
        if(out?.output){const file=path.join(item.package,out.output.file);assert.equal(out.output.bytes,(await fs.promises.stat(file)).size);assert.equal(out.output.sha256,await fileHash(file));}
        if(mode==='partial-eio'){assert.equal(out.output.bytes,7);assert.equal(out.output.sha256,sha((await fs.promises.readFile(path.join(fixtures,'modern.rnx'))).subarray(0,7)));}
        if(mode==='input-mutation'){assert(item.trace.inputMutated);assert.match(JSON.parse(item.proc.stderr).error,/input changed/);}
        if(mode==='readback-mismatch'){assert(item.trace.readbackCorrupted);assert.match(JSON.parse(item.proc.stderr).error,/readback identity mismatch/);}
        if(mode==='post-rename-metadata'||mode==='metadata-unpersistable'){assert(item.trace.rnxRenamed);assert(fs.existsSync(path.join(item.package,'restored.rnx')));}
        if(mode==='metadata-unpersistable')assert.equal(out,null);
        rejectReceiver(mode,item);
        return {actualExit:1,trace:item.trace,completeMarkerExists:out!==null,qualified:false,actualOutput:out?.output??null};
      });
    }
    await caseRun('receiver-identity',async()=>{
      const item=await scenario('receiver-identity');await restoreCrinexFile(item.input,item.package);
      const file=path.join(item.package,'restored.rnx'),raw=await fs.promises.readFile(file),at=raw.indexOf('1.234');assert(at>=0);raw[at]=50;
      await fs.promises.writeFile(file,raw);const rejected=rejectReceiver('receiver-identity',item);
      assert.match(JSON.parse(rejected.stderr).error,/consumer read does not match/);
      return {sameLengthValidRinexChangeRejected:true};
    });
    await caseRun('metadata-budget',async()=>{
      const item=await scenario('metadata-budget');await restoreCrinexFile(item.input,item.package);
      const file=path.join(item.package,'manifest.json'),raw=await fs.promises.readFile(file);
      const exact=Buffer.concat([raw,Buffer.alloc(1048576-raw.length,32)]);await fs.promises.writeFile(file,exact);
      assert.equal((await consumeRestoredFile(item.package,{consumer:'modern-check'})).delivery.qualified,true);
      await fs.promises.appendFile(file,' ');rejectReceiver('metadata-budget',item);
      return {exactMetadataBytesAccepted:1048576,oneMoreRejected:true};
    });
    await caseRun('old-defaults',async()=>{
      for(const name of ['modern','legacy','late','loss','quality']){
        const expected=reference.baseCLICompatibility[name];
        const proc=run('old-'+name,path.join(root,'tools/formats.mjs'),['crx',path.join(fixtures,name+'.crx'),...(name==='loss'?['--recover']:[])],expected.exit);
        assert.equal(proc.stdout,expected.stdout);assert.equal(proc.stderr,expected.stderr);
      }
      const items=[];const report=await consumeFormats('legacy',path.join(fixtures,'legacy.rnx'),s=>items.push(JSON.parse(s)));
      assert.deepEqual(Object.keys(report),['mode','lines','bytes','complete']);assert.equal(items.length,1);
      const epoch=items[0][1];assert.equal(epoch.gps_ticks,'14776992000000001');assert(!Object.hasOwn(epoch,'receiver_clock'));
      const value=epoch.satellites[0].values[0].observation;assert.equal(value.value,-3.25);assert.equal(value.lli,null);assert.equal(value.ssi,null);
      return {oldCliByteExactCases:5,oldSynchronousCallbackAndDefaultReportPreserved:true};
    });
    await caseRun('output-budget',async()=>{
      const dir=path.join(directory,'output-budget');await fs.promises.mkdir(dir);const input=path.join(dir,'input.crx');
      const python=process.env.RINEX_TEST_PYTHON||'python';
      const prepared=spawnSync(python,['-B',path.join(root,'tools/prepare-restoration-budget.py'),input],{cwd:directory,encoding:'utf8',timeout:60000});
      assert.ifError(prepared.error);assert.equal(prepared.status,0,prepared.stderr);const generated=JSON.parse(prepared.stdout);
      assert.equal(generated.sha256,reference.budget.input.sha256);
      const item={dir,input,package:path.join(dir,'package')};
      const proc=run('output-budget',fileURLToPath(import.meta.url),['--worker','budget',input,item.package],1,600000);
      assert.equal(proc.stdout,'');assert.match(JSON.parse(proc.stderr).error,/output exceeds 512MiB/);
      const out=await json(path.join(item.package,'manifest.json')),expected=reference.budget.committedPrefix;
      assert.equal(out.complete,false);assert.equal(out.output.bytes,expected.bytes);assert.equal(out.output.lines,expected.lines);assert.equal(out.output.sha256,expected.sha256);
      assert.equal(await fileHash(path.join(item.package,'restored.rnx.part')),expected.sha256);
      rejectReceiver('output-budget',item);return {realInputBytes:generated.bytes,actualPrefix:out.output,limit:536870912,fullIndependentOutputBytes:reference.budget.fullDecodedBytes};
    });
    assert.deepEqual(Object.fromEntries(await Promise.all((await fs.promises.readdir(fixtures)).map(async name=>[name,sha(await fs.promises.readFile(path.join(fixtures,name)))]))),before);
    const result={status:'passed',completeSelection:!only&&!skipBudget,cases,actualFilesystem:true,productionHooks:false,originalFixturesUnchanged:true,
      ...(skipBudget?{skipped:[{name:'output-budget',reason:'Explicit selection reuses frozen R06-r01 accepted 512MiB proof; full default suite still includes this case'}]}:{})};
    await fs.promises.writeFile(path.join(directory,'RESULT.json'),JSON.stringify(result,null,2)+'\n');
    console.log(JSON.stringify(result));passed=true;
  }finally{
    if(!retained&&passed){
      const actual=await fs.promises.realpath(directory),relative=path.relative(build,actual);
      assert(relative&&!path.isAbsolute(relative)&&relative!=='..'&&!relative.startsWith('..'+path.sep));
      await fs.promises.rm(actual,{recursive:true,force:true});
    }
  }
}
