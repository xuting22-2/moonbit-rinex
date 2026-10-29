import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {consumeFormats} from './formats.mjs';
import {limits,fileIdentity,writeAll,writePackageJson} from './crinex-file-io.mjs';

export async function restoreCrinexFile(inputPath,newDirectory,{recover=false}={}){
  if(typeof inputPath!=='string'||!inputPath||typeof newDirectory!=='string'||!newDirectory)throw Error('input and new directory paths required');
  if(typeof recover!=='boolean')throw Error('recover must be boolean');
  const part=path.join(newDirectory,'restored.rnx.part'),final=path.join(newDirectory,'restored.rnx');
  let created=false,fd=null,nativeReport=null,input=null,inputReadComplete=false,outputBytes=0;
  const digest=createHash('sha256');
  const manifest=(complete,output,error)=>({kind:'native-crinex-file-v1',complete,inputReadComplete,options:{recover},
    input:input?{file:path.basename(inputPath),...input}:{file:path.basename(inputPath),identityVerified:false},
    output,native_report:nativeReport,
    semantics:{output:'native restored ASCII lines with LF',qualification:'only the final complete manifest qualifies this package',
      restoration:'native lossless restoration, not downstream OBS quality or source authentication'},
    ...(error?{error}:{} )});
  try{
    fs.mkdirSync(newDirectory);created=true;fd=fs.openSync(part,'wx');
    const loaded=await consumeFormats('crx',inputPath,text=>{
      const bytes=Buffer.from(text,'utf8');
      if(bytes.length>limits.bytes-outputBytes)throw Error('restored output exceeds 512MiB');
      writeAll(fd,bytes);digest.update(bytes);outputBytes+=bytes.length;
    },{recover,includeInputIdentity:true});
    const {mode,lines,bytes,input:verified,...native}=loaded;
    input=verified;inputReadComplete=true;nativeReport=native;
    fs.closeSync(fd);fd=null;
    const actual=await fileIdentity(part);
    if(actual.bytes!==outputBytes||actual.sha256!==digest.digest('hex'))throw Error('restored output readback identity mismatch');
    const qualified=native.complete===true&&native.acceptable===true;
    writePackageJson(path.join(newDirectory,'report.json'),native);
    if(qualified)fs.renameSync(part,final);
    const result=manifest(qualified,{file:qualified?'restored.rnx':'restored.rnx.part',...actual,identityVerified:true});
    // The final manifest is the qualification marker. Renamed RNX alone is not success.
    const pending=path.join(newDirectory,'manifest.json.part');
    writePackageJson(pending,result);fs.renameSync(pending,path.join(newDirectory,'manifest.json'));
    return result;
  }catch(error){
    if(error.inputReadComplete===true){inputReadComplete=true;input=error.verifiedInput;}
    if(fd!==null){try{fs.closeSync(fd);}catch{}fd=null;}
    if(created){
      const file=fs.existsSync(final)?final:part;
      let actual=null;try{actual={file:path.basename(file),...await fileIdentity(file),identityVerified:true};}catch{}
      const failure=manifest(false,actual,String(error.message??error));
      // Best effort only: metadata IO can fail too. Never overwrite a final marker.
      try{writePackageJson(path.join(newDirectory,'manifest.json'),failure);}catch{}
    }
    throw error;
  }finally{if(fd!==null)try{fs.closeSync(fd);}catch{}}
}

if(process.argv[1]&&import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href){
  try{
    const args=process.argv.slice(2),[input,directory,flag]=args;
    if(![2,3].includes(args.length)||(args.length===3&&flag!=='--recover'))throw Error('Usage: node tools/restore-crinex.mjs INPUT.crx NEW_DIRECTORY [--recover]');
    const result=await restoreCrinexFile(input,directory,{recover:flag==='--recover'});
    process.stdout.write(JSON.stringify(result)+'\n');process.exitCode=result.complete?0:2;
  }catch(error){
    process.stderr.write(JSON.stringify({complete:false,error:String(error.message??error)})+'\n');process.exitCode=1;
  }
}
