'use strict';
// Run from an x64 VS developer environment with a Windows SDK (C++/WinRT).
const fs=require('node:fs'),path=require('node:path'),{spawnSync}=require('node:child_process');
const root=path.resolve(__dirname,'..'),output=path.join(root,'native/runtime');
fs.mkdirSync(output,{recursive:true});
const result=spawnSync(process.env.CXX||'cl.exe',['/nologo','/std:c++20','/EHsc','/O2','/MT','/DUNICODE','/D_UNICODE',path.join(root,'native/music_probe.cpp'),'/Fo'+path.join(output,'music_probe.obj'),'/Fe'+path.join(output,'PlazaMusicProbe.exe'),'/link','windowsapp.lib','ole32.lib'],{stdio:'inherit'});
if(result.error)throw result.error;
if(result.status!==0)process.exit(result.status||1);
fs.unlinkSync(path.join(output,'music_probe.obj'));
