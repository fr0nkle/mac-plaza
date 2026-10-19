const {test}=require('node:test'),assert=require('node:assert/strict');
const {ServiceClient}=require('../src/service-client.cjs');
test('transport requires a session, validates origins/routes, sends bearer auth and refuses redirects',async()=>{
  let seen;const client=new ServiceClient(async(url,options)=>{seen={url,options};return new Response('{"notes":[]}');});
  await assert.rejects(client.request('GET','/v1/notes'),/Connect Discord/);
  await assert.rejects(client.request('GET','/v1/notes',undefined,{origin:'http://example.com'}));
  await assert.rejects(client.request('GET','/v1/notes?token=secret',undefined,{origin:'https://example.com'}));
  assert.deepEqual(await client.request('GET','/v1/notes',undefined,{origin:'https://example.com',token:'fixture'}),{notes:[]});assert.equal(seen.options.redirect,'error');assert.equal(seen.options.headers.Authorization,'Bearer fixture');
});
test('transport retains status for authentication/revocation handling and bounds response bytes',async()=>{
  const auth={origin:'http://127.0.0.1:8787',token:'fixture'};
  await assert.rejects(new ServiceClient(async()=>new Response('{"error":"Revoked"}',{status:403})).request('GET','/v1/notes',undefined,auth),e=>e.status===403&&e.message==='Revoked');
  await assert.rejects(new ServiceClient(async()=>new Response('x'.repeat(8_000_001))).request('GET','/v1/notes',undefined,auth),/too large/);
  await assert.rejects(new ServiceClient(async()=>new Response('<html>')).request('GET','/v1/notes',undefined,auth),/unreadable/);
});
