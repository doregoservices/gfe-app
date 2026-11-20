'use strict';
const vm=require('vm'),fs=require('fs'),assert=require('assert');
const listeners={}, nodes={};
function node(id){return nodes[id] ||= {id,innerHTML:'',value:'',textContent:'',classList:{toggle(){}} ,addEventListener(k,fn){listeners[id+':'+k]=fn}}}
const store={};
const context={console,Intl,Date,Math,Number,String,JSON,Object,Array,RegExp,Blob,crypto:require('crypto').webcrypto,localStorage:{getItem:k=>store[k]||null,setItem:(k,v)=>store[k]=v},document:{querySelector:node,querySelectorAll:()=>[],addEventListener:(k,fn)=>listeners['document:'+k]=fn,createElement:()=>({click(){}})},window:{addEventListener(){},scrollTo(){}},location:{hash:''},confirm:()=>true,FormData:class{constructor(f){this.f=f}get(k){return this.f.fields[k]??null}},URL:{createObjectURL(){return 'blob:test'},revokeObjectURL(){}},setTimeout};
vm.createContext(context);vm.runInContext(fs.readFileSync(__dirname+'/app.js','utf8'),context);
const run=s=>vm.runInContext(s,context);const submit=(id,fields)=>listeners['document:submit']({target:{id,fields},preventDefault(){}});const click=(action,id)=>listeners['document:click']({target:{closest:()=>({dataset:{action,id}})}});
for(const route of ['accueil','saisie','journaux','balance','points','audit','parametres']){context.location.hash='#'+route;run('render()');assert(nodes['#view'].innerHTML.length>100,route)}
context.location.hash='#saisie';run('render()');const date=run('today()'),initial=run('getTotals(co().ops).cash');
submit('entry-form',{date,kind:'vente',mode:'Espèces',label:'Test fictif',amount:'1250',reference:'TEST'});
assert.equal(run('getTotals(co().ops).cash'),initial);const id=run('co().ops.find(o=>o.label==="Test fictif").id');click('validate',id);assert.equal(run('getTotals(co().ops).cash'),initial+1250);click('reverse',id);assert.equal(run('getTotals(co().ops).cash'),initial);click('reverse',id);assert.equal(run('co().ops.filter(o=>o.originalId === '+JSON.stringify(id)+').length'),1);
run("state.company='b';state.role='dirigeant';render()");assert.equal(run('co().ops.length'),0);submit('entry-form',{date,kind:'vente',mode:'Espèces',label:'Interdit',amount:'500',reference:''});assert.equal(run('co().ops.length'),0);
console.log('OK : 7 pages, brouillon, validation, contre-passation, séparation des données de démo, rôle dirigeant simulé.');
