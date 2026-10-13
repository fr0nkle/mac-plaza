'use strict';
(() => {
  const colors = [0xe74646,0xf4872c,0xe9c832,0x76ac35,0x247f41,0x346fd1,0x79c9e7,0xdc78b5,0x7740ad,0x6b4331,0xdddddd,0x333d4a];
  const skins = ['#f5d0a8','#efd4b5','#cc9d70','#a8744c','#795336','#4d332b'];
  const hairs = [0x292424,0x4d3024,0x79532a,0xb69655,0x777777,0x543b31,0xc2aa73,0xe0d1a2];
  let scene, camera, renderer, walkers = [], frame, paused = matchMedia('(prefers-reduced-motion: reduce)').matches, last = 0;
  function mesh(geometry, color) { return new THREE.Mesh(geometry, new THREE.MeshLambertMaterial({color})); }
  function character(a) {
    const group = new THREE.Group();
    const body = mesh(new THREE.CylinderGeometry(.22,.32,.65,10), colors[a.outfit] || colors[0]); body.position.y=.79;group.add(body);
    for (const x of [-.13,.13]) { const leg=mesh(new THREE.CylinderGeometry(.085,.08,.4,8),0x414853);leg.position.set(x,.29,0);group.add(leg);const shoe=mesh(new THREE.SphereGeometry(.1,8,6),0x303c48);shoe.scale.z=1.6;shoe.position.set(x,.09,.05);group.add(shoe); }
    for(const x of [-.32,.32]) {const arm=mesh(new THREE.CylinderGeometry(.07,.07,.47,8),colors[a.outfit]||colors[0]);arm.position.set(x,.76,0);arm.rotation.z=x>0?-.25:.25;group.add(arm);}
    const head=mesh(new THREE.SphereGeometry(.34,20,16),skins[a.skin]||skins[0]);head.position.y=1.38;head.scale.y=1.12;group.add(head);
    const hair=mesh(new THREE.SphereGeometry(.345,16,10,0,Math.PI*2,0,a.hair===0?.65:1.15),hairs[a.hairColor]||hairs[0]);hair.position.y=1.48;group.add(hair);
    const face=document.createElement('canvas');face.width=256;face.height=256;const c=face.getContext('2d');
    c.fillStyle='#25242c';for(const x of [87,169]){c.beginPath();c.ellipse(x,108,8,12,0,0,Math.PI*2);c.fill();c.lineWidth=6;c.beginPath();c.moveTo(x-14,82);c.lineTo(x+12,79);c.strokeStyle='#4a3329';c.stroke();}
    c.strokeStyle='#9c6351';c.lineWidth=5;c.beginPath();c.moveTo(129,116);c.lineTo(121,141);c.lineTo(136,141);c.stroke();c.strokeStyle='#613e35';c.lineWidth=5;c.beginPath();c.arc(128,146,24,.2,Math.PI-.2);c.stroke();
    if(a.glasses){c.strokeStyle='#28303b';c.lineWidth=5;for(const x of[87,169]){c.beginPath();c.roundRect(x-24,88,48,37,7);c.stroke();}c.beginPath();c.moveTo(111,104);c.lineTo(145,104);c.stroke();}
    const texture=new THREE.CanvasTexture(face);const front=new THREE.Mesh(new THREE.PlaneGeometry(.61,.61),new THREE.MeshBasicMaterial({map:texture,transparent:true,depthWrite:false}));front.position.set(0,1.39,.315);group.add(front);
    group.scale.set(.85+a.build*.3,.8+a.height*.4,1);return group;
  }
  function dispose(group) {group.traverse(o=>{o.geometry?.dispose();if(o.material){o.material.map?.dispose();o.material.dispose();}});}
  function update(avatar,friends=[]) {
    if(!scene)return;for(const w of walkers){scene.remove(w.group);dispose(w.group);}walkers=[];
    const crowd=[avatar,...friends.map(f=>f.avatar).filter(Boolean)];
    for(let i=0;i<Math.min(50,Math.max(24,crowd.length));i++) {
      const a=crowd[i]||{...avatar,outfit:i%12,skin:i%6,hairColor:i%8,hair:i%3===0?0:33};const group=character(a);scene.add(group);
      const angle=i*2.39996,r=2+Math.sqrt(i)*.95;
      walkers.push({group,x:Math.cos(angle)*r,z:Math.sin(angle)*r,phase:i*1.8,friend:friends[i-1]});
    }
  }
  function animate(time) {
    frame=requestAnimationFrame(animate);if(time-last<1000/30)return;last=time;
    const t=paused?0:time/1000;
    for(const w of walkers){w.group.position.set(w.x+Math.sin(t*.16+w.phase)*.65,Math.abs(Math.sin(t*2+w.phase))*.025,w.z+Math.cos(t*.16+w.phase)*.5);w.group.rotation.y=Math.sin(t*.16+w.phase)*.7;}
    renderer.render(scene,camera);
  }
  try {
    scene=new THREE.Scene();scene.background=new THREE.Color(0xeaf6fc);scene.fog=new THREE.Fog(0xeaf6fc,22,47);
    camera=new THREE.PerspectiveCamera(36,1,.1,100);camera.position.set(0,16,23);camera.lookAt(0,0,0);
    renderer=new THREE.WebGLRenderer({antialias:true,powerPreference:'low-power'});renderer.setPixelRatio(Math.min(devicePixelRatio,1.5));document.querySelector('#scene').append(renderer.domElement);
    scene.add(new THREE.HemisphereLight(0xffffff,0xa2c5d2,1.2));const light=new THREE.DirectionalLight(0xfff4df,.7);light.position.set(-5,10,8);scene.add(light);
    const floor=mesh(new THREE.CircleGeometry(11,70),0xfafcfd);floor.rotation.x=-Math.PI/2;floor.position.y=-.04;scene.add(floor);
    const ring=mesh(new THREE.RingGeometry(10.8,11.1,70),0xc9e2ed);ring.rotation.x=-Math.PI/2;scene.add(ring);
    for(let i=0;i<8;i++){const angle=i*Math.PI/4;const island=mesh(new THREE.CylinderGeometry(.8,.9,.1,24),[0xa1d9de,0xb4d1ef,0xe8d4ae][i%3]);island.position.set(Math.cos(angle)*8.7,.03,Math.sin(angle)*8.7);scene.add(island);}
    new ResizeObserver(([entry])=>{const{width,height}=entry.contentRect;renderer.setSize(width,height);camera.aspect=width/height;camera.updateProjectionMatrix();}).observe(document.querySelector('#scene'));
    document.addEventListener('visibilitychange',()=>{if(document.hidden)cancelAnimationFrame(frame);else frame=requestAnimationFrame(animate);});
    frame=requestAnimationFrame(animate);
    renderer.domElement.addEventListener('click',event=>{const box=renderer.domElement.getBoundingClientRect(),ray=new THREE.Raycaster();ray.setFromCamera(new THREE.Vector2((event.clientX-box.left)/box.width*2-1,-(event.clientY-box.top)/box.height*2+1),camera);const hits=ray.intersectObjects(walkers.map(w=>w.group),true);const walker=walkers.find(w=>hits.some(h=>{let p=h.object;while(p){if(p===w.group)return true;p=p.parent;}return false;}));if(walker?.friend)document.dispatchEvent(new CustomEvent('plaza-friend',{detail:walker.friend}));});
  } catch {document.querySelector('#scene-fallback').hidden=false;}
  window.plazaScene={update,pause:()=>{paused=!paused;return paused;},colors};
})();
