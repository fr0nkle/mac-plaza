'use strict';
const fs=require('node:fs/promises'),path=require('node:path');
// Windows Error Reporting text only. Never include memory dumps, whose contents
// cannot be reliably stripped of account credentials or journal data.
async function crashReports(localAppData,now=Date.now()){
 if(!localAppData)return[];const candidates=[];
 for(const kind of['ReportArchive','ReportQueue']){const base=path.join(localAppData,'Microsoft/Windows/WER',kind);let dirs;try{dirs=await fs.readdir(base,{withFileTypes:true});}catch{continue;}
 for(const dir of dirs.slice(0,1000)){if(!dir.isDirectory()||!/^AppCrash_Plaza\.exe_/i.test(dir.name))continue;const file=path.join(base,dir.name,'Report.wer');try{const stat=await fs.lstat(file);if(stat.isFile()&&!stat.isSymbolicLink()&&stat.size<=1024*1024&&stat.mtimeMs>now-30*86400000)candidates.push({file,date:stat.mtimeMs});}catch{}}
 }
 const reports=[];for(const{file}of candidates.sort((a,b)=>b.date-a.date).slice(0,10)){const data=await fs.readFile(file),text=data[0]===255&&data[1]===254?data.subarray(2).toString('utf16le'):data.toString('utf8');const fields=text.split(/\r?\n/).filter(line=>/^(EventType|AppName|AppVersion|AppPath|ReportIdentifier|Sig\[\d+\]\.(Name|Value))=/.test(line)).slice(0,80);reports.push(fields.join('\n'));}return reports;
}
module.exports={crashReports};
