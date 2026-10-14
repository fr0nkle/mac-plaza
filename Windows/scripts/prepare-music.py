"""Reuse the Miiverse recording already distributed in the pinned Mac release."""
import hashlib,io,pathlib,urllib.request,zipfile
url='https://github.com/fr0nkle/mac-plaza/releases/download/v0.20.2/Mac-Plaza-0.20.2.zip'
with urllib.request.urlopen(url,timeout=120) as response:data=response.read(50*1024*1024)
if hashlib.sha256(data).hexdigest()!='a50d42d243ea683cafa59e89d01becffb61564736a940ba6e6877b3ec78ea794':raise ValueError('Mac soundtrack source checksum mismatch')
folder=pathlib.Path(__file__).resolve().parents[1]/'native/runtime/Audio';folder.mkdir(parents=True,exist_ok=True)
with zipfile.ZipFile(io.BytesIO(data)) as archive:
    recording=archive.read('Mac Plaza.app/Contents/Resources/Audio/miiverse.m4a')
    if len(recording)!=1760963:raise ValueError('Unexpected Miiverse recording size')
    (folder/'miiverse.m4a').write_bytes(recording)
(folder/'SOURCE.txt').write_text('Miiverse recording reused unchanged from Mac Plaza 0.20.2. Separate soundtrack rights apply; excluded from corresponding source.\nSource: '+url+'\nSHA256: '+hashlib.sha256(recording).hexdigest()+'\n')
