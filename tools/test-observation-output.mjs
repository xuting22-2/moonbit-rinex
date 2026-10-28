import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';

const self=fileURLToPath(import.meta.url),root=path.resolve(path.dirname(self),'..');
const fault=process.env.RINEX_OUTPUT_FAULT_MODE;
if(fault){
  const original={openSync:fs.openSync,closeSync:fs.closeSync,writeSync:fs.writeSync,writeFileSync:fs.writeFileSync,open:fs.promises.open};
  const outputFds=new Set();
  const trace={mode:fault,fullWriteApiCalls:0,lowLevelCalls:0,shortReturns:0,actualOutputBytes:0,ioErrors:0,
    outputOpened:0,outputClosed:0,inputOpened:0,inputClosed:0,navigationOpens:0};
  fs.openSync=function(file,...args){
    const fd=original.openSync.call(this,file,...args);
    if(path.basename(String(file))==='epochs.ndjson'){outputFds.add(fd);trace.outputOpened++;}
    return fd;
  };
  fs.closeSync=function(fd){
    try{return original.closeSync.call(this,fd);}finally{if(outputFds.delete(fd))trace.outputClosed++;}
  };
  fs.writeFileSync=function(file,data,...args){
    if(typeof file==='number'&&outputFds.has(file))trace.fullWriteApiCalls++;
    return original.writeFileSync.call(this,file,data,...args);
  };
  fs.writeSync=function(fd,data,...args){
    if(!outputFds.has(fd))return original.writeSync.call(this,fd,data,...args);
    trace.lowLevelCalls++;
    if(fault==='partial-error'&&trace.lowLevelCalls===2){trace.ioErrors++;throw Object.assign(Error('injected output EIO after partial write'),{code:'EIO'});}
    const buffer=typeof data==='string'?Buffer.from(data):data;
    const offset=typeof data==='string'?0:(args[0]??0),length=typeof data==='string'?buffer.length:(args[1]??buffer.length-offset);
    const requested=Math.max(1,Math.floor(length/2));
    const written=original.writeSync.call(this,fd,buffer,offset,requested,null);
    trace.actualOutputBytes+=written;if(written<length)trace.shortReturns++;
    return written;
  };
  fs.promises.open=async function(file,...args){
    const handle=await original.open.call(this,file,...args),name=path.basename(String(file));
    if(name==='catalog-synthetic.nav')trace.navigationOpens++;
    if(name==='obs-query-time.rnx'){
      trace.inputOpened++;const close=handle.close.bind(handle);let closed=false;
      handle.close=async function(){try{return await close();}finally{if(!closed){trace.inputClosed++;closed=true;}}};
    }
    return handle;
  };
  process.on('exit',()=>original.writeFileSync(process.env.RINEX_OUTPUT_FAULT_TRACE,JSON.stringify(trace,null,2)+'\n'));
}else{
  const buildRoot=await fs.promises.realpath(path.join(root,'_build'));
  const retained=!!process.argv[2];
  const directory=retained?path.resolve(process.argv[2]):await fs.promises.mkdtemp(path.join(buildRoot,'observation-output-'));
  if(retained)await fs.promises.mkdir(directory);
  const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
  // Frozen successful output of the unchanged authored fixture, captured before
  // the writer repair. Physical readback is independent of the new writer.
  const expectedBytes=351,expectedSha256='9055f987a5c44d629d21fb2cff22eb0f5e2ed614880f1889958929c23fc4dd4d';
  const cases=[];
  try{
    for(const mode of ['short','partial-error']){
      const output=path.join(directory,mode),traceFile=path.join(directory,mode+'-trace.json');
      const proc=spawnSync(process.execPath,['--import',pathToFileURL(self).href,path.join(root,'examples/obs-tick-query.mjs'),output],
        {cwd:root,encoding:'utf8',timeout:20000,env:{...process.env,RINEX_OUTPUT_FAULT_MODE:mode,RINEX_OUTPUT_FAULT_TRACE:traceFile}});
      assert.ifError(proc.error);
      await fs.promises.writeFile(path.join(directory,mode+'.stdout'),proc.stdout);
      await fs.promises.writeFile(path.join(directory,mode+'.stderr'),proc.stderr);
      const trace=JSON.parse(await fs.promises.readFile(traceFile,'utf8'));
      const manifest=JSON.parse(await fs.promises.readFile(path.join(output,'manifest.json'),'utf8'));
      const actual=await fs.promises.readFile(path.join(output,'epochs.ndjson'));
      assert.equal(trace.fullWriteApiCalls,1);assert(trace.shortReturns>0);
      assert.equal(trace.inputOpened,trace.inputClosed);assert.equal(trace.inputOpened,1);
      assert.equal(trace.outputOpened,trace.outputClosed);assert.equal(trace.outputOpened,1);
      if(mode==='short'){
        assert.equal(proc.status,0);assert.equal(trace.navigationOpens,1);assert(trace.lowLevelCalls>1);
        assert.equal(manifest.complete,true);assert.equal(manifest.inputAcceptable,true);
        assert.equal(actual.length,expectedBytes);assert.equal(sha(actual),expectedSha256);
        assert.equal(manifest.output.bytes,actual.length);assert.equal(manifest.output.sha256,sha(actual));
        const result=JSON.parse(proc.stdout);assert.equal(result.observation.complete,true);assert.equal(result.results[0].result.status,'selected');
      }else{
        assert.equal(proc.status,1);assert.equal(proc.stdout,'');assert.equal(trace.navigationOpens,0);assert.equal(trace.ioErrors,1);
        assert.equal(manifest.complete,false);assert.equal(manifest.inputAcceptable,false);assert.match(manifest.error,/injected output EIO/);
        assert(actual.length>0&&actual.length<expectedBytes);
      }
      cases.push({mode,exit:proc.status,trace,manifestComplete:manifest.complete,manifestAcceptable:manifest.inputAcceptable,
        actualBytes:actual.length,actualSha256:sha(actual),outputReadbackMatched:mode==='short'});
    }
    const summary={status:'passed',faultScenarios:2,priorNormalOutputBytes:expectedBytes,priorNormalOutputSha256:expectedSha256,
      shortWritesCompletedAndReadBack:true,partialErrorBlockedNavigation:true,allInputOutputHandlesClosed:true,
      actualDiskFullOrPowerLossSimulated:false,cases};
    await fs.promises.writeFile(path.join(directory,'RESULT.json'),JSON.stringify(summary,null,2)+'\n');
    console.log(JSON.stringify(summary));
  }finally{
    if(!retained){
      const actual=await fs.promises.realpath(directory),relative=path.relative(buildRoot,actual);
      assert(relative&&!path.isAbsolute(relative)&&relative!=='..'&&!relative.startsWith('..'+path.sep));
      await fs.promises.rm(actual,{recursive:true,force:true});
    }
  }
}
