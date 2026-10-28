import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import * as api from '../_build/js/release/build/cmd/bridge/bridge.js';

// Keep files in the host and the shared grammar/state in the MoonBit Reader.
export async function extractObservations(file,directory,gpsRange=null){
 const options=JSON.stringify({gps_range:gpsRange});
 const reader=api.reader_create(options);
 // Record the same serialized range the native Reader accepted, without caller aliases.
 const rangeSnapshot=JSON.parse(options).gps_range;
 const handle=await fs.promises.open(file,'r');let fd=null,created=false,outputBytes=0,epochs=0,records=0;
 const digest=createHash('sha256'),outputDigest=createHash('sha256');let bytes=0,lines=0,headerSaved=false;
 try{
  const before=await handle.stat();if(!before.isFile()||before.size>536870912)throw Error('regular uncompressed file <=512MiB required');
  fs.mkdirSync(directory);created=true;fd=fs.openSync(path.join(directory,'epochs.ndjson'),'wx');
  function consume(raw,hasLF){
   if(hasLF&&raw.at(-1)===13)raw=raw.subarray(0,-1);
   if(raw.length>8192||raw.some(b=>b<32||b>126))throw Error('invalid ASCII or line capacity at line '+(lines+1));
   const epoch=JSON.parse(api.reader_feed(reader,raw.toString('ascii')));lines++;
   if(!headerSaved){
    const header=JSON.parse(api.reader_header(reader));
    if(header){fs.writeFileSync(path.join(directory,'header.json'),JSON.stringify(header,null,2)+'\n',{flag:'wx'});headerSaved=true;}
   }
   if(epoch){
    const encoded=JSON.stringify(epoch)+'\n';const size=Buffer.byteLength(encoded);
    if(size>536870912-outputBytes)throw Error('NDJSON output exceeds 512MiB');
    // A low-level write can return a prefix; advance delivery totals after a full write.
    fs.writeFileSync(fd,Buffer.from(encoded));outputDigest.update(encoded);outputBytes+=size;epochs++;records+=epoch.satellites.length;
   }
  }
  let pending=Buffer.alloc(0);
  for await(const chunk of handle.createReadStream({highWaterMark:65536,autoClose:false})){
   bytes+=chunk.length;if(bytes>536870912)throw Error('input byte limit exceeded');digest.update(chunk);
   const joined=pending.length?Buffer.concat([pending,chunk]):chunk;let at=0;
   for(let i=0;i<joined.length;i++)if(joined[i]===10){consume(joined.subarray(at,i),true);at=i+1;}
   pending=Buffer.from(joined.subarray(at));if(pending.length>8193)throw Error('line capacity exceeded');
  }
  if(pending.length)consume(pending,false);
  const after=await handle.stat();if(before.size!==after.size||before.mtimeMs!==after.mtimeMs||bytes!==before.size)throw Error('input changed during read');
  const report=JSON.parse(api.reader_finish(reader));
  fs.closeSync(fd);fd=null;
  fs.writeFileSync(path.join(directory,'report.json'),JSON.stringify(report,null,2)+'\n',{flag:'wx'});
  const header=JSON.parse(fs.readFileSync(path.join(directory,'header.json'),'utf8'));
  const manifest={complete:true,inputAcceptable:report.acceptable,gpsRange:rangeSnapshot,selectedEpochs:epochs,selectedSatelliteRecords:records,
   input:{file:path.basename(file),bytes,lines,sha256:digest.digest('hex')},
   output:{bytes:outputBytes,sha256:outputDigest.digest('hex')},
   source:{license:header.parsed.license,doi:header.parsed.doi,marker:header.parsed.marker},
   semantics:{time:'100ns GPS calendar ticks since 1980-01-01; not UTC',values:'stored raw numbers; numeric zero is retained and may mean missing',
    corrections:'no scale/phase/clock corrections applied; original header retained',lines:'one-based source lines; raw strings exclude line terminators'},
   limits:['complete validates the entire file; inputAcceptable and findings remain separate','returned complete epochs are provisional until finish',
    'existing listed OBS versions, GPS time and flags 0/1 only; no positioning or full RINEX certification']};
  fs.writeFileSync(path.join(directory,'manifest.json'),JSON.stringify(manifest,null,2)+'\n',{flag:'wx'});
  return manifest;
 }catch(error){
  if(created)fs.writeFileSync(path.join(directory,'manifest.json'),JSON.stringify({complete:false,inputAcceptable:false,selectedEpochs:epochs,selectedSatelliteRecords:records,error:String(error.message??error),limits:'retained NDJSON is provisional and incomplete'},null,2)+'\n',{flag:'wx'});
  throw error;
 }finally{if(fd!==null)fs.closeSync(fd);await handle.close();}
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 try{
  const [file,directory,...ticks]=process.argv.slice(2);
  if(!file||!directory||![0,2].includes(ticks.length))throw Error('Usage: node tools/extract-observations.mjs input.rnx NEW_DIRECTORY [startGPS100ns stopGPS100ns]');
  const manifest=await extractObservations(file,directory,ticks.length?ticks:null);
  console.log(JSON.stringify(manifest));process.exitCode=manifest.inputAcceptable?0:2;
 }catch(error){console.log(JSON.stringify({complete:false,inputAcceptable:false,error:String(error.message??error)}));process.exitCode=1;}
}
