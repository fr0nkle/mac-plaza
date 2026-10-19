// Follow the actual independent native window; never enable an inline test UI.
async function miiverse(app){
  const end=Date.now()+20000;
  while(Date.now()<end){
    const page=app.windows().find(p=>!p.isClosed()&&p.url().includes('panel=miiverse'));
    if(page){await page.locator('#miiverse').waitFor({state:'visible'});return page;}
    await new Promise(resolve=>setTimeout(resolve,50));
  }
  throw Error('The independent Miiverse window did not open.');
}
async function closePanel(page){await page.click(await page.locator('#miiverse').isVisible()?'#miiverse-close':'#close-panel');}
module.exports={miiverse,closePanel};
