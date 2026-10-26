'use strict';
// CI only: never run this to retry a blocked helper on a user's PC.
const assert=require('node:assert/strict'),path=require('node:path'),fs=require('node:fs'),{spawnSync}=require('node:child_process');
assert.equal(process.env.GITHUB_ACTIONS,'true','Only run in disposable GitHub Actions.');
const executable=path.resolve(__dirname,'../native/runtime/PlazaMusicProbe.exe');
const pe=fs.readFileSync(executable);assert.equal(pe.subarray(0,2).toString(),'MZ');assert.equal(pe.readUInt16LE(pe.readUInt32LE(60)+4),0x8664);
const result=spawnSync(executable,['--once'],{encoding:'utf8',windowsHide:true,timeout:10000});
assert.ifError(result.error);assert.equal(result.status,0,result.stderr);
const value=JSON.parse(result.stdout.trim());assert.equal(typeof value.available,'boolean');assert(Array.isArray(value.media)&&Array.isArray(value.audio));
console.log('Native x64 helper executed and emitted valid observations; media service available: '+value.available+'. This is not live music/speaker acceptance.');
