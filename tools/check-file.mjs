import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import * as api from '../_build/js/release/build/cmd/bridge/bridge.js';
export async function inspectFile(file,profile=null){
 const handle=await fs.promises.open(file,'r');
 try{
  const before=await handle.stat();if(!before.isFile()||before.size>536870912)throw Error('regular uncompressed file <=512MiB required');
  if(profile&&(!Array.isArray(profile)||profile.length!==4||profile.some(v=>!Number.isSafeInteger(v)||v<-1||v>2147483647)||profile[0]===0))throw Error('profile must be exact [year,month,day,hour]; hour=-1 for daily');
  const checker=api.create(...(profile??[0,0,0,-1])),hash=createHash('sha256');
  let pending=Buffer.alloc(0),bytes=0,lines=0;
  for await(const chunk of handle.createReadStream({highWaterMark:65536,autoClose:false})){
   bytes+=chunk.length;if(bytes>536870912)throw Error('input byte limit exceeded');hash.update(chunk);
   const data=pending.length?Buffer.concat([pending,chunk]):chunk;let start=0;
   for(let i=0;i<data.length;i++)if(data[i]===10){
    let line=data.subarray(start,i);if(line.at(-1)===13)line=line.subarray(0,-1);
    if(line.length>8192||line.some(b=>b<32||b>126))throw Error('invalid ASCII or line capacity at line '+(lines+1));
    api.feed(checker,line.toString('ascii'));lines++;start=i+1;
   }
   pending=Buffer.from(data.subarray(start));if(pending.length>8193)throw Error('line capacity exceeded');
  }
  if(pending.length){if(pending.length>8192||pending.some(b=>b<32||b>126))throw Error('invalid terminal ASCII line');api.feed(checker,pending.toString('ascii'));lines++;}
  const after=await handle.stat();if(before.size!==after.size||before.mtimeMs!==after.mtimeMs||bytes!==before.size)throw Error('input changed during read');
  return {...JSON.parse(api.finish(checker)),input:{bytes,lines,sha256:hash.digest('hex')},limits:'bounded OBS subset; not full RINEX/EPN certification; no numerical positioning'};
 }finally{await handle.close();}
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 try{
  const [file,...args]=process.argv.slice(2);if(!file||![0,4].includes(args.length))throw Error('Usage: node tools/check-file.mjs input.rnx [year month day hour|-1]');
  if(args.some(s=>!/^(-1|[0-9]+)$/.test(s)))throw Error('profile arguments must be decimal integers');
  const report=await inspectFile(file,args.length?args.map(Number):null);console.log(JSON.stringify(report,null,2));process.exitCode=report.acceptable?0:2;
 }catch(e){console.log(JSON.stringify({complete:false,acceptable:false,error:String(e.message??e)}));process.exitCode=1;}
}
