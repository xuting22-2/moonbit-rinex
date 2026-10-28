import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {readExtractedEpochs} from './extracted-epoch.mjs';

if(process.argv[1]&&import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href){
  try{
    const args=process.argv.slice(2),[directory,startText,countText,flag]=args;
    if(![3,4].includes(args.length)||!directory||!startText||!countText||
      !/^[0-9]+$/.test(startText)||!/^[0-9]+$/.test(countText)||(args.length===4&&flag!=='--header')){
      throw Error('Usage: node tools/read-extracted-epochs.mjs DIRECTORY START COUNT [--header]');
    }
    const output=await readExtractedEpochs(directory,Number(startText),Number(countText),{includeHeader:flag==='--header'});
    process.stdout.write(JSON.stringify(output)+'\n');
  }catch(error){
    process.stderr.write(JSON.stringify({complete:false,error:String(error.message??error)})+'\n');
    process.exitCode=1;
  }
}
