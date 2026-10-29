import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {extractGzipObservations} from './extract-observations.mjs';

export {extractGzipObservations};
if(process.argv[1]&&import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href){
 try{
  const [file,directory,...ticks]=process.argv.slice(2);
  if(!file||!directory||![0,2].includes(ticks.length))throw Error('Usage: node tools/extract-gzip-observations.mjs INPUT.rnx.gz NEW_DIRECTORY [startGPS100ns stopGPS100ns]');
  const manifest=await extractGzipObservations(file,directory,ticks.length?ticks:null);
  process.stdout.write(JSON.stringify(manifest)+'\n');process.exitCode=manifest.inputAcceptable?0:2;
 }catch(error){
  process.stderr.write(JSON.stringify({complete:false,inputAcceptable:false,error:String(error.message??error),code:error.code??null})+'\n');process.exitCode=1;
 }
}
