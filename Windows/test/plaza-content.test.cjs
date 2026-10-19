const{test}=require('node:test'),assert=require('node:assert/strict'),core=require('../src/core.cjs'),content=require('../src/plaza-content.cjs');
test('public Miis use verified identity, cannot borrow local/friend UUIDs, and gather by Steam ID',()=>{
 const primary=core.avatar('Primary'),f=core.avatar('Profile'),published=core.avatar('Posted primary'),stranger=core.avatar('Public author'),friends=[{id:'friend-account',discordID:'42',displayName:'Friend',avatar:f}],apps=[{label:'Portal 2',steamAppID:620,bundleID:'mac.portal'}];
 const notes=[{id:'a',ownerID:'friend-account',discordID:'42',author:published,topic:{steamAppID:620,bundleID:'steam.app.620'},text:'Hello'},{id:'b',ownerID:'stranger',author:stranger,text:'Hello'}];
 const context={avatars:[primary],primary,friends,notes,apps,population:20,accountID:'self'},roster=content.roster(context);assert.deepEqual(roster.avatars.map(a=>a.id),[primary.id,f.id,stranger.id]);assert.equal(roster.gathering[f.id.toLowerCase()],0);
 assert.equal(content.noteSpeech({...notes[1],author:f},context),undefined);assert.equal(content.noteSpeech({...notes[0],discordID:'99'},context),undefined);assert.equal(content.matchTopic({bundleID:'other',steamAppID:620},apps),0);
});
test('Discord speech uses current custom status and real recent games, never legacy notes, fabricated availability or mismatched identities',()=>{
 const now=Date.now()/1000,friend={id:'friend',discordID:'42',avatar:core.avatar(),displayName:'Friend',presence:'online',note:'Legacy profile note',customStatus:{discordID:'42',text:'Current status',observedAt:now},activities:[{name:'Portal',source:'discord',active:true,observedAt:now}]};
 assert.equal(content.friendSpeech(friend,0,now).text,'Current status');assert.equal(content.friendSpeech(friend,1,now).text,'Playing Portal');assert.equal(content.friendSpeech({...friend,presence:'offline',activities:[{...friend.activities[0],active:false}]},0,now).text,'Friend was recently playing Portal');assert.equal(content.friendSpeech({...friend,customStatus:null,activities:[]},0,now),undefined);
 const apps=[{label:'Pórtal 2!',bundleID:'a'},{label:'Another',bundleID:'b'}];assert.equal(content.matchActivity([{name:'portal2',source:'discord',active:false,observedAt:now}],apps,now),0);assert.equal(content.matchActivity([{name:'portal2',source:'discord',active:false,observedAt:now-7200}],apps,now),-1);assert.equal(content.matchActivity([{name:'portal2',source:'discord',active:false,observedAt:now}],[apps[0],apps[0]],now),-1);
});
test('speech selection rotates unread authored content, retains identity and deduplicates rendered speakers',()=>{
 const a=core.avatar('A'),b=core.avatar('B'),notes=[{id:'1',private:true,author:a,text:'Older unread',created:1},{id:'2',private:true,author:b,text:'Newer read',created:2,read:true},{id:'3',private:true,author:a,text:'Same author',created:0}],context={avatars:[a,b],primary:a,friends:[],notes,apps:[],rendered:[a.id,b.id],presentation:'journal'};
 assert.deepEqual(content.speech(context).map(n=>n.id),['1','2']);assert.equal(content.speech({...context,rendered:[b.id]}).length,1);
});
test('speech planner stays overhead and on-screen with pointers over authors, clearing controls and other cards',()=>{
 const size={width:1000,height:700},card={width:230,height:108},anchors=[{x:200,y:350},{x:600,y:350},{x:5,y:100}],places=content.placements(anchors,size,card,[],3);assert.equal(places.length,2);for(const p of places){const anchor=anchors[p.index];assert(p.y>=12&&p.y+p.height<anchor.y);assert(anchor.x>=p.x+27&&anchor.x<=p.x+p.width-27);}assert.equal(content.placements([{x:500,y:100}],size,card).length,0);assert.equal(content.placements([{x:200,y:350}],size,card,[{x:0,y:100,width:500,height:400}]).length,0);
});
