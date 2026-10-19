const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs/promises'),os=require('node:os'),path=require('node:path');
const birthday=require('../src/birthday.cjs'),core=require('../src/core.cjs');
test('primary birthday uses valid local month/day, leap days, persistent once/year receipt, and no profile in receipt',async()=>{
  const root=await fs.mkdtemp(path.join(os.tmpdir(),'birthday-'));try{const file=path.join(root,'birthday-celebration.json'),receipt=new birthday.BirthdayReceipt(file),primary=core.avatar('Primary'),date=new Date(2026,9,15,12);
    assert.equal(await receipt.claim(primary,date),false);primary.features.birthMonth=10;primary.features.birthDay=15;assert.equal(await receipt.claim(primary,date),true);assert.equal(await new birthday.BirthdayReceipt(file).claim(primary,date),false);assert.equal(await fs.readFile(file,'utf8'),'2026');assert.equal(await receipt.claim(primary,new Date(2027,9,15,12)),true);
    primary.features.birthMonth=2;primary.features.birthDay=29;assert.equal(await receipt.claim(primary,new Date(2028,2,1,12)),false);assert.equal(await receipt.claim(primary,new Date(2028,1,29,12)),true);
    for(const pair of [[2,30],[4,31],[0,1],[13,1],[1.5,2],[1,0]])assert.equal(birthday.valid(...pair),false);for(const pair of [[0,0],[2,29],[12,31]])assert.equal(birthday.valid(...pair),true);
  }finally{await fs.rm(root,{recursive:true,force:true});}
});
test('birthday waits for an available plaza, safe mode/lock/sheets/coverage never consume a receipt',()=>{
  const ready={loaded:true,visible:true};assert.equal(birthday.eligible(ready),true);
  for(const key of ['demo','recoveryRequired','safeMode','locked','suspended','sheet','preview','covered','celebrating'])assert.equal(birthday.eligible({...ready,[key]:true}),false);
  assert.equal(birthday.eligible({...ready,visible:false}),false);
});
