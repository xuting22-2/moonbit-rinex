import fs from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {inspectFile} from '../tools/check-file.mjs';

async function metadata(file){const stat=await fs.stat(file);if(!stat.isFile()||stat.size>1048576)throw Error('clip metadata regular file <=1MiB required');const raw=await fs.readFile(file);if(raw.length>1048576)throw Error('clip metadata limit');return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(raw));}
export async function consumeClippedObservations(directory){
  const manifest=await metadata(path.join(directory,'manifest.json'));
  if(manifest.schema!=='native-observation-clip-v1'||manifest.complete!==true||manifest.inputAcceptable!==true||manifest.qualified!==true||manifest.status!=='written'||manifest.output?.file!=='clipped.rnx')throw Error('clip package must be complete and qualified');
  const report=await metadata(path.join(directory,'report.json')),saved=await metadata(path.join(directory,'output-report.json')),source=await metadata(path.join(directory,'source-header.json'));
  if(report.input_report.complete!==true||report.input_report.acceptable!==true||JSON.stringify(report.input_report.header)!==JSON.stringify(source.parsed))throw Error('original source completion/quality/header mismatch');
  if(JSON.stringify(report.gps_range)!==JSON.stringify(manifest.gpsRange)||report.selected_epochs!==manifest.selectedEpochs||report.selected_satellite_records!==manifest.selectedSatelliteRecords)throw Error('native selection mismatch');
  for(const key of ['marker','license','doi'])if(manifest.source?.[key]!==source.parsed[key])throw Error('source context mismatch');
  const actual=await inspectFile(path.join(directory,'clipped.rnx'));
  if(actual.complete!==true||actual.acceptable!==true||JSON.stringify(actual)!==JSON.stringify(saved))throw Error('actual clipped read differs from saved native report');
  for(const key of ['bytes','lines','sha256'])if(actual.input[key]!==manifest.output[key])throw Error('actual clipped read identity mismatch');
  if(actual.epochs!==report.selected_epochs||actual.records!==report.selected_satellite_records||actual.first!==report.first_gps_ticks||actual.last!==report.last_gps_ticks)throw Error('actual clipped selection mismatch');
  return {complete:true,qualified:true,gpsRange:report.gps_range,input_report:report.input_report,output_report:actual,source:manifest.source};
}

if(process.argv[1]&&import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href){
  try{const [directory,...extra]=process.argv.slice(2);if(!directory||extra.length)throw Error('Usage: node examples/consume-clipped-observations.mjs DIRECTORY');const result=await consumeClippedObservations(directory);process.stdout.write(JSON.stringify(result)+'\n');}
  catch(error){process.stderr.write(JSON.stringify({complete:false,qualified:false,error:String(error.message??error)})+'\n');process.exitCode=1;}
}
