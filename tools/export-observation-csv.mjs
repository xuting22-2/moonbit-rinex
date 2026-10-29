import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import * as api from '../_build/js/release/build/cmd/bridge/bridge.js';

const limit=536870912;
// MoonBit owns CSV projection, counters and the unchanged Reader quality policy.
// This host only splits bounded lines and persists native output/metadata.
export async function exportObservationCsv(input,directory){
  const reader=api.csv_create(),inputHash=createHash('sha256'),outputHash=createHash('sha256');
  let handle=await fs.promises.open(input,'r'),fd=null,created=false,bytes=0,lines=0,outputBytes=0,outputLines=0,header=null;
  function json(file,value){fs.writeFileSync(path.join(directory,file),JSON.stringify(value,null,2)+'\n',{flag:'wx'});}
  function write(line){
    const encoded=Buffer.from(line+'\n','ascii');
    if(encoded.length>limit-outputBytes)throw Error('CSV output exceeds 512MiB');
    fs.writeFileSync(fd,encoded);outputHash.update(encoded);outputBytes+=encoded.length;outputLines++;
  }
  try{
    const before=await handle.stat();
    if(!before.isFile()||before.size>limit)throw Error('regular uncompressed input <=512MiB required');
    fs.mkdirSync(directory);created=true;fd=fs.openSync(path.join(directory,'observations.csv.part'),'wx');
    write(api.csv_columns());
    function feed(raw,hasLF){
      if(hasLF&&raw.at(-1)===13)raw=raw.subarray(0,-1);
      if(raw.length>8192||raw.some(b=>b<32||b>126))throw Error('invalid ASCII/line capacity at '+(lines+1));
      const rows=JSON.parse(api.csv_feed(reader,raw.toString('ascii')));lines++;
      if(!header){header=JSON.parse(api.csv_header(reader));if(header)json('header.json',header);}
      for(const row of rows)write(row);
    }
    let pending=Buffer.alloc(0);
    for await(const chunk of handle.createReadStream({highWaterMark:65536,autoClose:false})){
      bytes+=chunk.length;if(bytes>limit)throw Error('input byte limit exceeded');inputHash.update(chunk);
      const joined=pending.length?Buffer.concat([pending,chunk]):chunk;let at=0;
      for(let i=0;i<joined.length;i++)if(joined[i]===10){feed(joined.subarray(at,i),true);at=i+1;}
      pending=Buffer.from(joined.subarray(at));if(pending.length>8193)throw Error('line capacity exceeded');
    }
    if(pending.length)feed(pending,false);
    const after=await handle.stat();
    if(before.size!==after.size||before.mtimeMs!==after.mtimeMs||bytes!==before.size)throw Error('input changed during read');
    const report=JSON.parse(api.csv_finish(reader));
    await handle.close();handle=null;fs.closeSync(fd);fd=null;
    json('report.json',report);
    fs.renameSync(path.join(directory,'observations.csv.part'),path.join(directory,'observations.csv'));
    const {epochs,satellite_records,observation_rows,rows}=report;
    const manifest={schema:'raw-observation-csv-v1',complete:true,inputAcceptable:report.input_report.acceptable,
      input:{file:path.basename(input),bytes,lines,sha256:inputHash.digest('hex')},
      output:{file:'observations.csv',bytes:outputBytes,lines:outputLines,sha256:outputHash.digest('hex')},
      table:{epochs,satellite_records,observation_rows,rows},source:{license:header.parsed.license,doi:header.parsed.doi,marker:header.parsed.marker},
      semantics:{time:'Exact decimal 100ns GPST calendar ticks since1980-01-01; import as text, not UTC',
        values:'Original value_text/raw_field; blank differs from zero; zero may mean missing',
        corrections:'No scale/phase/clock corrections; original header retained',epochs:'An epoch marker exists even for zero satellites'},
      limits:['Existing modern OBS subset only; no numerical positioning or physical quality inference','Complete serialization and native input acceptance are separate','No source authentication, hostile-change snapshot, fsync or crash rollback']};
    json('manifest.json',manifest);return manifest;
  }catch(error){
    if(fd!==null){try{fs.closeSync(fd);}catch{}fd=null;}
    if(created){try{json('manifest.json',{schema:'raw-observation-csv-v1',complete:false,inputAcceptable:false,error:String(error.message??error),output:'Any retained CSV bytes are unqualified'});}catch{}}
    throw error;
  }finally{if(fd!==null)fs.closeSync(fd);if(handle)await handle.close();}
}

if(process.argv[1]&&import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href){
  try{
    const [input,directory,...extra]=process.argv.slice(2);
    if(!input||!directory||extra.length)throw Error('Usage: node tools/export-observation-csv.mjs INPUT.rnx NEW_DIRECTORY');
    const result=await exportObservationCsv(input,directory);process.stdout.write(JSON.stringify(result)+'\n');process.exitCode=result.inputAcceptable?0:2;
  }catch(error){process.stderr.write(JSON.stringify({complete:false,inputAcceptable:false,error:String(error.message??error)})+'\n');process.exitCode=1;}
}
