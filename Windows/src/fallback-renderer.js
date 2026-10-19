'use strict';
window.PlazaFallback=(()=>{
  function commands(context,list){
    context.beginPath();for(const [name,...args]of list){
      if(name==='path')commands(context,args[0]);
      else if(['fillStyle','strokeStyle','lineWidth','lineCap','lineJoin'].includes(name))context[name]=args[0];
      else if(name==='ellipseRect')context.ellipse(args[0]+args[2]/2,args[1]+args[3]/2,Math.abs(args[2]/2),Math.abs(args[3]/2),0,0,Math.PI*2);
      else if(name==='roundRect')context.roundRect(args[0],args[1],args[2],args[3],Math.max(0,args[4]));
      else if(name==='strokePath'||name==='fillPath'||name==='clipPath'){context[name==='strokePath'?'stroke':name==='fillPath'?'fill':'clip']();context.beginPath();}
      else if(name==='fillEllipse'||name==='strokeEllipse'){context.beginPath();context.ellipse(args[0]+args[2]/2,args[1]+args[3]/2,Math.abs(args[2]/2),Math.abs(args[3]/2),0,0,Math.PI*2);context[name==='fillEllipse'?'fill':'stroke']();context.beginPath();}
      else if(['save','restore','translate','rotate','scale','moveTo','lineTo','quadraticCurveTo','bezierCurveTo','closePath','arc','fillRect'].includes(name))context[name](...args);
    }
  }
  function texture(list){const canvas=document.createElement('canvas');canvas.width=canvas.height=256;commands(canvas.getContext('2d'),list);const result=new THREE.CanvasTexture(canvas);result.flipY=false;return result;}
  function model(a){if(!a.fallback)throw new Error('The original fallback artwork is unavailable.');const data=a.fallback,textures=data.faces.map(texture);let mask;
    function node(value){let object;
      if(value.geometry){const valueGeometry=value.geometry;let geometry;if(valueGeometry.primitive==='sphere')geometry=new THREE.SphereGeometry(1,20,16);else{geometry=new THREE.BufferGeometry();for(const[key,values]of Object.entries(valueGeometry.attributes))geometry.setAttribute(key,new THREE.Float32BufferAttribute(values,key==='uv'?2:3));geometry.setIndex(valueGeometry.indices);if(!geometry.attributes.normal)geometry.computeVertexNormals();}
        const appearance=valueGeometry.materials[0],color=new THREE.Color().setRGB(...appearance.color.slice(0,3));const material=appearance.face?new THREE.MeshBasicMaterial({map:textures[0],transparent:true,depthWrite:false}):new THREE.MeshPhongMaterial({color,specular:0x292929,shininess:24,side:appearance.doubleSided?THREE.DoubleSide:THREE.FrontSide});if(appearance.face)material.modulateType=6;object=new THREE.Mesh(geometry,material);if(appearance.face)mask=object;
      }else object=new THREE.Group();object.position.fromArray(value.position);object.scale.fromArray(value.scale);object.rotation.fromArray([...value.rotation,'XYZ']);for(const child of value.children)object.add(node(child));return object;
    }
    const content=node(data.head),meshes=new THREE.Group();content.scale.multiplyScalar(.9/.0108);content.position.y+=.378/.0108;meshes.add(content);
    const result={meshes,facelineColor:new THREE.Color().setRGB(...data.skin.slice(0,3)),_maskMesh:mask,
      setExpression(expression){mask.material.map=textures[expression===5||expression===11?4:expression===1?1:expression===4?2:expression===6?3:0];},
      dispose(){meshes.traverse(n=>{n.geometry?.dispose();n.material?.dispose();});textures.forEach(t=>t.dispose());}};return result;
  }
  function featureIcon(a,feature,w=144,h=96){const canvas=document.createElement('canvas');canvas.width=w;canvas.height=h;const c=canvas.getContext('2d');c.scale(w/144,h/96);commands(c,a.fallback.icons?.[feature]||[]);return canvas.toDataURL('image/png');}
  return{commands,model,featureIcon};
})();
