'use strict';
const defaults = {width:1000,height:720,minWidth:720,minHeight:540};
// Restore only geometry that fits the current display. Monitor removal and
// malformed local saves must not strand the window offscreen.
function fitBounds(saved, area, minimum=defaults) {
  const finite = value => Number.isFinite(value);
  const width = Math.min(area.width, Math.max(minimum.minWidth, finite(saved?.width) ? saved.width : defaults.width));
  const height = Math.min(area.height, Math.max(minimum.minHeight, finite(saved?.height) ? saved.height : defaults.height));
  const x = finite(saved?.x) ? saved.x : area.x + (area.width-width)/2;
  const y = finite(saved?.y) ? saved.y : area.y + (area.height-height)/2;
  return {x:Math.round(Math.max(area.x,Math.min(x,area.x+area.width-width))),
    y:Math.round(Math.max(area.y,Math.min(y,area.y+area.height-height))),width:Math.round(width),height:Math.round(height)};
}
function displayArea(saved,areas,fallback){
  if(!saved||![saved.x,saved.y,saved.width,saved.height].every(Number.isFinite))return fallback;
  const overlap=a=>Math.max(0,Math.min(saved.x+saved.width,a.x+a.width)-Math.max(saved.x,a.x))*Math.max(0,Math.min(saved.y+saved.height,a.y+a.height)-Math.max(saved.y,a.y));
  return [...areas].sort((a,b)=>overlap(b)-overlap(a)).find(a=>overlap(a)>0)||fallback;
}
module.exports = {defaults,fitBounds,displayArea};
