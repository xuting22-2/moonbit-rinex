import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const buildRoot = await fs.promises.realpath(path.join(root, '_build'));
const retained = !!process.argv[2];
const directory = retained ? path.resolve(process.argv[2]) :
  await fs.promises.mkdtemp(path.join(buildRoot, 'empty-epoch-chain-'));
if (retained) await fs.promises.mkdir(directory);
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const json = async file => JSON.parse(await fs.promises.readFile(file, 'utf8'));
const names = ['manifest.json', 'report.json', 'header.json', 'epochs.ndjson'];
async function identity(artifact) {
  return Object.fromEntries(await Promise.all(names.map(async name => {
    const bytes = await fs.promises.readFile(path.join(artifact, name));
    return [name, {bytes: bytes.length, sha256: sha(bytes)}];
  })));
}

// Serialized into a child preload containing only Node builtins. Observe real
// CLI file IO, without replacing parsing, quality decisions or navigation.
async function instrumentIO() {
  const fs = (await import('node:fs')).default;
  const path = (await import('node:path')).default;
  const config = JSON.parse(process.env.RINEX_EMPTY_EPOCH_AUDIT);
  const open = fs.promises.open;
  const trace = {opened: 0, closed: 0, originalObservationOpens: 0,
    navigationOpens: 0, outputBytesRead: 0, outputEnded: false,
    outputCompletedBeforeNav: null, outputBytesBeforeNav: 0};
  fs.promises.open = async function(file, ...args) {
    const absolute = path.resolve(String(file));
    if (config.originalFiles.includes(absolute)) trace.originalObservationOpens++;
    if (absolute === config.navFile) {
      trace.navigationOpens++;
      trace.outputCompletedBeforeNav = trace.outputEnded;
      trace.outputBytesBeforeNav = trace.outputBytesRead;
    }
    const handle = await open.call(this, file, ...args);
    trace.opened++;
    const close = handle.close.bind(handle);
    let closed = false;
    handle.close = async function() {
      try { return await close(); }
      finally { if (!closed) { closed = true; trace.closed++; } }
    };
    if (absolute === config.outputFile) {
      const stream = handle.createReadStream.bind(handle);
      handle.createReadStream = options => (async function*() {
        for await (const chunk of stream(options)) {
          trace.outputBytesRead += chunk.length;
          yield chunk;
        }
        trace.outputEnded = true;
      })();
    }
    return handle;
  };
  process.on('exit', () => fs.writeFileSync(config.traceFile, JSON.stringify(trace) + '\n'));
}

const input = path.join(directory, 'empty.rnx');
const badInput = path.join(directory, 'declared-one.rnx');
const nav = path.join(root, 'examples/catalog-synthetic.nav');
const preloader = path.join(directory, 'observe-io.mjs');
const cli = [];
const traces = {};
function run(label, module, args, exit, artifact = null) {
  const env = {...process.env};
  delete env.RINEX_EMPTY_EPOCH_AUDIT;
  const argv = [];
  const traceFile = path.join(directory, label + '.trace.json');
  if (artifact) {
    env.RINEX_EMPTY_EPOCH_AUDIT = JSON.stringify({traceFile, navFile: nav,
      outputFile: path.join(artifact, 'epochs.ndjson'), originalFiles: [input, badInput]});
    argv.push('--import', pathToFileURL(preloader).href);
  }
  argv.push(module, ...args);
  const proc = spawnSync(process.execPath, argv, {cwd: directory, env,
    encoding: 'utf8', timeout: 20000});
  assert.ifError(proc.error);
  fs.writeFileSync(path.join(directory, label + '.stdout.log'), proc.stdout);
  fs.writeFileSync(path.join(directory, label + '.stderr.log'), proc.stderr);
  assert.equal(proc.status, exit, proc.stderr || proc.stdout);
  if (artifact) {
    traces[label] = JSON.parse(fs.readFileSync(traceFile, 'utf8'));
    assert.equal(traces[label].opened, traces[label].closed);
    assert.equal(traces[label].originalObservationOpens, 0);
  }
  cli.push({name: label, exit: proc.status, stdoutEmpty: proc.stdout === ''});
  return proc;
}
function rejected(proc, pattern) {
  assert.equal(proc.stdout, '');
  const error = JSON.parse(proc.stderr);
  assert.equal(error.complete, false);
  assert.match(error.error, pattern);
}

try {
  // Fixed-column synthetic OBS. The day count was independently calculated by
  // Python datetime(2026,10,25)-datetime(1980,1,1), without this library.
  const ticks = '14773968000000001';
  assert.equal(((17099n * 86400n + 43200n) * 10000000n + 1n).toString(), ticks);
  assert(BigInt(ticks) > 9007199254740992n);
  const record = (body, label) => {
    assert(body.length <= 60 && label.length <= 20);
    return body.padEnd(60) + label;
  };
  const first = [2026, 10, 25, 12, 0].map(n => String(n).padStart(6)).join('') +
    '0.0000001'.padStart(13) + 'GPS'.padStart(8);
  const header = [
    record('     3.05           OBSERVATION DATA    G', 'RINEX VERSION / TYPE'),
    record('SYNTHETIC EMPTY EPOCH CHAIN', 'MARKER NAME'),
    record('G    1 C1C', 'SYS / # / OBS TYPES'),
    record(first, 'TIME OF FIRST OBS'),
    record('    30.000', 'INTERVAL'),
    record('MIT; fully synthetic', 'LICENSE OF USE'),
    record('', 'END OF HEADER'),
  ];
  const epochLine = '> 2026 10 25 12 00 00.0000001  0  0';
  assert.equal(epochLine.length, 35);
  assert.equal(epochLine.slice(31, 32), '0');
  assert.equal(epochLine.slice(32, 35), '  0');
  const expectedEpoch = {gps_ticks: ticks, flag: 0, line: 8, end_line: 8,
    raw_record: epochLine, receiver_clock: null, receiver_clock_raw: '', satellites: []};
  const inputBytes = Buffer.from(header.concat(epochLine).join('\n') + '\n', 'ascii');
  assert.equal(sha(inputBytes), '5d4bf26cc7bb11a222c05ae16039553143d5c3483d71474b953fb1f764898db7');
  fs.writeFileSync(input, inputBytes, {flag: 'wx'});
  fs.writeFileSync(preloader, 'await (' + instrumentIO.toString() + ')();\n', {flag: 'wx'});
  const navBytes = await fs.promises.readFile(nav);
  assert.deepEqual(navBytes.toString('ascii').split('\n').filter(line => /^[GC]\d\d /.test(line))
    .map(line => line.slice(0, 3)), ['G01', 'G01', 'G01', 'C01', 'C06']);

  const artifact = path.join(directory, 'artifact');
  const extraction = run('extract', path.join(root, 'tools/extract-observations.mjs'), [input, artifact], 0);
  assert.equal(extraction.stderr, '');
  const manifest = JSON.parse(extraction.stdout);
  const report = await json(path.join(artifact, 'report.json'));
  assert.equal(manifest.complete, true);
  assert.equal(manifest.inputAcceptable, true);
  assert.equal(manifest.selectedEpochs, 1);
  assert.equal(manifest.selectedSatelliteRecords, 0);
  assert.deepEqual(manifest.input, {file: 'empty.rnx', bytes: inputBytes.length, lines: 8, sha256: sha(inputBytes)});
  assert.equal(report.complete, true);
  assert.equal(report.acceptable, true);
  assert.equal(report.epochs, 1);
  assert.equal(report.records, 0);
  assert.equal(report.first, ticks);
  assert.equal(report.last, ticks);
  const warning = report.findings.find(item => item.code === 'empty-epoch');
  assert(warning);
  assert.equal(warning.line, 8);
  assert.equal(warning.error, false);
  const output = await fs.promises.readFile(path.join(artifact, 'epochs.ndjson'));
  assert.equal(output.length, Buffer.byteLength(JSON.stringify(expectedEpoch) + '\n'));
  assert.equal(output.toString().split('\n').length, 2);
  assert.deepEqual(JSON.parse(output.toString()), expectedEpoch);
  assert.deepEqual(manifest.output, {bytes: output.length, sha256: sha(output)});
  const before = await identity(artifact);

  // A physically separate reader/CLI pair has neither a NAV file nor a bridge.
  const standaloneRoot = path.join(directory, 'standalone');
  const standalone = path.join(standaloneRoot, 'tools');
  await fs.promises.mkdir(standalone, {recursive: true});
  for (const name of ['extracted-epoch.mjs', 'read-extracted-epoch.mjs']) {
    await fs.promises.copyFile(path.join(root, 'tools', name), path.join(standalone, name));
  }
  assert.deepEqual(await fs.promises.readdir(standaloneRoot), ['tools']);
  assert.deepEqual((await fs.promises.readdir(standalone)).sort(), ['extracted-epoch.mjs', 'read-extracted-epoch.mjs']);
  const rawCli = path.join(standalone, 'read-extracted-epoch.mjs');
  const plain = run('standalone-read', rawCli, [artifact, '1'], 0, artifact);
  assert.equal(plain.stderr, '');
  const read = JSON.parse(plain.stdout);
  assert.deepEqual(read.epoch, expectedEpoch);
  assert.equal(read.observation.native_report.acceptable, true);
  assert.deepEqual(read.observation.native_report.findings, report.findings);
  assert.deepEqual(read.observation.verified_output, {...manifest.output, epochs: 1});
  assert.deepEqual(read.observation.source, {license: 'MIT; fully synthetic', doi: '', marker: 'SYNTHETIC EMPTY EPOCH CHAIN'});
  assert.equal(traces['standalone-read'].navigationOpens, 0);
  assert.equal(traces['standalone-read'].outputBytesRead, output.length);
  assert.equal(traces['standalone-read'].outputEnded, true);

  const queryCli = path.join(root, 'tools/query-extracted-epoch.mjs');
  const query = run('query', queryCli, [artifact, nav, '1', 'G99'], 2, artifact);
  assert.equal(query.stderr, '');
  const result = JSON.parse(query.stdout);
  assert.deepEqual(result.observation, read.observation);
  assert.equal(result.observation.selected_epoch.gps_ticks, ticks);
  assert.equal(result.results.length, 1);
  assert.equal(result.results[0].result.status, 'unavailable');
  assert.equal(result.results[0].result.report.satellite, 'G99');
  assert.deepEqual(result.results[0].result.report.at, {gps_ticks: ticks});
  assert.equal(result.results[0].result.report.candidates, 0);
  assert.equal(result.results[0].result.report.eligible, 0);
  for (const [key, value] of Object.entries({complete: true, stored_records: 5, queries: 1,
    selected: 0, unavailable: 1, ambiguous: 0, all_selected: false})) assert.equal(result.receipt[key], value);
  assert.equal(traces.query.navigationOpens, 1);
  assert.equal(traces.query.outputCompletedBeforeNav, true);
  assert.equal(traces.query.outputBytesBeforeNav, output.length);

  // A syntactically readable header/body disagreement remains unacceptable.
  // It is a separate input, not a patched native report or rewritten good head.
  const badBytes = Buffer.from(header.slice(0, -1)
    .concat(record('     1', '# OF SATELLITES'), header.at(-1), epochLine).join('\n') + '\n', 'ascii');
  fs.writeFileSync(badInput, badBytes, {flag: 'wx'});
  const badArtifact = path.join(directory, 'declared-one-artifact');
  const badExtraction = run('quality-extract', path.join(root, 'tools/extract-observations.mjs'), [badInput, badArtifact], 2);
  const badManifest = JSON.parse(badExtraction.stdout);
  const badReport = await json(path.join(badArtifact, 'report.json'));
  assert.equal(badManifest.complete, true);
  assert.equal(badManifest.inputAcceptable, false);
  assert.equal(badManifest.selectedEpochs, 1);
  assert.equal(badManifest.selectedSatelliteRecords, 0);
  assert.equal(badReport.complete, true);
  assert.equal(badReport.acceptable, false);
  assert.equal(badReport.records, 0);
  assert.deepEqual(JSON.parse(await fs.promises.readFile(path.join(badArtifact, 'epochs.ndjson'), 'utf8')),
    {...expectedEpoch, line: 9, end_line: 9});
  assert(badReport.findings.some(item => item.code === 'header-satellite-total' && item.error && item.line === 7));
  assert(badReport.findings.some(item => item.code === 'empty-epoch' && !item.error && item.line === 9));
  const badBefore = await identity(badArtifact);
  rejected(run('quality-read', rawCli, [badArtifact, '1'], 1, badArtifact), /manifest must be complete and acceptable/);
  rejected(run('quality-query', queryCli, [badArtifact, nav, '1', 'G99'], 1, badArtifact),
    /manifest must be complete and acceptable/);
  for (const label of ['quality-read', 'quality-query']) {
    assert.equal(traces[label].navigationOpens, 0);
    assert.equal(traces[label].outputBytesRead, 0);
  }

  const corrupt = path.join(directory, 'same-length-corruption');
  await fs.promises.cp(artifact, corrupt, {recursive: true});
  const changed = Buffer.from(output);
  const at = changed.indexOf(ticks);
  assert(at >= 0);
  changed[at + ticks.length - 1] = 51;
  assert.equal(changed.length, output.length);
  fs.writeFileSync(path.join(corrupt, 'epochs.ndjson'), changed);
  rejected(run('corrupt-query', queryCli, [corrupt, nav, '1', 'G99'], 1, corrupt), /SHA256 mismatch/);
  assert.equal(traces['corrupt-query'].navigationOpens, 0);
  assert.equal(traces['corrupt-query'].outputEnded, true);
  assert.equal(traces['corrupt-query'].outputBytesRead, output.length);
  assert.equal(Object.values(traces).reduce((n, trace) => n + trace.navigationOpens, 0), 1);
  assert.deepEqual(await identity(artifact), before);
  assert.deepEqual(await identity(badArtifact), badBefore);
  assert.equal(sha(await fs.promises.readFile(input)), sha(inputBytes));
  assert.equal(sha(await fs.promises.readFile(badInput)), sha(badBytes));
  assert.equal(sha(await fs.promises.readFile(nav)), sha(navBytes));
  const receipt = {status: 'passed',scenarios: 3,extractionInvocations: 2,
    expectedEpoch,selectedEpochs: 1,selectedSatelliteRecords: 0,outputBytes: output.length,
    emptyEpochWarningPreserved: true,independentStandaloneRead: true,
    navigationLoadsAcrossAllConsumers: 1,qualityFailurePreserved: true,
    sameLengthCorruptionRejectedBeforeNav: true,artifactsAndInputsUnchanged: true,
    cli,traces,identities: before,originalObservationOpensDuringConsumers: 0};
  fs.writeFileSync(path.join(directory, 'RESULT.json'), JSON.stringify(receipt, null, 2) + '\n');
  console.log(JSON.stringify(receipt));
} finally {
  if (!retained) {
    const actual = await fs.promises.realpath(directory);
    const relative = path.relative(buildRoot, actual);
    assert(relative && !path.isAbsolute(relative) && relative !== '..' && !relative.startsWith('..' + path.sep));
    await fs.promises.rm(actual, {recursive: true, force: true});
  }
}
