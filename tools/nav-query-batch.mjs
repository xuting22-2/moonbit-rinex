import fs from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {queryNavigationBatch} from './nav-query.mjs';

async function readQueries(file) {
  const handle=await fs.open(file,'r'),limit=1048576;
  try {
    const before=await handle.stat();
    if(!before.isFile()||before.size>limit)throw Error('regular query JSON <=1MiB required');
    const chunks=[];let bytes=0;
    for await(const chunk of handle.createReadStream({highWaterMark:65536,autoClose:false})){
      bytes+=chunk.length;if(bytes>limit)throw Error('query JSON limit');chunks.push(chunk);
    }
    const after=await handle.stat();
    if(before.size!==after.size||before.mtimeMs!==after.mtimeMs||bytes!==before.size)throw Error('query JSON changed');
    return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(Buffer.concat(chunks)));
  } finally {await handle.close();}
}

const usage='Usage: node tools/nav-query-batch.mjs INPUT REQUESTS.json [--capacity N] [--skip-unsupported]';
if(process.argv[1]&&import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href){
  try {
    const [file,queryFile,...flags]=process.argv.slice(2),options={},seen=new Set();
    if(!file||!queryFile)throw Error(usage);
    for(let index=0;index<flags.length;index++){
      const flag=flags[index];if(seen.has(flag))throw Error('duplicate option '+flag);seen.add(flag);
      if(flag==='--skip-unsupported')options.skip=true;
      else if(flag==='--capacity'){
        const text=flags[++index];if(text===undefined||!/^[0-9]+$/.test(text))throw Error('integer capacity required');
        options.capacity=Number(text);
      }else throw Error('unknown option '+flag);
    }
    const {results,receipt}=await queryNavigationBatch(file,await readQueries(queryFile),options);
    process.stdout.write(JSON.stringify({results})+'\n');
    process.stderr.write(JSON.stringify(receipt)+'\n');
    process.exitCode=receipt.all_selected?0:2;
  } catch(error) {
    process.stderr.write(JSON.stringify({complete:false,query_status:'failed',error:String(error.message??error)})+'\n');
    process.exitCode=1;
  }
}
