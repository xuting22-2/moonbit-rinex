import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {queryNavigationBatch} from '../tools/nav-query.mjs';

const input=fileURLToPath(new URL('./catalog-synthetic.nav',import.meta.url));
const requests=JSON.parse(await fs.readFile(new URL('./catalog-queries.json',import.meta.url),'utf8'));
const batch=await queryNavigationBatch(input,requests);
assert.deepEqual(batch.results.map(item=>item.result.status),['selected','selected','unavailable','unavailable']);
assert.deepEqual(batch.results.map(item=>item.query_index),[1,2,3,4]);
assert.equal(batch.results[0].result.selection.record.record_index,3);
assert.equal(batch.results[1].result.selection.record.record_index,5);
assert.equal(batch.receipt.queries,4);
assert.equal(batch.receipt.stored_records,5);
console.log(JSON.stringify(batch));
