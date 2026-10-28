import fs from 'node:fs/promises';
import path from 'node:path';
import {createHash} from 'node:crypto';

// Read stored native decisions and verified bytes; no RINEX parsing or NAV dependency.
const byteLimit=536870912;
async function metadata(file){
  const handle=await fs.open(file,'r');
  try{
    const before=await handle.stat();if(!before.isFile()||before.size>1048576)throw Error('regular artifact metadata <=1MiB required');
    const chunks=[];let bytes=0;
    for await(const chunk of handle.createReadStream({highWaterMark:65536,autoClose:false})){
      bytes+=chunk.length;if(bytes>1048576)throw Error('artifact metadata limit');chunks.push(chunk);
    }
    const after=await handle.stat();
    if(bytes!==before.size||before.size!==after.size||before.mtimeMs!==after.mtimeMs)throw Error('artifact metadata changed');
    return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(Buffer.concat(chunks)));
  }finally{await handle.close();}
}
async function readEpochWindow(directory,index,count,includeHeader){
  if(!Number.isInteger(index)||index<1||index>1000000)throw Error('epoch index must be in 1..1000000');
  if(!Number.isInteger(count)||count<1||count>256)throw Error('epoch count must be in 1..256');
  if(typeof includeHeader!=='boolean')throw Error('includeHeader must be boolean');
  const last=index+count-1;
  if(last>1000000)throw Error('epoch range must stay in 1..1000000');
  const manifest=await metadata(path.join(directory,'manifest.json'));
  if(manifest.complete!==true||manifest.inputAcceptable!==true)throw Error('observation manifest must be complete and acceptable');
  const report=await metadata(path.join(directory,'report.json'));
  if(report.complete!==true||report.acceptable!==true)throw Error('native observation report must be complete and acceptable');
  const header=await metadata(path.join(directory,'header.json'));
  if(header.parsed?.time_system!=='GPS'||report.header?.time_system!=='GPS')throw Error('artifact must declare native GPS time');
  for(const key of ['marker','license','doi']){
    if(header.parsed[key]!==report.header[key]||manifest.source?.[key]!==header.parsed[key])throw Error('artifact source metadata disagree');
  }
  const declared=manifest.output;
  if(!declared||!Number.isSafeInteger(declared.bytes)||declared.bytes<0||declared.bytes>byteLimit||
    typeof declared.sha256!=='string'||!/^[0-9a-fA-F]{64}$/.test(declared.sha256))throw Error('invalid artifact output identity');
  if(!Number.isInteger(manifest.selectedEpochs)||manifest.selectedEpochs<0||manifest.selectedEpochs>1000000||
    !Number.isInteger(report.epochs)||report.epochs<manifest.selectedEpochs||report.epochs>1000000)throw Error('invalid artifact epoch counts');
  if(last>manifest.selectedEpochs)throw Error('requested extracted epoch is absent');
  const handle=await fs.open(path.join(directory,'epochs.ndjson'),'r');
  let bytes=0,rows=0,tail=false,parts=[];
  const selected=[],wanted=row=>row>=index&&row<=last;
  const digest=createHash('sha256');
  try{
    const before=await handle.stat();
    if(!before.isFile()||before.size!==declared.bytes||before.size>byteLimit)throw Error('artifact output byte count mismatch');
    for await(const chunk of handle.createReadStream({highWaterMark:65536,autoClose:false})){
      bytes+=chunk.length;if(bytes>byteLimit)throw Error('artifact output limit');digest.update(chunk);
      let start=0;
      for(let at=0;at<chunk.length;at++)if(chunk[at]===10){
        if(wanted(rows+1)){parts.push(Buffer.from(chunk.subarray(start,at)));selected.push(Buffer.concat(parts));parts=[];}
        rows++;start=at+1;tail=false;
      }
      if(start<chunk.length){tail=true;if(wanted(rows+1))parts.push(Buffer.from(chunk.subarray(start)));}
    }
    if(tail){rows++;if(wanted(rows))selected.push(Buffer.concat(parts));}
    const after=await handle.stat();
    if(bytes!==before.size||before.size!==after.size||before.mtimeMs!==after.mtimeMs)throw Error('artifact output changed');
  }finally{await handle.close();}
  const actualSha=digest.digest('hex');
  if(actualSha!==declared.sha256.toLowerCase())throw Error('artifact output SHA256 mismatch');
  if(rows!==manifest.selectedEpochs)throw Error('artifact output epoch count mismatch');
  if(selected.length!==count)throw Error('requested extracted epoch is absent');
  const epochs=selected.map(raw=>{
    const epoch=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(raw));
    if(!epoch||Array.isArray(epoch)||typeof epoch.gps_ticks!=='string'||!Array.isArray(epoch.satellites)||
      !Number.isInteger(epoch.line)||!Number.isInteger(epoch.end_line)||epoch.line<1||epoch.end_line<epoch.line)throw Error('invalid extracted epoch shape');
    return epoch;
  });
  return {epochs,...(includeHeader?{header}:{}),observation:{complete:manifest.complete,inputAcceptable:manifest.inputAcceptable,
    native_report:{complete:report.complete,acceptable:report.acceptable,profile:report.profile,time_unit:report.time_unit,
      findings:report.findings,omitted_findings:report.omitted_findings},
    source:manifest.source,reported_input:manifest.input,
    verified_output:{bytes,sha256:actualSha,epochs:rows}}};
}

function epochTag(index,epoch){
  return {index,gps_ticks:epoch.gps_ticks,line:epoch.line,end_line:epoch.end_line,flag:epoch.flag,
    receiver_clock:epoch.receiver_clock,receiver_clock_raw:epoch.receiver_clock_raw};
}

export async function readExtractedEpoch(directory,index,{includeHeader=false}={}){
  const {epochs,header,observation}=await readEpochWindow(directory,index,1,includeHeader);
  return {epoch:epochs[0],...(includeHeader?{header}:{}),
    observation:{...observation,selected_epoch:epochTag(index,epochs[0])}};
}

// One full identity/quality check, then atomic delivery of a bounded row window.
// Indices address stored NDJSON rows, without GNSS time or quality reinterpretation.
export async function readExtractedEpochs(directory,startIndex,count,{includeHeader=false}={}){
  const {epochs,header,observation}=await readEpochWindow(directory,startIndex,count,includeHeader);
  return {epochs,...(includeHeader?{header}:{}),
    observation:{...observation,selected_epochs:epochs.map((epoch,offset)=>epochTag(startIndex+offset,epoch))}};
}

