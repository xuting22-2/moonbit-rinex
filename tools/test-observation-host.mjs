import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {extractObservations} from './extract-observations.mjs';

const source=fileURLToPath(new URL('../examples/brux-first-two-epochs.rnx',import.meta.url));
const original=fs.readFileSync(source),lines=original.toString('ascii').trimEnd().split(/\r?\n/);
const temporary=fs.mkdtempSync(path.join(os.tmpdir(),'rinex-observation-host-'));
const firstOnly=['14745888000000000','14745888300000000'];
const json=(directory,name)=>JSON.parse(fs.readFileSync(path.join(directory,name),'utf8'));
const epochs=directory=>fs.readFileSync(path.join(directory,'epochs.ndjson'),'utf8').trim().split('\n').map(JSON.parse);
let checks=0;
async function input(name,rows,range=null){
 const file=path.join(temporary,name+'.rnx'),directory=path.join(temporary,name);
 fs.writeFileSync(file,Buffer.isBuffer(rows)?rows:rows.join('\n')+'\n');
 return {directory,run:()=>extractObservations(file,directory,range)};
}
try{
 const baseline=await input('original',original),result=await baseline.run();
 assert(result.complete);assert.equal(result.inputAcceptable,false);assert.equal(result.selectedEpochs,2);
 assert.equal(json(baseline.directory,'report.json').records,98);checks++;
 const crlf=await input('crlf',Buffer.from(lines.join('\r\n')+'\r\n'));await crlf.run();
 assert.deepEqual(epochs(crlf.directory),epochs(baseline.directory));checks++;
 const selected=await input('selected',original,firstOnly);const selection=await selected.run();
 assert.equal(selection.selectedEpochs,1);assert.equal(json(selected.directory,'report.json').epochs,2);
 assert.deepEqual(epochs(selected.directory),epochs(baseline.directory).slice(0,1));checks++;
 const second=lines.findIndex((line,i)=>i>lines.findIndex(l=>l.startsWith('>'))&&line.startsWith('>'));
 const corrupt=[...lines];corrupt[second+2]=corrupt[second+1];
 const outside=await input('invalid-outside-selection',corrupt,firstOnly);
 await assert.rejects(outside.run,/duplicate-satellite/);const partial=json(outside.directory,'manifest.json');
 assert.equal(partial.complete,false);assert.equal(partial.selectedEpochs,1);checks++;
 const truncated=await input('truncated',lines.slice(0,-1));
 await assert.rejects(truncated.run,/truncated-epoch/);assert.equal(json(truncated.directory,'manifest.json').complete,false);
 assert.equal(epochs(truncated.directory).length,1);checks++;
 const lone=await input('terminal-cr',Buffer.concat([original.subarray(0,-1),Buffer.from('\r')]));
 await assert.rejects(lone.run,/invalid ASCII/);assert.equal(json(lone.directory,'manifest.json').complete,false);checks++;
 const badTicks=await input('numeric-ticks',original,[14745888000000000,14745888300000000]);
 await assert.rejects(badTicks.run,/tick|range|exact/);assert(!fs.existsSync(badTicks.directory));checks++;
 const before=fs.readFileSync(path.join(baseline.directory,'manifest.json'));
 await assert.rejects(baseline.run,/exist/i);
 assert.deepEqual(fs.readFileSync(path.join(baseline.directory,'manifest.json')),before);checks++;
 const cli=spawnSync(process.execPath,[fileURLToPath(new URL('./extract-observations.mjs',import.meta.url)),source,path.join(temporary,'cli')],{encoding:'utf8'});
 assert.equal(cli.status,2);assert.equal(JSON.parse(cli.stdout).complete,true);checks++;
 assert.deepEqual(fs.readFileSync(source),original);
 console.log(JSON.stringify({hostIntegrationCases:checks,sourceUnchanged:true,wholeInputValidated:true,
  provisionalOutputOnFailure:true,cliUnacceptableExit:2,existingOutputPreserved:true}));
}finally{
 const real=fs.realpathSync(temporary),temp=fs.realpathSync(os.tmpdir());
 assert(!path.relative(temp,real).startsWith('..'));fs.rmSync(real,{recursive:true,force:true});
}
