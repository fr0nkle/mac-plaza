const fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'../..'),windows=path.join(root,'Windows');
fs.cpSync(path.join(root,'Sources/PlazaCore'),path.join(windows,'Engine/Sources/PlazaCore'),{recursive:true});
fs.cpSync(path.join(root,'Tests/PlazaCoreTests'),path.join(windows,'Engine/Tests/PlazaCoreTests'),{recursive:true});
fs.cpSync(path.join(root,'Sources/MacPlaza/Resources/FFL'),path.join(windows,'src/ffl'),{recursive:true});
// Adapter and renderer stay byte-identical to the Mac implementation. This
// tiny host bridge runs before plaza.js, replacing only WebKit's message port.
fs.writeFileSync(path.join(windows,'src/ffl/electron-host.js'),`window.webkit={messageHandlers:{ffl:{postMessage:message=>parent.postMessage({plazaFFL:message},'*')}}};\nfor(const name of ['pointerdown','pointermove','pointerup','pointercancel','wheel'])document.addEventListener(name,event=>{parent.postMessage({plazaInput:{name,x:event.clientX,y:event.clientY,pointerId:event.pointerId,buttons:event.buttons,deltaY:event.deltaY,ctrlKey:event.ctrlKey,metaKey:event.metaKey}},'*');if(name==='pointerdown')event.target.setPointerCapture?.(event.pointerId);if(name==='wheel'&&(event.ctrlKey||event.metaKey))event.preventDefault();},{passive:false});`);
fs.copyFileSync(path.join(windows,'src/fallback-renderer.js'),path.join(windows,'src/ffl/fallback-renderer.js'));
const index=path.join(windows,'src/ffl/index.html');let html=fs.readFileSync(index,'utf8');html=html.replace('<script src="vendor/three.min.js">','<script src="electron-host.js"></script><script src="fallback-renderer.js"></script><script src="vendor/three.min.js">');
fs.writeFileSync(index,html);
const adapter=path.join(windows,'src/ffl/plaza.js');let js=fs.readFileSync(adapter,'utf8');
js=js.replace('  ffl=await FFLjs.FFL.initWithResource','  if(!resource){ffl=null;resize();send("ready",true);return;}\n  ffl=await FFLjs.FFL.initWithResource');
js=js.replace('  const desc={...FFLjs.FFLCharModelDescDefault','  if(!ffl){const model=PlazaFallback.model(a);models.set(a.data,model);return model;}\n  const desc={...FFLjs.FFLCharModelDescDefault');
js=js.replace('function featureIcon(a,feature,w=144,h=96){','function featureIcon(a,feature,w=144,h=96){\n  if(!ffl)return PlazaFallback.featureIcon(a,feature,w,h);');
fs.writeFileSync(adapter,js);
console.log('Prepared unchanged Mac crowd sources and renderer assets.');
require('./prepare-artwork.cjs');
