import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import * as api from '../_build/js/release/build/cmd/bridge/bridge.js';
import {inspectFile} from './check-file.mjs';

const limit=536870912;
export async function clipObservationFile(input,directory,gpsRange){
  const clipper=api.clip_create(JSON.stringify(gpsRange));
  let handle=await fs.promises.open(input,'r'),bodyFd=null,created=false,bytes=0,lines=0,bodyBytes=0,bodyLines=0,sourceHeader=null;
  const inputHash=createHash('sha256'),bodyHash=createHash('sha256');
  function json(name,value){const encoded=Buffer.from(JSON.stringify(value,null,2)+'\n');if(encoded.length>1048576)throw Error('clip metadata exceeds1MiB');fs.writeFileSync(path.join(directory,name),encoded,{flag:'wx'});}
  try{
    const before=await handle.stat();if(!before.isFile()||before.size>limit)throw Error('regular modern OBS input <=512MiB required');
    fs.mkdirSync(directory);created=true;const bodyFile=path.join(directory,'body.rnx.part');bodyFd=fs.openSync(bodyFile,'wx');
    function feed(raw,hasLF){
      if(hasLF&&raw.at(-1)===13)raw=raw.subarray(0,-1);
      if(raw.length>8192||raw.some(b=>b<32||b>126))throw Error('invalid ASCII/line capacity at '+(lines+1));
      const rows=JSON.parse(api.clip_feed(clipper,raw.toString('ascii')));lines++;
      if(!sourceHeader){sourceHeader=JSON.parse(api.clip_header(clipper));if(sourceHeader)json('source-header.json',sourceHeader);}
      for(const row of rows){const encoded=Buffer.from(row+'\n','ascii');if(encoded.length>limit-bodyBytes)throw Error('clip body output exceeds512MiB');fs.writeFileSync(bodyFd,encoded);bodyHash.update(encoded);bodyBytes+=encoded.length;bodyLines++;}
    }
    let pending=Buffer.alloc(0);
    for await(const chunk of handle.createReadStream({highWaterMark:65536,autoClose:false})){
      bytes+=chunk.length;if(bytes>limit)throw Error('input limit');inputHash.update(chunk);
      const joined=pending.length?Buffer.concat([pending,chunk]):chunk;let at=0;
      for(let i=0;i<joined.length;i++)if(joined[i]===10){feed(joined.subarray(at,i),true);at=i+1;}
      pending=Buffer.from(joined.subarray(at));if(pending.length>8193)throw Error('line limit');
    }
    if(pending.length)feed(pending,false);
    const after=await handle.stat();if(before.size!==after.size||before.mtimeMs!==after.mtimeMs||bytes!==before.size)throw Error('input changed during read');
    const report=JSON.parse(api.clip_finish(clipper));await handle.close();handle=null;fs.closeSync(bodyFd);bodyFd=null;
    json('report.json',report);
    if(bodyLines!==report.selected_epochs+report.selected_satellite_records)throw Error('native/body line count mismatch');
    const bodyIdentity={bytes:bodyBytes,lines:bodyLines,sha256:bodyHash.digest('hex')};
    const status=!report.input_report.acceptable?'input-unacceptable':report.selected_epochs===0?'empty':'written';
    let output=null;
    if(status==='written'){
      if(!Array.isArray(report.output_header))throw Error('missing native clipped header');
      const part=path.join(directory,'clipped.rnx.part'),fd=fs.openSync(part,'wx'),writtenHash=createHash('sha256'),copiedBodyHash=createHash('sha256');let written=0,copied=0;
      const write=encoded=>{if(encoded.length>limit-written)throw Error('clipped RINEX output exceeds512MiB');fs.writeFileSync(fd,encoded);writtenHash.update(encoded);written+=encoded.length;};
      try{
        for(const line of report.output_header)write(Buffer.from(line+'\n','ascii'));
        const source=fs.openSync(bodyFile,'r');
        try{const buffer=Buffer.alloc(65536);for(;;){const n=fs.readSync(source,buffer,0,buffer.length,null);if(!n)break;const chunk=buffer.subarray(0,n);write(chunk);copiedBodyHash.update(chunk);copied+=n;}}
        finally{fs.closeSync(source);}
      }finally{fs.closeSync(fd);}
      if(copied!==bodyBytes||copiedBodyHash.digest('hex')!==bodyIdentity.sha256)throw Error('body readback identity mismatch');
      const expectedSHA=writtenHash.digest('hex'),file=path.join(directory,'clipped.rnx');fs.renameSync(part,file);
      const actual=await inspectFile(file);
      if(actual.complete!==true||actual.acceptable!==true)throw Error('actual clipped RINEX native quality failed');
      if(actual.input.bytes!==written||actual.input.sha256!==expectedSHA||actual.input.lines!==report.output_header.length+bodyLines)throw Error('actual clipped RINEX readback identity mismatch');
      if(actual.epochs!==report.selected_epochs||actual.records!==report.selected_satellite_records||actual.first!==report.first_gps_ticks||actual.last!==report.last_gps_ticks)throw Error('actual clipped RINEX selection mismatch');
      json('output-report.json',actual);output={file:'clipped.rnx',...actual.input};
    }
    const manifest={schema:'native-observation-clip-v1',complete:true,inputAcceptable:report.input_report.acceptable,qualified:status==='written',status,
      gpsRange:report.gps_range,selectedEpochs:report.selected_epochs,selectedSatelliteRecords:report.selected_satellite_records,
      firstGPS:report.first_gps_ticks,lastGPS:report.last_gps_ticks,omittedSummaryLines:report.omitted_summary_lines,
      input:{file:path.basename(input),bytes,lines,sha256:inputHash.digest('hex')},body:bodyIdentity,output,
      source:{marker:sourceHeader.parsed.marker,license:sourceHeader.parsed.license,doi:sourceHeader.parsed.doi},
      semantics:'Original selected raw measurement/clock/flag text, LF separators; only known extent headers adapted and optional file totals omitted; no extra corrections',
      limits:['Whole source quality must be acceptable; a selected clean window cannot promote a bad source','Actual final RNX is reopened by the existing checker before qualification','Other metadata is copied uninterpreted; no source authentication or crash transaction']};
    json('manifest.json',manifest);return manifest;
  }catch(error){
    if(bodyFd!==null){try{fs.closeSync(bodyFd);}catch{}bodyFd=null;}
    if(created){try{json('manifest.json',{schema:'native-observation-clip-v1',complete:false,inputAcceptable:false,qualified:false,error:String(error.message??error),limits:'Retained body/RNX is unqualified'});}catch{}}
    throw error;
  }finally{if(bodyFd!==null)fs.closeSync(bodyFd);if(handle)await handle.close();}
}

if(process.argv[1]&&import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href){
  try{
    const [input,directory,start,stop,...extra]=process.argv.slice(2);
    if(!input||!directory||start===undefined||stop===undefined||extra.length)throw Error('Usage: node tools/clip-observations.mjs INPUT.rnx NEW_DIRECTORY START_GPS100ns STOP_GPS100ns');
    const manifest=await clipObservationFile(input,directory,[start,stop]);process.stdout.write(JSON.stringify(manifest)+'\n');process.exitCode=manifest.qualified?0:2;
  }catch(error){process.stderr.write(JSON.stringify({complete:false,qualified:false,error:String(error.message??error)})+'\n');process.exitCode=1;}
}
