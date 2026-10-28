import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {queryNavigationBatch} from './nav-query.mjs';
import {readExtractedEpoch} from './extracted-epoch.mjs';

export async function queryExtractedEpoch(directory,navFile,epochIndex,satellites,{orbit=0,maxAge=7200,capacity=4096,skip=false}={}){
  if(!Number.isInteger(epochIndex)||epochIndex<1||epochIndex>1000000)throw Error('epoch index must be in 1..1000000');
  if(!Array.isArray(satellites)||satellites.length<1||satellites.length>256||satellites.some(value=>typeof value!=='string'))throw Error('1..256 satellite strings required');
  // Snapshot arguments; artifact checks only honor stored native decisions and
  // verify IO identity. Native batch code retains time/model/result semantics.
  const requested=Array.from(satellites);
  const {epoch,observation}=await readExtractedEpoch(directory,epochIndex);
  const batch=await queryNavigationBatch(navFile,requested.map(satellite=>({satellite,gps_ticks:epoch.gps_ticks,orbit,maxAge})),{capacity,skip});
  return {observation,...batch};
}

const usage='Usage: node tools/query-extracted-epoch.mjs DIRECTORY NAV_FILE EPOCH_INDEX SATELLITE... [--skip-unsupported] [--capacity N] [--max-age SECONDS] [--geo|--meo-igso]';
if(process.argv[1]&&import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href){
  try{
    const [directory,navFile,indexText,...args]=process.argv.slice(2),satellites=[],options={},seen=new Set();
    if(!directory||!navFile||!indexText||!/^[0-9]+$/.test(indexText))throw Error(usage);
    for(let at=0;at<args.length;at++){
      const token=args[at];if(!token.startsWith('--')){satellites.push(token);continue;}
      if(seen.has(token))throw Error('duplicate option '+token);seen.add(token);
      if(token==='--skip-unsupported')options.skip=true;
      else if(token==='--geo'||token==='--meo-igso'){
        if(options.orbit)throw Error('conflicting orbit options');options.orbit=token==='--geo'?1:2;
      }else if(token==='--capacity'||token==='--max-age'){
        const value=args[++at];if(value===undefined||!/^([0-9]+(\.[0-9]*)?|\.[0-9]+)$/.test(value))throw Error('numeric option value required');
        if(token==='--capacity')options.capacity=Number(value);else options.maxAge=Number(value);
      }else throw Error('unknown option '+token);
    }
    const output=await queryExtractedEpoch(directory,navFile,Number(indexText),satellites,options);
    process.stdout.write(JSON.stringify(output)+'\n');
    process.exitCode=output.receipt.all_selected?0:2;
  }catch(error){
    process.stderr.write(JSON.stringify({complete:false,error:String(error.message??error)})+'\n');process.exitCode=1;
  }
}
