'use strict';
// Core Audio calls can wait on Windows audio services. Keep them in a
// disposable utility process so the plaza and quit controls remain responsive.
const native=require(process.argv[2]);
const owner=Number(process.argv[3]);
function sample(){try{process.parentPort.postMessage(native.environment(owner));}catch{}}
sample();setInterval(sample,500);
