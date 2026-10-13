const fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'../..'),windows=path.join(root,'Windows');
fs.cpSync(path.join(root,'Sources/PlazaCore'),path.join(windows,'Engine/Sources/PlazaCore'),{recursive:true});
fs.cpSync(path.join(root,'Sources/MacPlaza/Resources/FFL'),path.join(windows,'src/ffl'),{recursive:true});
// Adapter and renderer stay byte-identical to the Mac implementation. This
// tiny host bridge runs before plaza.js, replacing only WebKit's message port.
fs.writeFileSync(path.join(windows,'src/ffl/electron-host.js'),`window.webkit={messageHandlers:{ffl:{postMessage:message=>parent.postMessage({plazaFFL:message},'*')}}};`);
const index=path.join(windows,'src/ffl/index.html');let html=fs.readFileSync(index,'utf8');html=html.replace('<script src="vendor/three.min.js">','<script src="electron-host.js"></script><script src="vendor/three.min.js">');
fs.writeFileSync(index,html);
console.log('Prepared unchanged Mac crowd sources and renderer assets.');
