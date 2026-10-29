import fs from 'node:fs';
import {createHash} from 'node:crypto';

// Host IO for this delivery package only; no RINEX or quality interpretation.
export const limits=Object.freeze({bytes:536870912,metadata:1048576});
async function readRegular(file,limit,consume){
  const handle=await fs.promises.open(file,'r');
  try{
    const before=await handle.stat();
    if(!before.isFile()||before.size>limit)throw Error('regular package file within byte limit required');
    let bytes=0;
    for await(const chunk of handle.createReadStream({highWaterMark:65536,autoClose:false})){
      bytes+=chunk.length;if(bytes>limit)throw Error('package file byte limit');consume(chunk);
    }
    const after=await handle.stat();
    if(bytes!==before.size||before.size!==after.size||before.mtimeMs!==after.mtimeMs)throw Error('package file changed during read');
    return bytes;
  }finally{await handle.close();}
}
export async function fileIdentity(file){
  const hash=createHash('sha256');let lines=0,last=-1;
  const bytes=await readRegular(file,limits.bytes,chunk=>{
    hash.update(chunk);last=chunk.at(-1);
    for(let at=chunk.indexOf(10);at>=0;at=chunk.indexOf(10,at+1))lines++;
  });
  if(bytes&&last!==10)lines++;
  return {bytes,lines,sha256:hash.digest('hex')};
}
export async function readPackageJson(file){
  const chunks=[];await readRegular(file,limits.metadata,chunk=>chunks.push(chunk));
  return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(Buffer.concat(chunks)));
}
export function writeAll(fd,buffer){
  for(let at=0;at<buffer.length;){
    const count=fs.writeSync(fd,buffer,at,buffer.length-at,null);
    if(!Number.isInteger(count)||count<1||count>buffer.length-at)throw Error('invalid package write progress');
    at+=count;
  }
}
export function writePackageJson(file,value){
  const bytes=Buffer.from(JSON.stringify(value,null,2)+'\n');
  if(bytes.length>limits.metadata)throw Error('package metadata exceeds 1MiB');
  const fd=fs.openSync(file,'wx');
  try{writeAll(fd,bytes);}finally{fs.closeSync(fd);}
}
