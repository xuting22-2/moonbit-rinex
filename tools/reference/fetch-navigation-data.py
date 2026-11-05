"""Anonymous IGS/DLR download, not redistributed under the product MIT license.

Montenbruck & Steigenberger, DLR/GSOC, DOI10.57677/BRD400DLR.
https://igs.org/mgex/mgex-product-descriptions/
"""
from pathlib import Path
import gzip,hashlib,json,sys,urllib.request

FILES={
 '4':('BRD400DLR_S_20250010000_01D_MN.rnx.gz','01e71f9007b89c042c046f01a1d9b122dccdd2a0e1a7afd3f824a7dbe8fc3c9e'),
 '3':('BRDM00DLR_S_20250010000_01D_MN.rnx.gz','bdea0a662783633473bd47201bc6c99048eed157e19276c8215f333047632ab2'),
}
def fetch(directory):
    root=Path(directory);root.mkdir(parents=True,exist_ok=True);receipts=[]
    for name,expected in FILES.values():
        dest=root/name;url='https://igs.bkg.bund.de/root_ftp/IGS/BRDC/2025/001/'+name
        if not dest.exists():
            req=urllib.request.Request(url,headers={'User-Agent':'moonbit-rinex-reference/1.0'})
            with urllib.request.urlopen(req,timeout=90) as r:b=r.read(8*1024*1024+1)
            if len(b)>8*1024*1024:raise ValueError('reference download8MiB bound')
            dest.write_bytes(b)
        b=dest.read_bytes();actual=hashlib.sha256(b).hexdigest()
        if actual!=expected:raise ValueError('publisher data changed; preserve input and investigate checksum mismatch')
        decoded=gzip.decompress(b)
        if len(decoded)>32*1024*1024:raise ValueError('reference decompressed32MiB bound')
        output=dest.with_suffix('');output.write_bytes(decoded)
        receipts.append({'url':url,'file':str(output),'compressedSha256':actual,'sha256':hashlib.sha256(decoded).hexdigest(),'bytes':len(decoded),'version':decoded[:9].decode('ascii').strip(),'attribution':'Montenbruck, O.; Steigenberger, P. (DLR/GSOC); IGS/BKG distribution','license':'No redistribution license asserted; not included in MIT source package'})
    (root/'download-receipt.json').write_text(json.dumps(receipts,indent=2)+'\n');return receipts
if __name__=='__main__':
    if len(sys.argv)!=2:raise SystemExit('Usage: fetch-navigation-data.py TASK_LOCAL_CACHE')
    print(json.dumps(fetch(sys.argv[1])))
