'use strict';
// The original Mac MiiFeatureIcon vector paths, in its 64-point coordinate space.
window.MiiIcon=kind=>{
  const svg=document.createElementNS('http://www.w3.org/2000/svg','svg');svg.setAttribute('viewBox','0 0 64 64');svg.setAttribute('aria-hidden','true');
  function path(d,fill=true,width=3){const p=document.createElementNS(svg.namespaceURI,'path');p.setAttribute('d',d);p.setAttribute('fill',fill?'currentColor':'none');if(!fill){p.setAttribute('stroke','currentColor');p.setAttribute('stroke-width',width);p.setAttribute('stroke-linecap','round');p.setAttribute('stroke-linejoin','round');}svg.append(p);}
  function ellipse(x,y,w,h,fill=true){const p=document.createElementNS(svg.namespaceURI,'ellipse');for(const[k,v]of Object.entries({cx:x+w/2,cy:y+h/2,rx:w/2,ry:h/2,fill:fill?'currentColor':'none',stroke:fill?'none':'currentColor','stroke-width':3}))p.setAttribute(k,v);svg.append(p);}
  const contour='M32 5C49 5 58 14 57 27C57 43 40 58 32 60C24 58 7 43 7 27C6 14 15 5 32 5Z';
  const mustache='M32 39C22 32 18 49 9 53Q23 58 32 48Q41 58 55 53C46 49 42 32 32 39Z';
  if(['face','makeup','wrinkles'].includes(kind)){path(contour,false);ellipse(19,25,5,6);ellipse(40,25,5,6);path('M22 42Q32 53 42 42',false);if(kind==='makeup'){ellipse(11,35,12,7);ellipse(41,35,12,7);}if(kind==='wrinkles')path('M24 16H40M24 20H40',false,2);}
  if(kind==='hair'){path(contour,false);path('M7 29C3 -3 61 -3 57 29L47 31 39 23 30 32 22 24 15 32Z');}
  if(kind==='brows')path('M4 38L27 26 27 34ZM60 38L37 26 37 34Z');
  if(kind==='eyes'){ellipse(3,21,26,21,false);ellipse(35,21,26,21,false);ellipse(14,22,9,19);ellipse(41,22,9,19);}
  if(kind==='nose')path('M38 8C36 21 23 33 25 44Q25 52 40 49',false,7);
  if(kind==='mouth'){path('M6 29C17 11 26 17 32 23C40 13 49 15 58 29Z');path('M6 35H58Q32 64 6 35');}
  if(kind==='glasses'||kind==='accessories'){ellipse(3,8,25,25,false);ellipse(36,8,25,25,false);path('M28 19Q32 16 36 19',false);path(mustache);ellipse(56,47,5,5);}
  if(kind==='mustache')path(mustache);
  if(kind==='beard')path('M10 25Q18 44 32 43Q47 44 54 25Q52 52 32 61Q12 52 10 25');
  if(kind==='mole'){path(contour,false,2);ellipse(42,39,7,7);}
  if(kind==='body'){ellipse(22,5,20,20);path('M28 28H36Q39 28 39 31V46Q39 49 36 49H28Q25 49 25 46V31Q25 28 28 28');path('M28 46V59M36 46V59',false,5);}
  return svg;
};
