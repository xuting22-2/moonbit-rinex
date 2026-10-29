import fs from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {queryNavigation,queryNavigationWithSource} from '../tools/nav-query.mjs';

// A real file recipient: keep the native-selected original text, then reopen
// the new one-record NAV through the existing parser and query API.
export async function replaySelectedNavigation(input,replayFile,options) {
  const query={...options};
  const original=await queryNavigationWithSource(input,query);
  if(original.result.status!=='selected')return {complete:true,original,replay:null};
  const {header_lines,record_lines}=original.source;
  const file=await fs.open(replayFile,'wx');
  try {await file.writeFile(Buffer.from([...header_lines,...record_lines].join('\n')+'\n','ascii'));}
  finally {await file.close();}
  const replay=await queryNavigation(replayFile,query);
  if(replay.result.status!=='selected')throw Error('replay did not select the captured record');
  const before=original.result.selection,after=replay.result.selection;
  for(const key of ['satellite','message','toc','toe','health']){
    if(JSON.stringify(before.record[key])!==JSON.stringify(after.record[key]))throw Error('replay record mismatch: '+key);
  }
  if(JSON.stringify(before.state)!==JSON.stringify(after.state))throw Error('replay state mismatch');
  return {complete:true,original,replay:{file:path.resolve(replayFile),...replay},lineSeparators:'LF'};
}

if(process.argv[1]&&import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href){
  try {
    const [input,replayFile,queryFile,...rest]=process.argv.slice(2);
    if(!input||!replayFile||!queryFile||rest.length)throw Error('Usage: node examples/nav-source-replay.mjs INPUT NEW_REPLAY.nav QUERY.json');
    const stat=await fs.stat(queryFile);
    if(!stat.isFile()||stat.size>1048576)throw Error('query JSON regular file <=1MiB required');
    const bytes=await fs.readFile(queryFile);if(bytes.length>1048576)throw Error('query JSON limit');
    const options=JSON.parse(bytes.toString('utf8'));
    if(!options||typeof options!=='object'||Array.isArray(options))throw Error('query object required');
    const output=await replaySelectedNavigation(input,replayFile,options);
    process.stdout.write(JSON.stringify(output)+'\n');
    process.exitCode=output.replay?0:2;
  }catch(error){
    process.stderr.write(JSON.stringify({complete:false,error:String(error.message??error)})+'\n');process.exitCode=1;
  }
}
