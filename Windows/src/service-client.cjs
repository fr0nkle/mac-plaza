'use strict';
const {endpoint}=require('./core.cjs');
// Both platforms speak the existing authenticated /v1 protocol. The transport
// has no platform/community namespace, credential bypass, or backend changes.
class ServiceClient {
  constructor(fetcher=globalThis.fetch){this.fetch=fetcher;}
  async request(method,route,body,auth){
    if(!auth)throw new Error('Connect Discord first.');
    if(!/^\/v1\/[a-z0-9/-]+$/.test(route))throw new Error('Invalid service route.');
    const headers={'Content-Type':'application/json'};
    if(auth.token)headers.Authorization='Bearer '+auth.token;
    let response;
    try{response=await this.fetch(endpoint(auth.origin)+route,{method,headers,
      body:body===undefined?undefined:JSON.stringify(body),redirect:'error',signal:AbortSignal.timeout(20000)});}
    catch{throw new Error('The Plaza service is unavailable. Your saved notes and draft are safe. Try again when it is online.');}
    let text='';
    const decoder=new TextDecoder();let length=0;
    for await(const chunk of response.body||[]){length+=chunk.byteLength;if(length>8_000_000)throw new Error('Service response is too large.');text+=decoder.decode(chunk,{stream:true});}
    text+=decoder.decode();
    let data;try{data=JSON.parse(text);}catch{throw new Error('The service returned an unreadable response.');}
    if(!response.ok){const error=new Error(data.error||'The service rejected the request.');error.status=response.status;throw error;}
    return data;
  }
}
module.exports={ServiceClient};
