import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import {inspectFile} from './check-file.mjs';
const source=new URL('../examples/brux-first-two-epochs.rnx',import.meta.url);
const original=await fs.readFile(source),lines=original.toString('ascii').trimEnd().split(/\r?\n/);
const dir=await fs.mkdtemp(path.join(os.tmpdir(),'moonbit-rinex-contract-'));
let checks=0;
async function run(name,rows,expected){
 const file=path.join(dir,name+'.rnx');await fs.writeFile(file,Buffer.isBuffer(rows)?rows:rows.join('\n')+'\n');
 if(typeof expected==='string'){await assert.rejects(inspectFile(file,[2026,9,23,-1]),e=>String(e).includes(expected));}
 else await expected(await inspectFile(file,[2026,9,23,-1]));checks++;
}
try{
 const epochIndices=lines.map((l,i)=>l.startsWith('>')?i:-1).filter(i=>i>=0),[first,second]=epochIndices;
 await run('original',lines,r=>{assert(r.complete);assert(!r.acceptable);assert.equal(r.epochs,2);assert.equal(r.records,98);assert(r.finding_counts['profile-last']);});
 await run('truncated',lines.slice(0,-1),'truncated-epoch');
 let changed=[...lines];changed[first+2]=changed[first+1];await run('duplicate-sv',changed,'duplicate-satellite');
 changed=[...lines];changed.push(lines.at(-1));await run('extra-record',changed,'unexpected-observation');
 changed=[...lines];changed[first]=changed[first].slice(0,31)+'6'+changed[first].slice(32);await run('event6',changed,'unsupported-event');
 changed=[...lines];changed[first+1]=changed[first+1].slice(0,3)+'           NaN'+changed[first+1].slice(17);await run('nan',changed,'observation-number');
 changed=[...lines];changed[first+1]=changed[first+1].padEnd(3+24*16)+'         1.000  ';await run('extra-fields',changed,'extra-observation-fields');
 changed=[...lines];changed[second]=changed[first];await run('duplicate-epoch',changed,r=>assert.equal(r.finding_counts['epoch-order'],1));
 changed=[...lines];changed[second]=changed[second].slice(0,18)+' 30.0000001'+changed[second].slice(29);await run('one-tick-off-lattice',changed,r=>{assert.equal(r.finding_counts['profile-lattice'],1);assert.equal(r.finding_counts['epoch-interval'],1);});
 changed=[...lines];changed[first]=changed[first].padEnd(41)+' 0.000000000001';await run('clock-undeclared',changed,r=>{assert.equal(r.receiver_clock_epochs,1);assert.equal(r.finding_counts['clock-header-missing'],1);});
 await run('crlf',Buffer.from(lines.join('\r\n')+'\r\n'),r=>assert.equal(r.records,98));
 await run('invalid-byte',Buffer.concat([original,Buffer.from([255,10])]),'invalid ASCII');
 await run('long-line',Buffer.from('X'.repeat(9000)+'\n'),'line capacity');
 await assert.rejects(inspectFile(source,[2026.5,9,23,-1]),/exact/);checks++;
 await assert.rejects(inspectFile(dir),/regular/);checks++;
 assert.deepEqual(await fs.readFile(source),original);
 console.log(JSON.stringify({publicPrefixCases:checks,sourceUnchanged:true,noPartialSuccess:true,includes:'exact 100ns lattice, duplicate/truncated records, unsupported event, invalid number, clock metadata, host byte/type/capacity errors'}));
}finally{const real=await fs.realpath(dir),temp=await fs.realpath(os.tmpdir());assert(!path.relative(temp,real).startsWith('..'));await fs.rm(real,{recursive:true,force:true});}
