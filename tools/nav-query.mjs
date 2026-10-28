import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import * as api from '../_build/js/release/build/cmd/bridge/bridge.js';

// Host: arguments, bounded byte/line IO and final output only. MoonBit owns the
// catalog, normalized time, candidate evaluation, ranking and diagnostics.
const scope='GPS/BDS broadcast query within declared reader/model/selection policy; skipped unsupported records are not validated';
function normalizeQuery(options) {
  const {satellite, week, sow, bdt=false, orbit=0, maxAge=7200}=options;
  if(typeof satellite!=='string'||!Number.isInteger(week)||!Number.isFinite(sow)||
    typeof bdt!=='boolean'||!Number.isInteger(orbit)||!Number.isFinite(maxAge))throw Error('invalid query argument types');
  return {satellite,week,sow,bdt,orbit,maxAge};
}
function validateStorage(capacity,skip) {
  if(!Number.isInteger(capacity)||typeof skip!=='boolean')throw Error('invalid query argument types');
}
function evaluate(session,{satellite,week,sow,bdt,orbit,maxAge}) {
  return JSON.parse(api.nav_catalog_query(session,satellite,week,sow,bdt,orbit,maxAge));
}
async function withNavigation(file,capacity,skip,consume) {
  const session=api.nav_catalog_create(capacity,skip);
  const handle=await fs.promises.open(file,'r');
  let bytes=0,lines=0,pending=Buffer.alloc(0);
  try {
    const before=await handle.stat();
    if(!before.isFile()||before.size>536870912)throw Error('regular input <=512MiB required');
    const feed=(raw,hasLF)=>{
      if(hasLF&&raw.at(-1)===13)raw=raw.subarray(0,-1);
      if(raw.length>8192||raw.some(b=>b<32||b>126))throw Error('ASCII/line limit at '+(lines+1));
      api.nav_catalog_feed(session,raw.toString('ascii'));lines++;
    };
    for await(const chunk of handle.createReadStream({highWaterMark:65536,autoClose:false})){
      bytes+=chunk.length;if(bytes>536870912)throw Error('input limit');
      const joined=pending.length?Buffer.concat([pending,chunk]):chunk;let at=0;
      for(let i=0;i<joined.length;i++)if(joined[i]===10){feed(joined.subarray(at,i),true);at=i+1;}
      pending=Buffer.from(joined.subarray(at));if(pending.length>8193)throw Error('line limit');
    }
    if(pending.length)feed(pending,false);
    const after=await handle.stat();
    if(before.size!==after.size||before.mtimeMs!==after.mtimeMs||bytes!==before.size)throw Error('input changed');
    const load=JSON.parse(api.nav_catalog_finish(session));
    return consume(session,{...load,lines,bytes,scope});
  } finally {await handle.close();}
}

export async function queryNavigation(file, options) {
  const query=normalizeQuery(options),{capacity=4096,skip=false}=options;
  validateStorage(capacity,skip);
  return withNavigation(file,capacity,skip,(session,load)=>{
    const result=evaluate(session,query);
    return {result,receipt:{...load,query_status:result.status}};
  });
}

// A bounded, ordered snapshot; no result escapes if any native query fails.
export async function queryNavigationBatch(file, requests, {capacity=4096,skip=false}={}) {
  if(!Array.isArray(requests)||requests.length<1||requests.length>256)throw Error('batch requires 1..256 queries');
  validateStorage(capacity,skip);
  const allowed=new Set(['satellite','week','sow','bdt','gps_ticks','orbit','maxAge']);
  const queries=Array.from(requests,(request,index)=>{
    try {
      if(!request||typeof request!=='object'||Array.isArray(request))throw Error('query object required');
      for(const key of Object.keys(request))if(!allowed.has(key))throw Error('unknown query field '+key);
      if(Object.hasOwn(request,'gps_ticks')){
        if(['week','sow','bdt'].some(key=>Object.hasOwn(request,key)))throw Error('gps_ticks cannot be combined with week/sow/bdt');
        const {satellite,gps_ticks,orbit=0,maxAge=7200}=request;
        if(typeof satellite!=='string'||typeof gps_ticks!=='string'||!Number.isInteger(orbit)||!Number.isFinite(maxAge))throw Error('gps_ticks requires a string and valid query argument types');
        return {satellite,gps_ticks,orbit,maxAge};
      }
      return normalizeQuery(request);
    } catch(error) {throw Error('query '+(index+1)+': '+String(error.message??error));}
  });
  return withNavigation(file,capacity,skip,(session,load)=>{
    const {results,summary}=JSON.parse(api.nav_catalog_query_batch(session,JSON.stringify(queries)));
    return {results,receipt:{...load,query_status:'batch',...summary}};
  });
}

const usage='Usage: node tools/nav-query.mjs INPUT SATELLITE WEEK SOW [--bdt] [--geo|--meo-igso] [--max-age SECONDS] [--capacity N] [--skip-unsupported]';
if(process.argv[1]&&import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href){
  try {
    const [file,satellite,weekText,sowText,...flags]=process.argv.slice(2);
    if(!file||!satellite||weekText===undefined||sowText===undefined||
      !/^[0-9]+$/.test(weekText)||!/^([0-9]+(\.[0-9]*)?|\.[0-9]+)$/.test(sowText))throw Error(usage);
    const options={satellite,week:Number(weekText),sow:Number(sowText)},seen=new Set();
    for(let i=0;i<flags.length;i++){
      const flag=flags[i];if(seen.has(flag))throw Error('duplicate option '+flag);seen.add(flag);
      if(flag==='--bdt')options.bdt=true;
      else if(flag==='--geo'||flag==='--meo-igso'){
        if(options.orbit)throw Error('conflicting orbit options');options.orbit=flag==='--geo'?1:2;
      }else if(flag==='--skip-unsupported')options.skip=true;
      else if(flag==='--max-age'||flag==='--capacity'){
        const value=flags[++i];
        if(value===undefined||!/^([0-9]+(\.[0-9]*)?|\.[0-9]+)$/.test(value))throw Error('numeric value required for '+flag);
        if(flag==='--capacity')options.capacity=Number(value);else options.maxAge=Number(value);
      }else throw Error('unknown option '+flag);
    }
    const {result,receipt}=await queryNavigation(file,options);
    process.stdout.write(JSON.stringify(result)+'\n');process.stderr.write(JSON.stringify(receipt)+'\n');
    process.exitCode=result.status==='selected'?0:2;
  } catch(error) {
    process.stderr.write(JSON.stringify({complete:false,query_status:'failed',error:String(error.message??error)})+'\n');process.exitCode=1;
  }
}
