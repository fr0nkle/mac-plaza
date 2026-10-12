/* Original Men2.pack body geometry and FSKA animation playback.
 * Source curves are evaluated directly; no authored gait is applied in this mode.
 * The 16-bone rigid palette is represented as a shared Three.js skinned geometry.
 */
'use strict';
const PlazaOriginalBody=(()=>{
  let resources,templates=[],texture,clips=new Map(),materials=new Map(),clipBones=new Map();
  const scratch={scale:new Float64Array(3),rotation:new Float64Array(4),translation:new Float64Array(3)};
  const worldScale=.14,headScale=.0108,headCenter=.378;
  const euler=new THREE.Euler(0,0,0,'ZYX'),q=new THREE.Quaternion(),v=new THREE.Vector3(),s=new THREE.Vector3();
  function clear(){for(const t of templates)t.geometry.dispose();templates=[];for(const m of materials.values())m.dispose();materials.clear();texture?.dispose();texture=null;clips.clear();clipBones.clear();resources=null;}
  function decodeTexture(t,module){
    if(t.width>512||t.height>512||t.data.length>4*1024*1024)throw new Error('Menu texture is too large.');
    const input=module._malloc(t.data.length),output=module._malloc(t.width*t.height*4);
    try{module.HEAPU8.set(t.data,input);if(module._MacPlazaDecodeMenuBC3(input,t.data.length,t.width,t.height,t.tile,t.swizzle,t.pitch,output)!==1)throw new Error('Original body texture could not be decoded.');return module.HEAPU8.slice(output,output+t.width*t.height*4);}finally{module._free(input);module._free(output);}
  }
  function load(pack,module){
    if(pack?.version!==1||pack.models?.length!==2||!Array.isArray(pack.animations)||pack.animations.length>256)throw new Error('Invalid local menu body resource.');
    // Validate/build first; a failed replacement must not destroy a previous resource.
    const built=[];let tex;
    try{
      const pixels=decodeTexture(pack.texture,module);tex=new THREE.DataTexture(pixels,pack.texture.width,pack.texture.height,THREE.RGBAFormat);tex.flipY=false;tex.magFilter=THREE.LinearFilter;tex.minFilter=THREE.LinearFilter;tex.needsUpdate=true;
      for(const m of pack.models){
        const n=m.positions.length/3;if(n<1||n>10000||m.bones.length!==16||m.joints.length!==n||m.normals.length!==n*3||m.colors.length!==n*4||m.uv.length!==n*2||m.indices.length>100000)throw new Error('Invalid original body mesh.');
        const g=new THREE.BufferGeometry();g.setAttribute('position',new THREE.Float32BufferAttribute(m.positions,3));g.setAttribute('normal',new THREE.Float32BufferAttribute(m.normals,3));g.setAttribute('_color',new THREE.Float32BufferAttribute(m.colors,4));g.setAttribute('uv',new THREE.Float32BufferAttribute(m.uv,2));g.setAttribute('tangent',new THREE.Float32BufferAttribute(new Float32Array(n*3),3));
        const indices=new Uint16Array(n*4),weights=new Float32Array(n*4);m.joints.forEach((j,i)=>{if(j<0||j>=16)throw new Error('Invalid palette index');indices[i*4]=j;weights[i*4]=1;});g.setAttribute('skinIndex',new THREE.Uint16BufferAttribute(indices,4));g.setAttribute('skinWeight',new THREE.Float32BufferAttribute(weights,4));g.setIndex(m.indices);
        // Source positions are rigid bone-local, not a flattened bind-pose mesh.
        // A generous conservative bound covers original gestures for picking.
        g.boundingSphere=new THREE.Sphere(new THREE.Vector3(0,7,0),30);
        built.push({data:m,geometry:g});
      }
      const map=new Map(pack.animations.map(c=>[c.name,c]));for(const name of ['Walk00_l','Wait00_l','Talk00_l','Talk01_l','Handwaving00_l','MessageHappy00_l'])if(!map.has(name))throw new Error('Missing original clip '+name);
      clear();resources=pack;templates=built;texture=tex;clips=map;for(const c of clips.values())clipBones.set(c.name,new Map(c.bones.map(b=>[b.name,b])));
    }catch(e){built.forEach(t=>t.geometry.dispose());tex?.dispose();throw e;}
  }
  function materialFor(a){
    const key=a.outfit;if(materials.has(key))return materials.get(key);
    const m=new FFLShaderMaterial({modulateMode:1,modulateType:9,color:new THREE.Color(outfits[a.outfit]),colorG:new THREE.Color(0x54565c),map:texture,useSpecularModeBlinn:true});
    // The menu atlas's alpha selects pants vs favorite-color cloth. It is not
    // transparency. Keep the original UVs, vertex lighting attributes and atlas.
    m.fragmentShader=m.fragmentShader.replace('color = vec4(texel.rgb, u_opacity * texel.a);','color = vec4(texel.rgb * mix(u_const1.rgb, u_const2.rgb, texel.a), u_opacity);');
    m.transparent=false;materials.set(key,m);return m;
  }
  function poseValues(clip,frame,bone){
    const d=clipBones.get(clip.name)?.get(bone.name),{scale,rotation,translation}=scratch;
    scale.set(d?.scale||bone.scale);rotation.set(d?.rotation||bone.rotation);translation.set(d?.translation||bone.translation);
    for(const c of d?.curves||[]){const value=PlazaMenuAssets.sample(c,frame);if(c.target>=4&&c.target<=12)scale[(c.target-4)/4]=value;else if(c.target>=16&&c.target<=24)translation[(c.target-16)/4]=value;else if(c.target>=32&&c.target<=44)rotation[(c.target-32)/4]=value;else throw new Error('Unsupported bone target');}
    return scratch;
  }
  function pick(state,social,index,time){
    if(state===1||state===2)return 'Walk00_l';
    if(state===3)return social?(index%2?'Talk01_l':'Talk00_l'):(time<20/30?'Handwaving00_o':'Handwaving00_l');
    if(state===4)return 'MessageHappy00_l';
    if(state===5)return social?'Wait00_l':'MessageSurprise00_l';
    return ['Wait00_l','Wait02_l','Wait05_l','Wait07_l'][index%4];
  }
  function create(a,index){
    const t=templates[a.gender===1?1:0],root=new THREE.Group(),body=new THREE.Group(),head=new THREE.Group();body.scale.setScalar(worldScale);root.add(body,head);
    const nodes=t.data.bones.map(b=>{const n=new THREE.Bone();n.name=b.name;n.matrixAutoUpdate=false;body.add(n);return n;});
    const skeleton=new THREE.Skeleton(nodes,nodes.map(()=>new THREE.Matrix4()));const mesh=new THREE.SkinnedMesh(t.geometry,materialFor(a));mesh.frustumCulled=false;body.add(mesh);mesh.bind(skeleton,new THREE.Matrix4());
    const build=Math.round(a.build*127),height=Math.round(a.height*127),sx=build*(height*.47/128+.4)/128+height*.23/128+.4,sy=height*.77/128+.5;
    const shapes=t.data.bones.map(b=>{if(/^arm_[lr][12]$/.test(b.name))return new THREE.Vector3(sy,sx,sx);if(/^(wrist|ankle)_[lr]$/.test(b.name))return new THREE.Vector3(sx,sx,sx);return new THREE.Vector3(sx,b.name==='head'?Math.max(1,sy):sy,sx);});
    const transforms=nodes.map(()=>({position:new THREE.Vector3(),quaternion:new THREE.Quaternion(),shape:new THREE.Vector3()}));
    const lastPose=nodes.map(()=>({p:new THREE.Vector3(),q:new THREE.Quaternion(),s:new THREE.Vector3()})),previousPose=nodes.map(()=>({p:new THREE.Vector3(),q:new THREE.Quaternion(),s:new THREE.Vector3()}));
    const rootScale=new THREE.Vector3(sy,sy,sx),headOffset=new THREE.Vector3();
    const idlePoses=t.data.bones.map(b=>{const p=poseValues(clips.get('Wait00_l'),0,b);return {p:new THREE.Vector3().fromArray(p.translation),q:new THREE.Quaternion().setFromEuler(new THREE.Euler(...p.rotation.slice(0,3),'ZYX')),s:new THREE.Vector3().fromArray(p.scale)};});
    let previous='',transition=1,lastTime=null,hasPrevious=false,clipName='',clipFrame=0,controllerSample=null;
    const sourceClips=resources.animations;
    function apply(name,frame,time,instant=false,weight=1,native=null){
      const clip=clips.get(name);if(!clip)throw new Error('Missing original animation '+name);
      if(previous!==name){hasPrevious=!!previous;if(hasPrevious)previousPose.forEach((p,i)=>{p.p.copy(lastPose[i].p);p.q.copy(lastPose[i].q);p.s.copy(lastPose[i].s);});previous=name;transition=instant?1:0;}
      const dt=lastTime===null?1/30:Math.max(0,Math.min(.1,time-lastTime));lastTime=time;transition=Math.min(1,transition+dt/.18);
      if(instant)transition=1;
      const alpha=native?native.blend:transition*transition*(3-2*transition);
      const outgoing=native&&alpha<1?clips.get(sourceClips[native.previousClip]?.name):null;
      controllerSample=native;
      for(let i=0;i<nodes.length;i++){
        const b=t.data.bones[i],p=poseValues(clip,frame,b);euler.set(p.rotation[0],p.rotation[1],p.rotation[2],'ZYX');q.setFromEuler(euler);v.fromArray(p.translation);s.fromArray(p.scale);
        if(weight<1){const idle=idlePoses[i];v.lerpVectors(idle.p,v,weight);q.slerpQuaternions(idle.q,q,weight);s.lerpVectors(idle.s,s,weight);}
        if(outgoing){
          // Recovered native controller supplies both original clips and the
          // original linear weight. Do not apply the legacy fixed crossfade.
          const prior=poseValues(outgoing,native.previousFrame,b);
          const priorP=previousPose[i].p.fromArray(prior.translation),priorQ=previousPose[i].q;
          euler.set(prior.rotation[0],prior.rotation[1],prior.rotation[2],'ZYX');priorQ.setFromEuler(euler);
          const priorS=previousPose[i].s.fromArray(prior.scale);
          v.lerpVectors(priorP,v,alpha);q.slerpQuaternions(priorQ,q,alpha);s.lerpVectors(priorS,s,alpha);
        } else if(!native&&hasPrevious&&alpha<1){v.lerpVectors(previousPose[i].p,v,alpha);q.slerpQuaternions(previousPose[i].q,q,alpha);s.lerpVectors(previousPose[i].s,s,alpha);}
        lastPose[i].p.copy(v);lastPose[i].q.copy(q);lastPose[i].s.copy(s);
        const at=transforms[i],parent=b.parent>=0?transforms[b.parent]:null;
        if(parent){
          at.position.copy(v).multiply(parent.shape);
          if(t.data.bones[b.parent].name==='skl_root')at.position.y+=sx-sy;
          at.position.applyQuaternion(parent.quaternion).add(parent.position);at.quaternion.copy(parent.quaternion).multiply(q);
        }else{at.position.copy(v).multiply(rootScale);at.quaternion.copy(q);}
        at.shape.copy(shapes[i]).multiply(s);nodes[i].matrix.compose(at.position,at.quaternion,at.shape);
      }
      clipName=name;clipFrame=frame;
      const at=transforms[t.data.bones.findIndex(b=>b.name==='head')];head.position.copy(at.position).multiplyScalar(worldScale);head.quaternion.copy(at.quaternion);head.position.add(headOffset.set(0,headCenter,0).applyQuaternion(at.quaternion));
    }
    function frame(w,instant=false){
      if(w.length>=23){
        const native={clip:w[17],frame:w[18],previousClip:w[19],previousFrame:w[20],blend:w[21],revision:w[22]};
        const current=sourceClips[native.clip],old=sourceClips[native.previousClip];
        if(!current||!old||![native.frame,native.previousFrame,native.blend].every(Number.isFinite)||native.blend<0||native.blend>1)throw new Error('Invalid native controller pose');
        apply(current.name,native.frame,w[16]??0,instant,1,native);return;
      }
      const state=w[4],phase=w[5],amount=w[6],social=!!w[7],time=w[10]??0;
      const sequence=w.length>=16 && state!==1 && state!==2 ? PlazaOriginalSequence.sample(clips,w[14]<0?0:w[13],w[14],w[15],index):null;
      const name=sequence?.name||pick(state,social,index,time),clip=clips.get(name);
      // Keep original curve timing; distance drives the walk cycle. The measured
      // original planted-foot travel is approximately 10.4 body units per cycle.
      // The native simulation uses 1.456 world units before height scaling.
      const f=sequence?sequence.frame:(state===1||state===2)?((phase/(2*Math.PI))%1+1)%1*clip.frames:clip.loop?((time*30+(state===0?index*7:0))%clip.frames+clip.frames)%clip.frames:Math.max(0,Math.min(clip.frames,time*30));
      apply(name,f,w[16]??time,instant,(state===1||state===2)?Math.max(0,Math.min(1,amount)):1);
    }
    apply('Wait00_l',0,0,true);
    return {root,body,head,mesh,skeleton,frame,apply,dispose:()=>{skeleton.dispose();},stats:()=>({clip:clipName,frame:clipFrame,nativeController:!!controllerSample,blend:controllerSample?.blend??transition,head:head.position.toArray(),bones:nodes.map(n=>n.matrix.elements.slice())})};
  }
  return {load,clear,create,decodeTexture,get active(){return !!resources;},get clipCount(){return clips.size;},get modelCount(){return templates.length;},get headScale(){return headScale;},get headCenter(){return headCenter;}};
})();
if(typeof module!=='undefined')module.exports=PlazaOriginalBody;
