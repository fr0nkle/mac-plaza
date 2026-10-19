'use strict';
const { randomUUID } = require('node:crypto');
const DEFAULT_SERVICE = 'https://mac-plaza.tail1400d.ts.net';
function endpoint(value) {
  const url = new URL(value);
  if (!(url.protocol === 'https:' || (url.protocol === 'http:' && ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname))) ||
      url.username || url.password || url.search || url.hash || !['', '/'].includes(url.pathname)) throw new Error('Use an HTTPS service address.');
  return url.origin;
}
function avatar(name = 'You') {
  const features = { eyeColor: 0, browColor: 1, mouthColor: 0, glassesType: 1, glassesColor: 0,
    mustache: 0, beardType: 1, facialHairColor: 1, wrinkles: 0, makeup: 0, gender: 0,
    mole: false, flipHair: false, birthMonth: 0, birthDay: 0, favorite: false, creator: '', allowCopying: true, sharing: true };
  for (const key of 'eyeSize eyeStretch eyeRotation eyeY browSize browStretch browRotation browSpacing browY noseSize noseY mouthSize mouthStretch mouthY glassesSize glassesY mustacheSize mustacheY moleSize moleX moleY'.split(' ')) features[key] = 0.5;
  features.eyeY = 12 / 18; features.browY = 7 / 15; features.mouthY = 13 / 18;
  return { id: randomUUID(), name, skin: 0, hair: 33, hairColor: 1, eyes: 2, brows: 0, nose: 1, mouth: 23,
    face: 0, outfit: 0, glasses: false, beard: false, eyeSpacing: 2 / 12, featureHeight: 0.5, height: 0.5, build: 0.5, features };
}
function document() { return { avatar: avatar(), privateNotes: [], pending: {}, draft: { text: '', drawing: [], drawingDescription: '', visibility: 'public' } }; }
function visibility(note) { return note.private ? 'private' : note.audience ?? 'friends'; }
function draftVisibility(draft) {
  if (draft?.visibility) return draft.visibility;
  if (draft?.shared === false) return 'private';
  return draft?.audience ?? 'friends';
}
// Windows 0.4 called friends-only posts "public". Never broaden saved content
// when upgrading to the Mac 0.22+ three-audience protocol.
function migrateAudiences(store) {
  if (store.audienceVersion === 1) return false;
  for (const doc of Object.values(store.accounts || {})) {
    if (doc.draft?.visibility === 'public') doc.draft.visibility = 'friends';
    for (const note of Object.values(doc.pending || {})) if (note && note.audience == null) note.audience = 'friends';
  }
  store.audienceVersion = 1;
  return true;
}
function validateAvatar(value) {
  if (!value || typeof value.name !== 'string' || !value.name.trim() || [...value.name].length > 24 ||
      !/^[\da-f]{8}-(?:[\da-f]{4}-){3}[\da-f]{12}$/i.test(value.id) || !value.features) throw new Error('Choose a valid character.');
  for (const [object, limits] of [[value, {skin:5,hair:131,hairColor:7,eyes:59,brows:23,nose:17,mouth:35,face:11,outfit:11}],
    [value.features,{eyeColor:5,browColor:7,mouthColor:4,glassesType:8,glassesColor:5,mustache:5,beardType:5,facialHairColor:7,wrinkles:11,makeup:11,gender:1}]]) {
    for (const [key, maximum] of Object.entries(limits)) if (!Number.isInteger(object[key]) || object[key]<0 || object[key]>maximum) throw new Error('Character feature is out of range.');
  }
  for (const [object, keys] of [[value,'eyeSpacing featureHeight height build'],[value.features,'eyeSize eyeStretch eyeRotation eyeY browSize browStretch browRotation browSpacing browY noseSize noseY mouthSize mouthStretch mouthY glassesSize glassesY mustacheSize mustacheY moleSize moleX moleY']]) {
    for (const key of keys.split(' ')) if (!Number.isFinite(object[key]) || object[key]<0 || object[key]>1) throw new Error('Character feature is out of range.');
  }
  for(const [object,keys] of [[value,['glasses','beard']],[value.features,['mole','flipHair']]])for(const key of keys)if(typeof object[key]!=='boolean')throw new Error('Character feature is invalid.');
  return value;
}
function validateNote(note) {
  validateAvatar(note?.author);
  if (!note || !/^[\da-f-]{36}$/i.test(note.id) || typeof note.text !== 'string' || [...note.text].length > 280 ||
      typeof note.drawingDescription !== 'string' || [...note.drawingDescription].length > 160 ||
      !Array.isArray(note.drawing) || note.drawing.length > 512 ||
      note.drawing.reduce((n, s) => n + (s.points?.length ?? 60001), 0) > 20000 ||
      !note.drawing.every(s => typeof s.eraser === 'boolean' && s.points.every(p => Number.isFinite(p.x) && Number.isFinite(p.y) && p.x >= 0 && p.x <= 1 && p.y >= 0 && p.y <= 1)) ||
      (!note.text.trim() && !note.drawing.length) || (note.drawing.length && !note.drawingDescription.trim()) ||
      !Number.isFinite(note.created) || note.created < 0) throw new Error('Write up to 280 characters, and describe any drawing.');
  return note;
}
function wireNote(note) {
  validateNote(note);
  const audience = note.audience ?? 'friends';
  if (!['public', 'friends'].includes(audience)) throw new Error('Private notes cannot enter a shared feed.');
  const author = structuredClone(note.author);
  author.features.creator = ''; author.features.birthMonth = 0; author.features.birthDay = 0;
  return { id: note.sourceID || note.id, author, text: note.text.trim(), drawing: note.drawing,
    drawingDescription: note.drawingDescription.trim(), created: note.created, topic: note.topic || null, audience };
}
// Read current server state before applying this device's edits. Never replace
// notes with an empty local cache on first sign-in, or resurrect remote deletions.
const NOTE_RETENTION_SECONDS = 7 * 24 * 60 * 60;
function expired(note, now = Date.now()/1000) { return note.created <= now - NOTE_RETENTION_SECONDS; }
function pruneNotes(store, now = Date.now()/1000) {
  let removed = 0;
  for (const doc of Object.values(store.accounts || {})) {
    for (const key of ['privateNotes', 'remoteNotes']) if (Array.isArray(doc[key])) {
      const before = doc[key].length; doc[key] = doc[key].filter(n => !expired(n, now)); removed += before-doc[key].length;
    }
    for (const [id, note] of Object.entries(doc.pending || {})) if (note && expired(note, now)) { delete doc.pending[id]; removed++; }
  }
  return removed;
}
function mergeNotes(remote, ownerID, pending, now = Date.now()/1000) {
  const notes = new Map(remote.filter(n => n.ownerID === ownerID && !expired(n, now)).map(n => [n.sourceID, wireNote(n)]));
  for (const [id, change] of Object.entries(pending)) {
    if (change === null) notes.delete(id);
    else if (!expired(change, now)) notes.set(id, wireNote(change));
  }
  if (notes.size > 200 || [...notes.values()].reduce((total, note) => total + note.drawing.reduce((n, s) => n + s.points.length, 0), 0) > 60000) throw new Error('The shared journal has reached its limit. Remove a note or drawing first.');
  return [...notes.values()];
}
function publicAvatar(avatar) { validateAvatar(avatar);const value=structuredClone(avatar);value.features.creator='';value.features.birthMonth=0;value.features.birthDay=0;return value; }
module.exports = { visibility, draftVisibility, migrateAudiences, publicAvatar, DEFAULT_SERVICE, endpoint, avatar, document, validateAvatar, validateNote, wireNote, mergeNotes, NOTE_RETENTION_SECONDS, expired, pruneNotes };
