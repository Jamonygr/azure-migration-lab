import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const ignore = new Set(['.git','.terraform','node_modules','bin','obj','work','.tools']);
function walk(dir) { return fs.readdirSync(dir,{withFileTypes:true}).flatMap(e=>ignore.has(e.name)?[]:e.isDirectory()?walk(path.join(dir,e.name)):[path.join(dir,e.name)]); }
const files=walk(root), errors=[];
const slug=s=>s.toLowerCase().replace(/<[^>]+>/g,'').replace(/[`*_~]/g,'').replace(/[^\p{L}\p{N}\s_-]/gu,'').replace(/ /g,'-');
function anchors(file) {
  const seen=new Map(), result=new Set();
  const text=fs.readFileSync(file,'utf8').replace(/^(?:```|~~~)[^\n]*\n[\s\S]*?^(?:```|~~~)\s*$/gm,'');
  for(const m of text.matchAll(/^#{1,6}\s+(.+?)\s*#*$/gm)) {const s=slug(m[1]);const n=seen.get(s)||0;result.add(n?s+'-'+n:s);seen.set(s,n+1);}
  for(const m of text.matchAll(/(?:id|name)=["']([^"']+)["']/g)) result.add(m[1]);
  return result;
}
let links=0;
for(const file of files.filter(f=>f.endsWith('.md'))) {
  const text=fs.readFileSync(file,'utf8').replace(/^(?:```|~~~)[^\n]*\n[\s\S]*?^(?:```|~~~)\s*$/gm,'');
  const refs=[...text.matchAll(/!?\[[^\]]*\]\(<?([^\s)>]+)>?(?:\s+"[^"]*")?\)/g),...text.matchAll(/(?:src|href)=["']([^"']+)["']/g)];
  for(const m of refs) {
    const uri=m[1].replace(/\\([_()[\]#*])/g,'$1');if(/^(?:[a-z]+:|\/\/)/i.test(uri))continue;
    links++;let decoded;try{decoded=decodeURIComponent(uri);}catch{errors.push(`${file}: invalid encoding ${uri}`);continue;}
    const [location,fragment]=decoded.split('#');const dest=location?path.resolve(path.dirname(file),location.split('?')[0]):file;
    if(!dest.startsWith(root+path.sep)&&dest!==root){errors.push(`${file}: outside repository ${uri}`);continue;}
    if(!fs.existsSync(dest)){errors.push(`${path.relative(root,file)}: missing ${uri}`);continue;}
    if(fragment&&dest.endsWith('.md')&&!anchors(dest).has(fragment))errors.push(`${path.relative(root,file)}: missing anchor ${uri}`);
  }
}
for(const file of files.filter(f=>f.endsWith('.svg'))) {
  const s=fs.readFileSync(file,'utf8');
  if(!/<svg\b/.test(s)||!s.includes('</svg>')||!s.includes('viewBox='))errors.push(`${file}: invalid SVG root/viewBox`);
  if(/<script\b|onload=|javascript:/i.test(s))errors.push(`${file}: active content in SVG`);
}
if(errors.length){console.error(errors.join('\n'));process.exitCode=1;}else console.log(`Documentation checks passed: ${links} local links; ${files.filter(f=>f.endsWith('.svg')).length} SVGs.`);
