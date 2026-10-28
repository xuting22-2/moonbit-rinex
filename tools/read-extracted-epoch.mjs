import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {readExtractedEpoch} from './extracted-epoch.mjs';

if(process.argv[1]&&import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href){
  try{
    const args=process.argv.slice(2),[directory,indexText,flag]=args;
    if(![2,3].includes(args.length)||!directory||!indexText||!/^[0-9]+$/.test(indexText)||(args.length===3&&flag!=='--header'))throw Error('Usage: node tools/read-extracted-epoch.mjs DIRECTORY EPOCH_INDEX [--header]');
    const output=await readExtractedEpoch(directory,Number(indexText),{includeHeader:flag==='--header'});
    process.stdout.write(JSON.stringify(output)+'\n');
  }catch(error){
    process.stderr.write(JSON.stringify({complete:false,error:String(error.message??error)})+'\n');process.exitCode=1;
  }
}
