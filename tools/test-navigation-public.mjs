import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import * as api from '../_build/js/release/build/cmd/bridge/bridge.js';
import {exchangeNavigationFile,inspectNavigation,evaluateNavigationRecord} from './navigation-file.mjs';

const [cache,output]=process.argv.slice(2);
if(!cache||!output)throw Error('Usage: test-navigation-public.mjs DOWNLOADED_DATA NEW_OUTPUT_DIRECTORY');
fs.mkdirSync(output);
const expected=JSON.parse(fs.readFileSync('examples/navigation-public-expected.json','utf8'));
const numeric=JSON.parse(fs.readFileSync('tools/reference/rtklib-navigation-expected.json','utf8'));
const reports=[];const python=process.env.PYTHON??(process.platform==='win32'?'python':'python3');
for(const reference of expected.files){
 const input=path.join(cache,reference.name);assert.equal(createHash('sha256').update(fs.readFileSync(input)).digest('hex'),reference.sha256);
 const directory=path.join(output,'exchange-'+reference.version);
 const receipt=await exchangeNavigationFile(input,directory);
 assert.equal(receipt.complete,true);assert.equal(receipt.allSupported,true);assert.equal(receipt.records,reference.records);assert.deepEqual({...receipt.counts},reference.counts);
 const recipient=spawnSync(python,['tools/reference/verify-navigation-exchange.py',input,directory],{encoding:'utf8'});
 assert.equal(recipient.status,0,recipient.stderr||recipient.stdout);
 const reopened=await inspectNavigation(path.join(directory,'navigation.rnx'));
 assert.deepEqual({...reopened.counts},reference.counts);assert.equal(reopened.records,reference.records);
 reports.push({version:reference.version,receipt,recipient:JSON.parse(recipient.stdout),reopenedRecords:reopened.records});
}
// Actual RTKLIB routine executions were frozen separately; no product parser
// or orbital formula produced these18 reference states.
const input=path.join(cache,expected.files[0].name),session=api.navigation_create();
let count=0,checked=0,maxMetres=0,maxClockSeconds=0;const indices=new Map();
for(const line of fs.readFileSync(input,'ascii').trimEnd().split(/\r?\n/)){
 const raw=api.navigation_feed(session,line);if(!raw)continue;count++;
 const m=JSON.parse(raw),key=[m.category,m.system,m.family].join(' ');
 const tests=numeric.results.filter(t=>t.key===key&&t.sourceFirstLine===m.first_line);
 for(const test of tests){
  const state=JSON.parse(api.navigation_evaluate(session,test.elapsedSeconds,m.family==='FNAV'?'E5a':'E1B',0,7200));
  const got=[state.x,state.y,state.z,state.clock_seconds];
  for(let i=0;i<4;i++){
   const error=Math.abs(got[i]-test.expected[i]);if(i<3)maxMetres=Math.max(maxMetres,error);else maxClockSeconds=Math.max(maxClockSeconds,error);
   assert.ok(error<=(i<3?0.0001:1e-13),JSON.stringify({key,elapsed:test.elapsedSeconds,i,error}));
  }
  checked++;indices.set(key,count);
 }
}
const end=JSON.parse(api.navigation_finish(session));assert.equal(end.records,20355);assert.equal(checked,18);
for(const [key,index] of indices){
 const test=numeric.results.find(t=>t.key===key&&t.elapsedSeconds===600);
 const result=await evaluateNavigationRecord(input,index,{elapsedSeconds:600,signal:key.endsWith('FNAV')?'E5a':'E1B'});
 assert.ok(Math.abs(result.result.x-test.expected[0])<=.0001);assert.equal(result.receipt.complete,true);
}
const result={status:'public_navigation_contract_passed',files:reports,numeric:{reference:numeric.reference,commit:numeric.commit,states:checked,maxMetres,maxClockSeconds},hostNumericQueries:indices.size};
fs.writeFileSync(path.join(output,'public-verification.json'),JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify({status:result.status,files:reports.map(r=>({version:r.version,records:r.receipt.records,fields:r.recipient.fields})),numeric:result.numeric,hostNumericQueries:indices.size,output}));
