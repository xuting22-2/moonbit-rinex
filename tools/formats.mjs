import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import * as api from '../_build/js/release/build/cmd/bridge/bridge.js';

// Only bounded byte/line IO is performed here. All format states and numbers
// are interpreted by MoonBit. Output remains provisional until finish succeeds.
export async function consumeFormats(mode,file,emit,options={}){
 const handle=await fs.promises.open(file,'r');
 const before=await handle.stat();
 if(!before.isFile()||before.size>536870912){await handle.close();throw Error('regular input <=512MiB required');}
 const state=mode==='crx'?api.crx_create(options.recover===true):
  mode==='legacy'?api.legacy_create():mode==='nav'?api.nav_create(options.skip===true):null;
 if(state===null){await handle.close();throw Error('mode must be crx, legacy or nav');}
 let pending=Buffer.alloc(0),bytes=0,lines=0;
 const feed=(raw,hasLF)=>{
  if(hasLF&&raw.at(-1)===13)raw=raw.subarray(0,-1);
  if(raw.length>8192||raw.some(b=>b<32||b>126))throw Error('ASCII/line limit at '+(lines+1));
  lines++;
  const line=raw.toString('ascii');
  if(mode==='crx'){
   for(const out of JSON.parse(api.crx_feed(state,line)))emit(out+'\n');
  }else{
   const item=JSON.parse(mode==='legacy'?api.legacy_feed(state,line):api.nav_feed(state,line,options.orbit??0));
   if(item!==null)emit(JSON.stringify(item)+'\n');
  }
 };
 try{
  for await(const chunk of handle.createReadStream({highWaterMark:65536,autoClose:false})){
   bytes+=chunk.length;if(bytes>536870912)throw Error('input limit');
   const data=pending.length?Buffer.concat([pending,chunk]):chunk;let at=0;
   for(let i=0;i<data.length;i++)if(data[i]===10){feed(data.subarray(at,i),true);at=i+1;}
   pending=Buffer.from(data.subarray(at));if(pending.length>8193)throw Error('line limit');
  }
  if(pending.length)feed(pending,false);
  const after=await handle.stat();
  if(before.size!==after.size||before.mtimeMs!==after.mtimeMs||bytes!==before.size)throw Error('input changed');
  const report=JSON.parse(mode==='crx'?api.crx_finish(state):mode==='legacy'?api.legacy_finish(state):api.nav_finish(state));
  return {mode,lines,bytes,...report};
 }finally{await handle.close();}
}
if(process.argv[1]&&import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href){
 const [mode,file,...flags]=process.argv.slice(2);
 try{
  if(!file)throw Error('Usage: node tools/formats.mjs crx|legacy|nav INPUT [--recover] [--skip-unsupported] [--geo|--meo-igso]');
  if(flags.some(f=>!['--recover','--skip-unsupported','--geo','--meo-igso'].includes(f))||
   (flags.includes('--geo')&&flags.includes('--meo-igso')))throw Error('invalid options');
  const report=await consumeFormats(mode,file,s=>process.stdout.write(s),{
   recover:flags.includes('--recover'),skip:flags.includes('--skip-unsupported'),
   orbit:flags.includes('--geo')?1:flags.includes('--meo-igso')?2:0});
  process.stderr.write(JSON.stringify(report)+'\n');
  process.exitCode=report.acceptable===false||report.complete===false?2:0;
 }catch(e){process.stderr.write(JSON.stringify({complete:false,acceptable:false,error:String(e.message??e)})+'\n');process.exitCode=1;}
}
