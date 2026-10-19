'use strict';
const defaults = {width:1000,height:720,minWidth:720,minHeight:540};
// Restore only geometry that fits the current display. Monitor removal and
// malformed local saves must not strand the window offscreen.
function fitBounds(saved, area) {
  const finite = value => Number.isFinite(value);
  const width = Math.min(area.width, Math.max(defaults.minWidth, finite(saved?.width) ? saved.width : defaults.width));
  const height = Math.min(area.height, Math.max(defaults.minHeight, finite(saved?.height) ? saved.height : defaults.height));
  const x = finite(saved?.x) ? saved.x : area.x + (area.width-width)/2;
  const y = finite(saved?.y) ? saved.y : area.y + (area.height-height)/2;
  return {x:Math.round(Math.max(area.x,Math.min(x,area.x+area.width-width))),
    y:Math.round(Math.max(area.y,Math.min(y,area.y+area.height-height))),width:Math.round(width),height:Math.round(height)};
}
module.exports = {defaults,fitBounds};
