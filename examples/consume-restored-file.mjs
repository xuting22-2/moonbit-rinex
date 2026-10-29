import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {isDeepStrictEqual} from 'node:util';
import {readPackageJson,limits} from '../tools/crinex-file-io.mjs';
import {inspectFile} from '../tools/check-file.mjs';
import {consumeFormats} from '../tools/formats.mjs';

// A real file receiver: no original CRX path, automatic mode or provisional result.
export async function consumeRestoredFile(directory,{consumer}={}){
  if(!['legacy','modern-check'].includes(consumer))throw Error('explicit legacy or modern-check consumer required');
  const manifest=await readPackageJson(path.join(directory,'manifest.json'));
  if(manifest.kind!=='native-crinex-file-v1'||manifest.complete!==true||manifest.inputReadComplete!==true||
    manifest.native_report?.complete!==true||manifest.native_report?.acceptable!==true)throw Error('restoration package is not qualified');
  const report=await readPackageJson(path.join(directory,'report.json'));
  if(!isDeepStrictEqual(manifest.native_report,report))throw Error('stored native restoration reports disagree');
  const output=manifest.output;
  if(output?.file!=='restored.rnx'||output.identityVerified!==true||!Number.isSafeInteger(output.bytes)||output.bytes<0||output.bytes>limits.bytes||
    typeof output.sha256!=='string'||!/^[0-9a-f]{64}$/.test(output.sha256))throw Error('invalid restored output identity');
  const file=path.join(directory,'restored.rnx');
  const downstream=consumer==='modern-check'?await inspectFile(file):
    await consumeFormats('legacy',file,()=>{},{includeInputIdentity:true});
  if(downstream.input.bytes!==output.bytes||downstream.input.sha256!==output.sha256)throw Error('consumer read does not match restored output identity');
  return {delivery:{qualified:true,native_report:report,reported_input:manifest.input,
      verified_output:{bytes:downstream.input.bytes,sha256:downstream.input.sha256}},
    downstream:{consumer,report:downstream,semantics:consumer==='legacy'?'legacy grammar completion; no GNSS quality judgment':'native OBS completion and quality remain separate'}};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href){
  try{
    const [directory,flag,consumer,...extra]=process.argv.slice(2);
    if(!directory||flag!=='--consumer'||extra.length)throw Error('Usage: node examples/consume-restored-file.mjs DIRECTORY --consumer legacy|modern-check');
    const result=await consumeRestoredFile(directory,{consumer});
    process.stdout.write(JSON.stringify(result)+'\n');process.exitCode=result.downstream.report.complete===false||result.downstream.report.acceptable===false?2:0;
  }catch(error){process.stderr.write(JSON.stringify({complete:false,error:String(error.message??error)})+'\n');process.exitCode=1;}
}
