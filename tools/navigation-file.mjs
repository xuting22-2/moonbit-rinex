import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import * as api from '../_build/js/release/build/cmd/bridge/bridge.js';

const inputLimit=536870912,outputLimit=1073741824;
// Host owns byte IO only. MoonBit owns framing, schemas, epochs, constellation
// interpretation, health, models and errors. Nothing is qualified before EOF.
async function scan(file,consume=()=>{}) {
  const session=api.navigation_create(),handle=await fs.promises.open(file,'r');
  const hash=createHash('sha256'),counts=Object.create(null);let bytes=0,lines=0,index=0,pending=Buffer.alloc(0);
  const record=m=>{
    index++;
    const key=[m.category,m.system,m.family,m.subtype].filter(Boolean).join(' ');
    if(!Object.hasOwn(counts,key)&&Object.keys(counts).length>=4096)throw Error('navigation summary key limit4096');
    counts[key]=(counts[key]??0)+1;
    consume(m,index,session);
  };
  try {
    const before=await handle.stat();if(!before.isFile()||before.size>inputLimit)throw Error('regular NAV input <=512MiB required');
    const feed=(raw,lf)=>{
      if(lf&&raw.at(-1)===13)raw=raw.subarray(0,-1);
      if(raw.length>80||raw.some(b=>b<32||b>126))throw Error('NAV ASCII/80-column limit at '+(lines+1));
      const out=api.navigation_feed(session,raw.toString('ascii'));lines++;
      if(out)record(JSON.parse(out));
    };
    for await(const chunk of handle.createReadStream({highWaterMark:65536,autoClose:false})){
      bytes+=chunk.length;if(bytes>inputLimit)throw Error('NAV input limit');hash.update(chunk);
      const joined=pending.length?Buffer.concat([pending,chunk]):chunk;let at=0;
      for(let i=0;i<joined.length;i++)if(joined[i]===10){feed(joined.subarray(at,i),true);at=i+1;}
      pending=Buffer.from(joined.subarray(at));if(pending.length>81)throw Error('NAV line limit');
    }
    if(pending.length)feed(pending,false);
    const after=await handle.stat();if(before.size!==after.size||before.mtimeMs!==after.mtimeMs||bytes!==before.size)throw Error('NAV input changed');
    const end=JSON.parse(api.navigation_finish(session));if(end.final_record)record(end.final_record);
    if(index!==end.records)throw Error('native NAV record count mismatch');
    return {schema:'native-navigation-v1',complete:true,allSupported:end.all_supported,
      records:end.records,unsupportedRecords:end.unsupported_records,counts,headerLines:end.header_lines,
      input:{bytes,lines,sha256:hash.digest('hex')},
      semantics:'Typed native RINEX NAV; exact raw line text and spare/blank fields retained; no implicit time-scale conversion'};
  }finally{await handle.close();}
}

export async function inspectNavigation(file){return scan(file);}

// Explicit one-based physical record selection, not a best-ephemeris catalog.
// The file is fully parsed and finished before returning the selected result.
export async function evaluateNavigationRecord(file,index,{elapsedSeconds=0,signal='',orbit=0,maxAge=7200}={}){
  if(!Number.isInteger(index)||index<1||typeof signal!=='string'||!Number.isFinite(elapsedSeconds)||!Number.isInteger(orbit)||!Number.isFinite(maxAge))throw Error('invalid navigation evaluation arguments');
  let result=null,source=null;
  const receipt=await scan(file,(m,n,session)=>{if(n===index){result=JSON.parse(api.navigation_evaluate(session,elapsedSeconds,signal,orbit,maxAge));source={firstLine:m.first_line,lastLine:m.last_line,satellite:m.satellite,family:m.family,epoch:m.epoch};}});
  if(!source)throw Error('navigation record index outside file');
  return {recordIndex:index,source,result,receipt};
}

export async function exchangeNavigationFile(file,directory){
  let created=false,rnx=null,ndjson=null,rnxBytes=0,jsonBytes=0,headerWritten=false;
  const rnxHash=createHash('sha256'),jsonHash=createHash('sha256');
  const write=(fd,b,kind)=>{
    if(kind==='rnx'){if(b.length>inputLimit-rnxBytes)throw Error('NAV RINEX output512MiB limit');rnxBytes+=b.length;rnxHash.update(b);}
    else{if(b.length>outputLimit-jsonBytes)throw Error('NAV NDJSON output1GiB limit');jsonBytes+=b.length;jsonHash.update(b);}
    fs.writeFileSync(fd,b);
  };
  const writeHeader=header=>{if(!headerWritten){for(const line of header)write(rnx,Buffer.from(line+'\n','ascii'),'rnx');headerWritten=true;}};
  const manifest=value=>fs.writeFileSync(path.join(directory,'manifest.json'),JSON.stringify(value,null,2)+'\n',{flag:'wx'});
  try{
    fs.mkdirSync(directory);created=true;
    rnx=fs.openSync(path.join(directory,'navigation.rnx.part'),'wx');ndjson=fs.openSync(path.join(directory,'messages.ndjson.part'),'wx');
    const receipt=await scan(file,(m,_,session)=>{
      writeHeader(JSON.parse(api.navigation_header(session)));
      for(const line of m.raw_lines)write(rnx,Buffer.from(line+'\n','ascii'),'rnx');
      write(ndjson,Buffer.from(JSON.stringify(m)+'\n'),'json');
    });
    writeHeader(receipt.headerLines);
    fs.closeSync(rnx);rnx=null;fs.closeSync(ndjson);ndjson=null;
    const output={rnx:{file:'navigation.rnx',bytes:rnxBytes,sha256:rnxHash.digest('hex')},ndjson:{file:'messages.ndjson',bytes:jsonBytes,sha256:jsonHash.digest('hex')}};
    fs.renameSync(path.join(directory,'navigation.rnx.part'),path.join(directory,output.rnx.file));
    fs.renameSync(path.join(directory,'messages.ndjson.part'),path.join(directory,output.ndjson.file));
    const value={...receipt,qualified:receipt.allSupported,output,
      exchange:'Same version and all header/record line text. LF separators, including final LF. Opaque records retained. Not source authentication or orbital validation.'};
    manifest(value);return value;
  }catch(error){
    if(created){try{manifest({schema:'native-navigation-v1',complete:false,qualified:false,error:String(error.message??error),retained:'Parts are unqualified; no completed receipt'});}catch{}}
    throw error;
  }finally{if(rnx!==null)fs.closeSync(rnx);if(ndjson!==null)fs.closeSync(ndjson);}
}

if(process.argv[1]&&import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href){
  try{
    const [command,file,...args]=process.argv.slice(2);let result;
    if(command==='inspect'&&file&&args.length===0)result=await inspectNavigation(file);
    else if(command==='exchange'&&file&&args.length===1)result=await exchangeNavigationFile(file,args[0]);
    else if(command==='evaluate'&&file&&args.length>=2&&args.length<=3)result=await evaluateNavigationRecord(file,Number(args[0]),{elapsedSeconds:Number(args[1]),signal:args[2]??''});
    else throw Error('Usage: navigation-file.mjs inspect INPUT | exchange INPUT NEW_DIRECTORY | evaluate INPUT RECORD_INDEX ELAPSED_SI_SECONDS [GALILEO_SIGNAL]');
    process.stdout.write(JSON.stringify(result)+'\n');process.exitCode=result.allSupported===false||result.receipt?.allSupported===false?2:0;
  }catch(error){process.stderr.write(JSON.stringify({complete:false,qualified:false,error:String(error.message??error)})+'\n');process.exitCode=1;}
}
