/* Local Wii U menu data reader. No firmware execution, eval, fetch or dependencies.
 * Supports the big-endian BFRES 3.0 resources used by Men2.pack. Format field
 * references: KillzXGaming/BfresLibrary and Nintendo file-format documentation.
 * Original implementation; output preserves source vertices and cubic coefficients.
 */
'use strict';
const PlazaMenuAssets=(()=>{
  const check=(ok,message)=>{if(!ok)throw new Error('Menu assets: '+message);};
  class Reader {
    constructor(bytes){this.b=bytes;this.v=new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength);}
    bounds(p,n=1){check(Number.isInteger(p)&&p>=0&&n>=0&&p+n<=this.b.length,'out-of-range data');return p;}
    u8(p){return this.v.getUint8(this.bounds(p));} i8(p){return this.v.getInt8(this.bounds(p));}
    u16(p){return this.v.getUint16(this.bounds(p,2));} i16(p){return this.v.getInt16(this.bounds(p,2));}
    u32(p){return this.v.getUint32(this.bounds(p,4));} i32(p){return this.v.getInt32(this.bounds(p,4));}
    f32(p){const v=this.v.getFloat32(this.bounds(p,4));check(Number.isFinite(v),'non-finite float');return v;}
    ptr(p){const delta=this.i32(p);return delta?this.bounds(p+delta):0;}
    textAt(p){if(!p)return '';let end=p;while(end<this.b.length&&end-p<1024&&this.b[end])end++;check(end<this.b.length&&end-p<1024,'unterminated name');return new TextDecoder().decode(this.b.subarray(p,end));}
    text(p){return this.textAt(this.ptr(p));}
    signature(p,s){check(this.textBytes(p,s.length)===s,'expected '+s);}
    textBytes(p,n){return String.fromCharCode(...this.b.subarray(this.bounds(p,n),p+n));}
    floats(p,n){return Array.from({length:n},(_,i)=>this.f32(p+i*4));}
    slice(p,n){this.bounds(p,n);return this.b.slice(p,p+n);}
    dict(p){if(!p)return [];const n=this.u32(p+4);check(n<=512,'too many dictionary entries');this.bounds(p+8,(n+1)*16);return Array.from({length:n},(_,i)=>{const o=p+8+(i+1)*16;return [this.text(o+8),this.ptr(o+12)];});}
  }
  function yaz0(b){
    const r=new Reader(b);r.signature(0,'Yaz0');const length=r.u32(4);check(length>0&&length<=32*1024*1024,'expanded archive size');const out=new Uint8Array(length);let i=16,o=0;
    while(o<length){const bits=r.u8(i++);for(let mask=128;mask&&o<length;mask>>=1){if(bits&mask)out[o++]=r.u8(i++);else{const a=r.u8(i++),c=r.u8(i++),distance=((a&15)<<8|c)+1;let n=a>>4;n=n?n+2:r.u8(i++)+18;check(distance<=o&&o+n<=length,'invalid Yaz0 back-reference');while(n--){out[o]=out[o-distance];o++;}}}}
    return out;
  }
  function sarc(b){
    const r=new Reader(b);r.signature(0,'SARC');check(r.u16(6)===0xfeff,'only big-endian SARC is supported');check(r.u32(8)===b.length,'archive length mismatch');const sfat=r.u16(4);r.signature(sfat,'SFAT');const count=r.u16(sfat+6),nodes=sfat+r.u16(sfat+4),names=nodes+count*16;r.signature(names,'SFNT');const strings=names+r.u16(names+4),data=r.u32(12);check(count<=4096,'too many archive entries');const out=new Map();let totalBytes=0;
    for(let i=0;i<count;i++){const p=nodes+i*16,flags=r.u32(p+4),start=r.u32(p+8),end=r.u32(p+12);check(flags>>>24===1&&end>=start,'invalid named archive entry');totalBytes+=end-start;check(totalBytes<=b.length*2,'overlapping archive allocation budget');const name=r.textAt(strings+(flags&0xffffff)*4);check(!out.has(name),'duplicate archive member');out.set(name,r.slice(data+start,end-start));}return out;
  }
  function fresIn(b){if(String.fromCharCode(...b.subarray(0,4))==='Yaz0')b=yaz0(b);if(String.fromCharCode(...b.subarray(0,4))==='FRES')return b;const a=sarc(b),entry=Array.from(a).find(([n])=>n.endsWith('.bfres'));check(entry,'BFRES missing');return entry[1];}
  function half(v){const sign=v&0x8000?-1:1,e=v>>10&31,m=v&1023;check(e!==31,'non-finite vertex');return sign*(e?Math.pow(2,e-15)*(1+m/1024):Math.pow(2,-14)*m/1024);}
  function vertex(r,p,format){
    if(format===0x80f)return [0,1,2,3].map(i=>half(r.u16(p+i*2)));
    if(format===0x811)return r.floats(p,3);
    if(format===0x20b){const v=r.u32(p),s=x=>Math.max(-1,(x&512?x-1024:x)/511);return [s(v&1023),s(v>>>10&1023),s(v>>>20&1023)];}
    if(format===0xa)return [0,1,2,3].map(i=>r.u8(p+i)/255);
    if(format===7)return [r.u16(p)/65535,r.u16(p+2)/65535];
    if(format===0x808)return [half(r.u16(p)),half(r.u16(p+2))];
    if(format===0x100)return [r.u8(p)];
    throw new Error('Menu assets: unsupported vertex format '+format.toString(16));
  }
  function model(r,p){
    r.signature(p,'FMDL');const name=r.text(p+4),sk=r.ptr(p+12);r.signature(sk,'FSKL');const bs=r.dict(r.ptr(sk+16));check(bs.length===16&&r.u16(sk+10)===0,'expected original 16-bone rigid body');const palette=Array.from({length:r.u16(sk+12)},(_,i)=>r.u16(r.ptr(sk+24)+i*2));
    const bones=bs.map(([name,b])=>({name,parent:r.i16(b+6),flags:r.u32(b+16),scale:r.floats(b+20,3),rotation:r.floats(b+32,4),translation:r.floats(b+48,3)}));
    check(bones.every((b,i)=>b.parent<i&&b.parent>=-1),'bone hierarchy');
    const shapes=r.dict(r.ptr(p+20));check(shapes.length===1,'expected one body shape');const sh=shapes[0][1];r.signature(sh,'FSHP');check(r.u8(sh+22)===1,'expected rigid skinning');const v=r.ptr(sh+32);r.signature(v,'FVTX');const count=r.u32(v+8);check(count>0&&count<10000&&r.u8(v+5)<5,'vertex budget');const buffers=Array.from({length:r.u8(v+5)},(_,i)=>{const p=r.ptr(v+24)+i*24;return {pointer:r.ptr(p+20),stride:r.u16(p+12),size:r.u32(p+4)};});
    const attributes={};for(const [name,a] of r.dict(r.ptr(v+20))){const buffer=buffers[r.u8(a+4)];check(buffer&&buffer.stride,'vertex buffer');const format=r.u32(a+8),offset=r.u16(a+6),values=[];for(let i=0;i<count;i++)values.push(...vertex(r,buffer.pointer+i*buffer.stride+offset,format));attributes[name]=values;}
    check(attributes._p0?.length===count*4&&attributes._i0?.length===count,'required vertex attributes');
    const mesh=r.ptr(sh+36),primitive=r.u32(mesh),format=r.u32(mesh+4),n=r.u32(mesh+8),indexBuffer=r.ptr(mesh+20),first=r.u32(mesh+24),data=r.ptr(indexBuffer+20);check(primitive===4&&n<100000&&n%3===0,'triangle mesh');check(format===4,'expected big-endian 16-bit indices');const indices=Array.from({length:n},(_,i)=>r.u16(data+i*2)+first);check(indices.every(i=>i<count),'triangle indices');
    const joints=attributes._i0.map(i=>{check(i<palette.length&&palette[i]<bones.length,'bone palette index');return palette[i];});
    return {name,bones,positions:attributes._p0.filter((_,i)=>i%4!==3),normals:attributes._n0,colors:attributes._c0,uv:attributes._u0,joints,indices};
  }
  function curve(r,p){
    const flags=r.u16(p),count=r.u16(p+2),type=flags>>4&7,ft=flags&3,kt=flags>>2&3;check(count>0&&count<=4096&&ft<=2&&kt<=2&&[0,1,2].includes(type),'curve format');const fp=r.ptr(p+24),kp=r.ptr(p+28),elements=type===0?4:type===1?2:1;
    const frames=Array.from({length:count},(_,i)=>ft===0?r.f32(fp+i*4):ft===1?r.i16(fp+i*2)/32:r.u8(fp+i));check(frames.every((x,i)=>x>=0&&(!i||x>=frames[i-1])),'curve frame order');const keys=Array.from({length:count*elements},(_,i)=>kt===0?r.f32(kp+i*4):kt===1?r.i16(kp+i*2):r.i8(kp+i));return {target:r.u32(p+4),type,scale:r.f32(p+16),offset:r.f32(p+20),frames,keys};
  }
  function animation(r,p){
    r.signature(p,'FSKA');const name=r.text(p+4),flags=r.u32(p+12),frames=r.u16(p+16),count=r.u16(p+18),ba=r.ptr(p+32);check(frames>0&&frames<=3600&&count<=32&&(flags&0x7000)===0x1000,'skeletal clip');
    const bones=Array.from({length:count},(_,i)=>{const b=ba+i*24,f=r.u32(b),base=r.ptr(b+20);let at=base;const data={name:r.text(b+4),curves:[]};if(f&8){data.scale=r.floats(at,3);at+=12;}if(f&16){data.rotation=r.floats(at,4);at+=16;}if(f&32)data.translation=r.floats(at,3);check(r.u8(b+10)<=12,'bone curve count');for(let j=0;j<r.u8(b+10);j++)data.curves.push(curve(r,r.ptr(b+16)+j*32));return data;});return {name,frames,loop:!!(flags&4),bones};
  }
  function texture(r,p){r.signature(p,'FTEX');check(r.u32(p+24)===0x433,'expected original BC3 body atlas');return {width:r.u32(p+8),height:r.u32(p+12),tile:r.u32(p+52),swizzle:r.u32(p+56),pitch:r.u32(p+64),data:Array.from(r.slice(r.ptr(p+176),r.u32(p+36)))};}
  function read(input){
    check(input.byteLength<=64*1024*1024,'archive too large');const files=sarc(input),body=files.get('Common/Model/MiiBodyMiddle.szs'),anims=files.get('Common/Model/MiiAnim.szs');check(body&&anims,'choose Men2.pack containing MiiBodyMiddle.szs and MiiAnim.szs');const r=new Reader(fresIn(body)),a=new Reader(fresIn(anims));for(const f of [r,a]){f.signature(0,'FRES');check(f.u32(4)===0x03000001,'expected BFRES 3.0.0.1');}
    const models=new Map(r.dict(r.ptr(32))),textures=new Map(r.dict(r.ptr(36))),clips=a.dict(a.ptr(40)).map(([n,p])=>animation(a,p));
    for(const n of ['Walk00_l','Wait00_l','Talk00_l','Talk01_l','Handwaving00_l','MessageHappy00_l'])check(clips.some(c=>c.name===n),'missing '+n);
    check(models.has('FemaleBody')&&models.has('MaleBody')&&textures.has('Body'),'original body variants or atlas missing');return {version:1,format:'Wii U Menu BFRES 3.0.0.1',models:[model(r,models.get('MaleBody')),model(r,models.get('FemaleBody'))],animations:clips,texture:texture(r,textures.get('Body'))};
  }
  function sample(c,frame){
    const f=c.frames;let lo=0,hi=f.length-1;while(lo<hi){const mid=Math.ceil((lo+hi)/2);if(f[mid]<=frame)lo=mid;else hi=mid-1;}
    const elements=c.type===0?4:c.type===1?2:1,k=lo*elements,t=lo+1<f.length?Math.max(0,Math.min(1,(frame-f[lo])/(f[lo+1]-f[lo]))):0;
    let value=c.keys[k];if(c.type===0)value+=t*(c.keys[k+1]+t*(c.keys[k+2]+t*c.keys[k+3]));else if(c.type===1)value+=t*c.keys[k+1];return value*(c.scale||1)+c.offset;
  }
  return {read,sarc,yaz0,sample};
})();
if(typeof module!=='undefined')module.exports=PlazaMenuAssets;
