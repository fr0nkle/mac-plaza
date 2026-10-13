const {test}=require('node:test'),assert=require('node:assert/strict');
const {validateFriends,FriendRoster,recipients}=require('../src/social.cjs'),core=require('../src/core.cjs');
const friend={discordID:'123456789012345678',displayName:'A friend',presence:'online'};
test('Discord snapshots require ready state, unique uint64 identities and bounded names',()=>{
  validateFriends({state:'ready',friends:[friend]});
  for(const value of [{state:'account-mismatch',friends:[friend]},{state:'connecting',friends:[friend]},{state:'ready',friends:[friend,friend]},{state:'ready',friends:[{...friend,discordID:'18446744073709551616'}]},{state:'ready',friends:[{...friend,displayName:'x'.repeat(81)}]}])assert.throws(()=>validateFriends(value));
});
test('automatic friends retain their own shared Mii; local assignment applies only to unlinked friends',()=>{
  const roster=new FriendRoster(),shared=core.avatar('Shared Mii'),assigned=core.avatar('Local Mii'),document={friendAssignments:{[friend.discordID]:assigned}};
  const [linked]=roster.resolve([friend],{friends:[{id:shared.id,discordID:friend.discordID,avatar:shared}]},document);assert.deepEqual(linked.avatar,shared);
  const [unlinked]=roster.resolve([friend],{friends:[]},document);assert.equal(unlinked.locallyAssignedAvatar,true);assert.equal(unlinked.avatar.hair,assigned.hair);assert.notEqual(unlinked.avatar.id,assigned.id);assert.equal(unlinked.avatar.name,friend.displayName);
});
test('temporary Miis remain stable for the session and never pretend to be a shared profile',()=>{
  const roster=new FriendRoster(),snapshot={friends:[]};const first=roster.resolve([friend],snapshot,{})[0],again=roster.resolve([friend],snapshot,{})[0];assert.deepEqual(first,again);assert.equal(first.temporaryAvatar,true);roster.reset();assert.notEqual(roster.resolve([friend],snapshot,{})[0].id,first.id);
});
test('hidden friends lose recipient grants and disappear; stale/offline games are excluded',()=>{
  const roster=new FriendRoster(),now=Date.now()/1000,games={games:[{discordID:friend.discordID,name:'Portal 2',observedAt:now,active:true}]};
  assert.equal(roster.resolve([friend],{friends:[]},{hiddenFriends:[friend.discordID]},games).length,0);assert.deepEqual(recipients([friend],[friend.discordID]),[]);
  assert.equal(roster.resolve([friend],{friends:[]},{},games)[0].activities.length,1);
  assert.equal(roster.resolve([{...friend,presence:'offline'}],{friends:[]},{},games)[0].activities,undefined);
  games.games[0].observedAt=now-91;assert.equal(roster.resolve([friend],{friends:[]},{},games)[0].activities,undefined);
});
