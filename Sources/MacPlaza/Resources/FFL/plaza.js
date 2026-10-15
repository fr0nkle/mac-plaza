/* Mac Plaza local FFL adapter. No fetch, sockets, CDN, or remote renderer. */
'use strict';
const send = (type, value) => window.webkit.messageHandlers.ffl.postMessage({type,value});
const bytes = s => Uint8Array.from(atob(s), c => c.charCodeAt(0));
let ffl, renderer, scene, camera, mode, models = new Map(), rigs = [];
let generation = 0;
let plazaRenderScale=1;
function setRenderScale(scale){plazaRenderScale=Math.max(1,Math.min(2,Number(scale)||1));resize();}
let noteTargets=[];
function setNoteTargets(indices){noteTargets=indices.filter(i=>Number.isInteger(i)&&i>=0&&i<200).slice(0,6);if(renderer)draw();}
function fail(e) { const message=String(e?.message || e); document.getElementById('error').style.display='block';document.getElementById('error').textContent='FFL renderer: '+message;send('error',message+(e?.stack?"\n"+e.stack:"")); }
window.addEventListener('error', e=>fail(e.error || e.message));
window.addEventListener('unhandledrejection', e=>fail(e.reason));
async function initialize(resource, wasm, requestedMode, bodyResource=null) {
  mode=requestedMode;
  renderer=new THREE.WebGLRenderer({alpha:true,antialias:true,preserveDrawingBuffer:mode==='portrait'});
  // FFL's Wii U shader operates in sRGB, not Three's linear workflow.
  THREE.ColorManagement && (THREE.ColorManagement.legacyMode=true);
  renderer.outputEncoding=THREE.LinearEncoding;
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.5));
  renderer.setClearColor(0,0); document.body.appendChild(renderer.domElement);
  scene=new THREE.Scene();scene.autoUpdate=false;camera=new THREE.OrthographicCamera(-1,1,1,-1,.1,100);
  scene.add(new THREE.AmbientLight(0xffffff,.65));const key=new THREE.DirectionalLight(0xffffff,.8);key.position.set(-3,6,8);scene.add(key);
  ffl=await FFLjs.FFL.initWithResource(bytes(resource),ModuleFFL({wasmBinary:bytes(wasm),print:()=>{},printErr:()=>{}}));
  if(ffl.module._MacPlazaFFLHasGX2()!==1)throw new Error("FFL was built without Wii U texture conversion support.");
  if(ffl.module._MacPlazaFFLVerifyGX2()!==1)throw new Error("The Wii U texture conversion self-test failed.");
  ffl.setRenderer(renderer);if(bodyResource)PlazaOriginalBody.load(JSON.parse(new TextDecoder().decode(bytes(bodyResource))),ffl.module);resize();
  send('ready',true);
}
function getModel(a) {
  if(models.has(a.data))return models.get(a.data);
  const desc={...FFLjs.FFLCharModelDescDefault,resolution:mode==='plaza'?256:512,allExpressionFlag:FFLjs.makeExpressionFlag(mode==='plaza'?[0,1,4,5,6,7,11]:[0,1,4])};
  const model=new FFLjs.CharModel(ffl,bytes(a.data),desc,FFLShaderMaterial,renderer);
  models.set(a.data,model);return model;
}
const outfits=[0xD21E14,0xFF6E19,0xFFD820,0x78D220,0x007830,0x0A48BC,0x3CAADE,0xF55A7D,0x7328AD,0x483818,0xE0E0E0,0x181814];
const bodyMaterials=new Map();
function material(c){if(!bodyMaterials.has(c))bodyMaterials.set(c,new THREE.MeshLambertMaterial({color:c}));return bodyMaterials.get(c);}
const sphere=new THREE.SphereGeometry(1,16,12);
// Rounded shoulders and a softly tapered waist replace the previous rigid cone.
// Original geometry, shared by the entire crowd; no downloaded body assets.
function torsoGeometry(female){
  const profile=[[0,-.085],[female ? .205 : .175,-.08],[female ? .226 : .19,-.05],[female ? .216 : .18,.02],[.158,.22],[.177,.43],[.195,.51],[.175,.55],[.09,.58],[0,.58]];
  return new THREE.LatheGeometry(profile.map(p=>new THREE.Vector2(...p)),20);
}
const shirt=torsoGeometry(false),femaleShirt=torsoGeometry(true);
const upperLeg=new THREE.CylinderGeometry(.050,.043,.34,10),lowerLeg=new THREE.CylinderGeometry(.043,.037,.36,10);
const upperArm=new THREE.CylinderGeometry(.054,.047,.27,10),lowerArm=new THREE.CylinderGeometry(.047,.040,.27,10);
const bodyBatches=new Map();
function batchBody(n){
  if(mode!=='plaza')return;
  const key=n.geometry.uuid+n.material.uuid;
  if(!bodyBatches.has(key)){
    const batch=new THREE.InstancedMesh(n.geometry,n.material,512);batch.count=0;batch.frustumCulled=false;
    batch.instanceMatrix.setUsage(THREE.DynamicDrawUsage);scene.add(batch);bodyBatches.set(key,{batch,members:[]});
  }
  bodyBatches.get(key).members.push(n);n.visible=false;
}
function updateBodies(){
  for(const {batch,members} of bodyBatches.values()){
    let count=0;
    for(const n of members){
      let visible=true;for(let p=n.parent;p;p=p.parent)if(!p.visible){visible=false;break;}
      if(visible)batch.setMatrixAt(count++,n.matrixWorld);
    }
    batch.count=count;batch.instanceMatrix.needsUpdate=true;
  }
}
function clearBodies(){for(const {batch} of bodyBatches.values()){scene.remove(batch);batch.dispose();}bodyBatches.clear();}
function mesh(g,c,p,s,parent){let n=new THREE.Mesh(g,material(c));n.position.fromArray(p);s&&n.scale.fromArray(s);parent.add(n);batchBody(n);return n;}
function joint(parent,p){const n=new THREE.Group();n.position.fromArray(p);parent.add(n);return n;}
let shadowMaterial;const shadowGeometry=new THREE.PlaneGeometry(.9,.5);
function shadow(parent){
  if(!shadowMaterial){const c=document.createElement('canvas');c.width=c.height=64;const ctx=c.getContext('2d'),g=ctx.createRadialGradient(32,32,0,32,32,32);g.addColorStop(0,'rgba(0,0,0,.16)');g.addColorStop(1,'rgba(0,0,0,0)');ctx.fillStyle=g;ctx.fillRect(0,0,64,64);shadowMaterial=new THREE.MeshBasicMaterial({map:new THREE.CanvasTexture(c),transparent:true,depthWrite:false});}
  const n=new THREE.Mesh(shadowGeometry,shadowMaterial);n.rotation.x=-Math.PI/2;n.position.y=.005;parent.add(n);batchBody(n);return n;
}
function makeOriginalRig(a,index){
  const model=getModel(a),original=PlazaOriginalBody.create(a,index),{root,body,head}=original,headMeshes=model.meshes.clone();let maskMaterial;
  headMeshes.traverse(n=>{if(n.isMesh&&n.material.modulateType===6){n.material=n.material.clone();maskMaterial=n.material;}});
  headMeshes.scale.setScalar(PlazaOriginalBody.headScale);headMeshes.position.set(0,-PlazaOriginalBody.headCenter,0);head.add(headMeshes);
  root.userData.index=index;root.traverse(n=>n.userData.index=index);scene.add(root);
  return {root,body,head,model,original,maskMaterial,shadow:shadow(root),expression:-1};
}
function makeRig(a,index) {
  if(PlazaOriginalBody.active)return makeOriginalRig(a,index);
  const model=getModel(a),root=new THREE.Group(),stature=.72+a.height*.40,girth=.76+a.build*.48;
  const body=joint(root,[0,.844*stature,0]),torso=joint(body,[0,0,0]);
  body.scale.set(girth,stature,stature);
  const color=outfits[a.outfit],skin=model.facelineColor.getHex();
  const head=joint(root,[0,1.454*stature+.378,0]);
  // A fixed chin attachment keeps short/long hairstyles at the same neck.
  const headMeshes=model.meshes.clone();let maskMaterial;
  headMeshes.traverse(n=>{if(n.isMesh && n.material.modulateType===6){n.material=n.material.clone();maskMaterial=n.material;}});
  headMeshes.scale.setScalar(.0108);headMeshes.position.set(0,-.378,0);head.add(headMeshes);
  mesh(a.gender===1?femaleShirt:shirt,color,[0,0,0],[1,1,.68*girth/stature],torso);
  mesh(sphere,skin,[0,.59,0],[.067,.085,.067],torso);
  const arms=[],elbows=[],hands=[],legs=[],knees=[],ankles=[];
  for(const side of [-1,1]){
    const n=joint(torso,[side*.18,.51,0]);
    mesh(upperArm,color,[0,-.135,0],null,n);
    const elbow=joint(n,[0,-.27,0]);mesh(sphere,color,[0,0,0],[.047,.047,.047],elbow);
    mesh(lowerArm,color,[0,-.135,0],null,elbow);
    const hand=joint(elbow,[0,-.285,0]);mesh(sphere,skin,[0,0,0],[.052,.058,.048],hand);
    arms.push(n);elbows.push(elbow);hands.push(hand);
  }
  for(const side of [-1,1]){
    const n=joint(body,[side*.085,-.08,0]);mesh(upperLeg,0x4B4C50,[0,-.17,0],null,n);
    const knee=joint(n,[0,-.34,0]);mesh(sphere,0x4B4C50,[0,0,0],[.043,.043,.043],knee);
    mesh(lowerLeg,0x4B4C50,[0,-.18,0],null,knee);
    const ankle=joint(knee,[0,-.36,0]);mesh(sphere,0x3A3B3E,[0,-.01,.025],[.058,.055,.10],ankle);
    legs.push(n);knees.push(knee);ankles.push(ankle);
  }
  root.userData.index=index;root.traverse(n=>n.userData.index=index);scene.add(root);
  return {root,body,torso,head,model,arms,elbows,hands,legs,knees,ankles,stature,maskMaterial,shadow:shadow(root),expression:-1};
}
function clearRigs(){clearBodies();for(const r of rigs){scene.remove(r.root);r.maskMaterial?.dispose();r.original?.dispose();}rigs=[];}
function rosterKeys(identities){
  const counts=new Map();return identities.map(id=>{const occurrence=counts.get(id)||0;counts.set(id,occurrence+1);return id+':'+occurrence;});
}
function removeRig(r){
  scene.remove(r.root);r.maskMaterial?.dispose();r.original?.dispose();
  // Removed fallback limbs must leave their instance batches as well. A stale
  // member would continue drawing a ghost after its root leaves the scene.
  for(const {members} of bodyBatches.values())for(let i=members.length-1;i>=0;i--){
    for(let p=members[i];p;p=p.parent)if(p===r.root){members.splice(i,1);break;}
  }
}
async function configure(avatars) {
  if(avatars.length>200)throw new Error('The plaza supports at most 200 characters.');
  ++generation;
  const previous=rigs,retained=new Map(previous.map(r=>[r.identity,r]));
  const keys=rosterKeys(avatars.map((a,i)=>a.id||a.data||String(i)));
  const wantedIdentities=new Set(keys),vacancies=previous.filter(r=>!wantedIdentities.has(r.identity));
  rigs=avatars.map((a,i)=>{
    const identity=keys[i],appearance=JSON.stringify([a.data,a.height,a.build,a.outfit,a.gender]);
    const old=retained.get(identity);let r=old;
    if(!r||r.appearance!==appearance){
      r=makeRig(a,i);
      // Keep an edited Mii, or a replacement in a full crowd, at the last
      // displayed pose until its identity-tagged native snapshot arrives.
      const poseBefore=old?.lastPose||vacancies.shift()?.lastPose;
      if(poseBefore)pose(r,poseBefore,true);else r.root.visible=false;
    }
    r.identity=identity;r.appearance=appearance;
    r.root.traverse(n=>n.userData.index=i);return r;
  });
  const surviving=new Set(rigs);
  for(const r of previous)if(!surviving.has(r))removeRig(r);
  const wanted=new Set(avatars.map(a=>a.data));
  for(const [key,model] of models)if(!wanted.has(key)){model.dispose();models.delete(key);}
  draw();send('configured',rigs.length);
}
function expression(blink,mood){return blink ? (mood===3?11:5):[0,1,4,6][mood] || 0;}
function pose(r,w,instant=false){
  r.lastPose=w;r.root.visible=true;
  const [x,z,height=0,angle,state,phase,amount,social,blink,mood,time=0,lookYaw=0,turn=0]=w;
  if(r.original){
    r.root.position.set(x,height,z);r.root.rotation.y=angle;r.original.frame(w,instant);r.shadow.position.y=.005-height;
    const exp=expression(blink,mood);if(exp!==r.expression){r.model.setExpression(exp);if(r.maskMaterial)r.maskMaterial.map=r.model._maskMesh.material.map;r.expression=exp;}return;
  }
  const p=PlazaMotion.solve(state,phase,amount,time,!!social,lookYaw,turn);
  r.root.position.set(x,height+p.hop*r.stature,z);r.root.rotation.y=angle;
  r.body.position.y=(.844+p.bob)*r.stature;r.head.position.y=(1.454+p.bob)*r.stature+.378;
  r.shadow.position.y=.005-r.root.position.y;
  r.shadow.scale.setScalar(1+p.hop*.8);
  // Ease expressive joints. Feet use the exact IK solution: filtering leg angles
  // would introduce lag and make planted soles skate across the floor.
  const nodes=[...r.arms,...r.elbows,r.torso,r.head];
  const values=[p.la,p.ra,p.le,p.re,p.torso,p.head],blend=instant?1:1-Math.exp(-13/30);
  nodes.forEach((n,i)=>{const e=n.rotation,v=values[i];e.set(e.x+(v[0]-e.x)*blend,e.y+(v[1]-e.y)*blend,e.z+(v[2]-e.z)*blend);});
  r.hands[1].rotation.z=p.wrist;
  p.legs.forEach((v,i)=>{r.legs[i].rotation.x=v[0];r.knees[i].rotation.x=v[1];r.ankles[i].rotation.x=v[2];});
  const exp=expression(blink,mood);if(exp!==r.expression){r.model.setExpression(exp);if(r.maskMaterial)r.maskMaterial.map=r.model._maskMesh.material.map;r.expression=exp;}
}
function frame(snapshot,identities){
  if(!renderer)return;
  if(identities){
    // In-flight frames can belong to a roster that has since been reordered.
    // A Mii may only consume a pose carrying its own identity.
    const keys=rosterKeys(identities),poses=new Map(keys.map((key,i)=>[key,snapshot[i]]));
    rigs.forEach(r=>{const w=poses.get(r.identity);if(w)pose(r,w);});
  }else rigs.forEach((r,i)=>snapshot[i]&&pose(r,snapshot[i]));
  draw();
}
function draw(){if(renderer){scene.updateMatrixWorld(true);updateBodies();renderer.render(scene,camera);
  if(mode==='plaza'&&noteTargets.length){const anchors=[];for(const i of noteTargets){const r=rigs[i];if(!r)continue;const p=r.head.getWorldPosition(new THREE.Vector3());p.y+=.42;p.project(camera);anchors.push([i,(p.x+1)/2,(1-p.y)/2]);}send('noteAnchors',anchors);}
}}
function resize(){if(!renderer)return;const w=Math.max(1,innerWidth),h=Math.max(1,innerHeight);renderer.setSize(w,h,false);
  if(mode==='plaza'){const half=24*plazaRenderScale*h/w;camera.left=-24*plazaRenderScale;camera.right=24*plazaRenderScale;camera.top=half;camera.bottom=-half;camera.position.set(0,16,22);camera.lookAt(0,0,0);}
  else{camera.left=-1.38*w/h;camera.right=1.38*w/h;camera.top=1.38;camera.bottom=-1.38;camera.position.set(0,1.20,6);camera.lookAt(0,1.20,0);}
  camera.updateProjectionMatrix();draw();}
window.addEventListener('resize',resize);
async function preview(a,angle,state,headOnly=false){await configure([a]);const r=rigs[0];r.body.visible=true;r.shadow.visible=true;pose(r,[0,0,0,angle,state,1,state===1?1:0,false,false,state===4?1:state===5?2:0,.4],true);
  if(headOnly){r.body.visible=false;r.shadow.visible=false;camera.left=-.64;camera.right=.64;camera.top=.64;camera.bottom=-.64;camera.position.set(0,r.head.position.y,6);camera.lookAt(0,r.head.position.y,0);camera.updateProjectionMatrix();}
  draw();}
async function portrait(a,angle,state,headOnly,w,h){camera.position.set(0,1.20,6);camera.lookAt(0,1.20,0);renderer.setPixelRatio(1);renderer.setSize(w,h,false);camera.left=-1.4*w/h;camera.right=1.4*w/h;camera.top=1.4;camera.bottom=-1.4;camera.updateProjectionMatrix();await preview(a,angle,state,headOnly);return renderer.domElement.toDataURL('image/png');}
// Capture actual FFL parts while its temporary mask textures are alive. The
// feature tiles use the same geometry, textures and modulation as the Mii.
function featureIcon(a,feature,w=144,h=96){
  const types=FFLjs.FFLModulateType,part={eyes:types.EYE,brows:types.EYEBROW,mouth:types.MOUTH}[feature];
  if(part===undefined&&feature!=='nose')throw new Error('Unknown feature tile');
  const render=renderer.render,originalRender=render.bind(renderer);
  let model,result;
  renderer.setPixelRatio(1);renderer.setSize(w,h,false);
  function capture(meshes,isNose=false){
    const isolated=new THREE.Scene();
    // Left and right mask parts are separate meshes; the catalog shows one.
    if(!isNose)meshes=meshes.slice(0,1);
    meshes.forEach(mesh=>isolated.add(mesh.clone()));
    isolated.updateMatrixWorld(true);
    const box=new THREE.Box3().setFromObject(isolated),size=box.getSize(new THREE.Vector3()),center=box.getCenter(new THREE.Vector3());
    if(box.isEmpty())return;
    const half=Math.max(size.y/2,size.x*h/w/2,.001)*1.35;
    // FFL mask parts use a downward Y axis; real nose geometry uses world Y.
    const view=new THREE.OrthographicCamera(-half*w/h,half*w/h,isNose?half:-half,isNose?-half:half,.01,1000);
    view.position.set(center.x,center.y,box.max.z+100);view.lookAt(center);view.updateProjectionMatrix();
    const target=renderer.getRenderTarget();
    try{renderer.setRenderTarget(null);renderer.clear();originalRender(isolated,view);result=renderer.domElement.toDataURL('image/png');}
    finally{renderer.setRenderTarget(target);isolated.clear();}
  }
  try{
    const desc={...FFLjs.FFLCharModelDescDefault,resolution:256,allExpressionFlag:FFLjs.makeExpressionFlag([0])};
    model=new FFLjs.CharModel(ffl,bytes(a.data),desc,FFLShaderMaterial);
    if(part!==undefined){
      renderer.render=function(s,c){
        if(!result){const parts=s.children.filter(n=>n.isMesh&&n.geometry.userData.modulateType===part);if(parts.length)capture(parts);}
        return originalRender(s,c);
      };
    }
    model.initTextures(renderer);
    renderer.render=render;
    if(feature==='nose')capture(model.meshes.children.filter(n=>n.geometry.userData.modulateType===types.SHAPE_NOSE||n.geometry.userData.modulateType===types.SHAPE_NOSELINE),true);
    // A deliberately absent feature (e.g. no eyebrows) has an empty tile.
    if(!result){renderer.setRenderTarget(null);renderer.clear();result=renderer.domElement.toDataURL('image/png');}
    return result;
  }finally{renderer.render=render;model?.dispose();}
}
document.addEventListener('pointerdown',event=>{if(mode!=='plaza')return;const p=new THREE.Vector2(event.clientX/innerWidth*2-1,1-event.clientY/innerHeight*2),ray=new THREE.Raycaster();ray.setFromCamera(p,camera);const hit=ray.intersectObjects(rigs.map(r=>r.root),true)[0];if(hit)send('select',hit.object.userData.index);});
function dispose(){++generation;clearRigs();for(const model of models.values())model.dispose();models.clear();PlazaOriginalBody.clear();ffl?.dispose();renderer?.dispose();renderer?.forceContextLoss();renderer=null;}
function snapshot(){draw();return renderer.domElement.toDataURL('image/png');}
function diagnostics(){return {roster:rigs.map(r=>({id:r.identity,root:r.root.uuid,position:r.root.position.toArray(),visible:r.root.visible})),originalBodies:PlazaOriginalBody.active,originalClips:PlazaOriginalBody.clipCount,original:rigs.slice(0,4).map(r=>r.original?.stats()||null),feet:rigs.slice(0,4).map(r=>r.ankles?.map(n=>n.getWorldPosition(new THREE.Vector3()).toArray())||[]),drawCalls:renderer.info.render.calls,rigs:rigs.length,models:models.size,bodyBatches:bodyBatches.size,bodyInstances:Array.from(bodyBatches.values()).reduce((n,b)=>n+b.batch.count,0),masks:rigs.map(r=>({material:r.maskMaterial?.uuid,texture:r.maskMaterial?.map?.uuid,expression:r.expression}))};}
async function importMenu(data){const pack=PlazaMenuAssets.read(bytes(data));clearRigs();PlazaOriginalBody.load(pack,ffl.module);return JSON.stringify(pack);}
window.plazaFFL={setRenderScale,setNoteTargets,importMenu,initialize,configure,frame,preview,portrait,featureIcon,dispose,diagnostics,snapshot,motion:PlazaMotion.solve};
window.plazaFFL.dispatch=(id,method,args)=>{
  Promise.resolve().then(()=>window.plazaFFL[method](...args)).then(value=>send('reply',{id,value:value??null}),error=>send('reply',{id,error:String(error?.stack||error)}));
};
send('loaded',true);
