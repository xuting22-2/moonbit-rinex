"""Fetch a pinned public CEDA observation fixture into a new external directory.

The data is fetched for reference checking; it is not included in this package.
"""
from pathlib import Path
import argparse,gzip,hashlib,json,urllib.request
COMMIT='8d1210a0f1ada71ff7b8d0484cfaf22ff154a38e'
NAME='CEDA00USA_R_20182100000_23H_15S_MO.rnx'
URL='https://raw.githubusercontent.com/geospace-code/georinex/'+COMMIT+'/src/georinex/tests/data/'+NAME+'.gz'
COMPRESSED_SHA256='781d445832492015533e3b7aaac435568d80da26f38b3528fb1a07f2a451556b'
PLAIN_SHA256='2563103ee2803a16f81c068658b6c7a210dd379f53327ff79b7de29afb034ee9'

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('directory',type=Path);args=p.parse_args()
    if args.directory.exists():raise ValueError('Choose a new directory; existing files are preserved')
    with urllib.request.urlopen(URL,timeout=60) as response:compressed=response.read(8*1024*1024+1)
    if len(compressed)>8*1024*1024 or hashlib.sha256(compressed).hexdigest()!=COMPRESSED_SHA256:raise ValueError('Reference archive hash mismatch')
    data=gzip.decompress(compressed)
    if hashlib.sha256(data).hexdigest()!=PLAIN_SHA256:raise ValueError('Decompressed reference hash mismatch')
    args.directory.mkdir(parents=True)
    (args.directory/NAME).write_bytes(data)
    (args.directory/'SOURCE.json').write_text(json.dumps({'url':URL,'commit':COMMIT,'compressedSha256':COMPRESSED_SHA256,'sha256':PLAIN_SHA256,'transformation':'gzip decompression only; no header edits','redistributedByProduct':False},indent=2)+'\n',encoding='utf-8')
    print(args.directory/NAME)

if __name__=='__main__':main()
