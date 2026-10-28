#import <Foundation/Foundation.h>

// The saturn://extensions page: installed extensions, the store, and a short "build your own" guide.
// __STATE__ is replaced with the current state as JSON; the page asks the app for changes through the
// "saturnExtensions" message handler, and the app pushes updates back through window.__saturnExt.update().
NSString *SaturnExtensionsPageHTMLTemplate(void) {
    static const char *const kPage = R"HTML(<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>Extensions</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
:root{--blue:#0064E0;--blue-hover:#0457CB;--focus:#0143B5;--ink:#1C2B33;--muted:#5D6C7B;--muted2:#647685;--soft:#F1F4F7;--border:#DEE3E9;--hair:rgba(10,19,23,.12);--red:#E41E3F;--green:#31A24C}
*{box-sizing:border-box}
html{background:#fff}
body{margin:0;color:var(--ink);font:16px/24px -apple-system,BlinkMacSystemFont,"Helvetica Neue",Helvetica,Arial,sans-serif;letter-spacing:-.16px}
.wrap{max-width:1000px;margin:0 auto;padding:56px 32px 120px}
h1{margin:0;font-size:36px;line-height:46px;font-weight:500;letter-spacing:normal}
.lead{margin:8px 0 0;color:var(--muted);font-size:18px;line-height:26px;letter-spacing:normal;max-width:600px}
.tabs{display:flex;gap:8px;margin:32px 0 28px;flex-wrap:wrap}
.tab{font:inherit;font-weight:700;font-size:14px;line-height:20px;letter-spacing:-.14px;border:0;border-radius:100px;padding:10px 22px;min-height:44px;cursor:pointer;background:var(--soft);color:var(--ink);transition:background-color .2s ease-out}
.tab:hover{background:#E4E9EE}
.tab[aria-selected=true]{background:var(--blue);color:#fff}
.btn{font:inherit;font-weight:700;font-size:14px;line-height:20px;letter-spacing:-.14px;border-radius:100px;padding:10px 22px;min-height:44px;cursor:pointer;border:2px solid transparent;transition:background-color .2s ease-out;background:var(--soft);color:var(--ink)}
.btn:hover{background:#E4E9EE}
.btn.primary{background:var(--blue);color:#fff}
.btn.primary:hover{background:var(--blue-hover)}
.btn.outline{background:transparent;color:var(--blue);border-color:var(--hair)}
.btn.outline:hover{background:var(--soft)}
.btn.danger{color:var(--red)}
.btn[disabled]{background:transparent;color:rgba(68,86,100,.5);cursor:default;border-color:transparent}
.tab:focus-visible,.btn:focus-visible,input:focus-visible,a:focus-visible{outline:2px solid var(--focus);outline-offset:3px}
.list{display:flex;flex-direction:column;gap:16px}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:16px}
.card{background:var(--soft);border-radius:24px;padding:24px;display:flex;flex-direction:column;gap:14px}
.top{display:flex;align-items:flex-start;gap:16px}
.ic{flex:none;width:48px;height:48px;border-radius:16px;background:#fff;color:var(--ink);font-weight:700;font-size:20px;display:flex;align-items:center;justify-content:center;overflow:hidden;text-transform:uppercase}
.ic img{width:100%;height:100%;object-fit:cover}
.meta{flex:1;min-width:0}
.name{font-size:20px;line-height:26px;font-weight:500;letter-spacing:normal;display:flex;gap:10px;align-items:center;flex-wrap:wrap}
.by{font-size:13px;line-height:18px;color:var(--muted)}
.desc{margin:0;color:var(--ink);font-size:15px;line-height:22px}
.chips{display:flex;gap:6px;flex-wrap:wrap}
.chip{font-size:12px;line-height:16px;padding:4px 10px;border-radius:100px;background:#fff;color:var(--muted);border:1px solid var(--hair)}
.chip.warn{color:var(--red);border-color:rgba(228,30,63,.35)}
.chip.dev{color:var(--blue);border-color:rgba(0,100,224,.35)}
.actions{display:flex;gap:8px;flex-wrap:wrap;align-items:center}
.sp{flex:1}
.err{color:var(--red);font-size:13px;line-height:18px}
.switch{appearance:none;-webkit-appearance:none;width:48px;height:28px;border-radius:100px;background:#C5CDD5;position:relative;cursor:pointer;transition:background-color .2s ease-out;margin:0;flex:none}
.switch::after{content:"";position:absolute;top:3px;left:3px;width:22px;height:22px;border-radius:50%;background:#fff;transition:transform .2s cubic-bezier(.08,.52,.52,1)}
.switch:checked{background:var(--blue)}
.switch:checked::after{transform:translateX(20px)}
.search{position:relative;margin:0 0 20px}
.search input{width:100%;height:56px;border-radius:100px;border:1px solid var(--border);padding:0 24px 0 56px;font:inherit;color:var(--ink);background:#fff}
.search input:focus{border-color:var(--focus);box-shadow:0 0 0 1px var(--focus);outline:none}
.search svg{position:absolute;left:22px;top:18px;width:20px;height:20px;stroke:var(--muted2);fill:none;stroke-width:1.8;stroke-linecap:round}
.note{color:var(--muted);font-size:14px;line-height:20px;margin:0 0 16px}
.empty{margin:72px 0;text-align:center;color:var(--muted)}
.empty b{display:block;font-size:24px;line-height:30px;font-weight:500;color:var(--ink);margin-bottom:8px}
.empty .btn{margin-top:20px}
.steps{display:grid;grid-template-columns:repeat(3,1fr);gap:16px}
.step h3{margin:0;font-size:24px;line-height:30px;font-weight:300;letter-spacing:normal}
.step p{margin:0;color:var(--muted);font-size:15px;line-height:22px}
.step .actions{margin-top:auto}
pre{margin:24px 0 0;background:var(--soft);border-radius:24px;padding:24px;overflow:auto;font:13px/20px ui-monospace,SFMono-Regular,Menlo,monospace;letter-spacing:0}
h2{margin:40px 0 8px;font-size:24px;line-height:30px;font-weight:500;letter-spacing:normal}
table{border-collapse:collapse;width:100%;font-size:14px;line-height:20px}
td{padding:10px 0;border-top:1px solid var(--hair);vertical-align:top}
td:first-child{font:13px/20px ui-monospace,SFMono-Regular,Menlo,monospace;color:var(--ink);width:44%;padding-right:16px;letter-spacing:0}
td:last-child{color:var(--muted)}
.name a,.name a:visited{color:inherit;text-decoration:none}
.name a:hover{text-decoration:underline}
.ic{text-decoration:none}
.back{display:inline-flex;align-items:center;gap:8px;font-weight:700;font-size:14px;line-height:20px;letter-spacing:-.14px;color:var(--blue);text-decoration:none;margin:32px 0 20px;cursor:pointer}
.back:hover{text-decoration:underline}
.hero{display:flex;gap:24px;align-items:center;flex-wrap:wrap}
.hero .ic{width:96px;height:96px;border-radius:24px;font-size:36px;background:var(--soft)}
.hero .meta h2{margin:0;font-size:36px;line-height:46px;font-weight:500}
.hero .actions{margin-left:auto}
.shots{display:flex;gap:16px;overflow-x:auto;padding:0 0 8px;margin:32px 0 0;scroll-snap-type:x mandatory}
.shots figure{margin:0;flex:none;width:min(560px,86%);scroll-snap-align:start}
.shots img{display:block;width:100%;aspect-ratio:16/10;object-fit:cover;border-radius:24px;background:var(--soft);border:1px solid var(--hair);cursor:zoom-in}
.shots figcaption{margin:10px 4px 0;font-size:13px;line-height:18px;color:var(--muted)}
.prose{max-width:720px}
.prose p,.prose ul{margin:0 0 16px;font-size:16px;line-height:24px}
.prose h3,.prose h4,.prose h5{margin:28px 0 8px;font-size:20px;line-height:26px;font-weight:500;letter-spacing:normal}
.prose ul{padding-left:22px}
.prose code{font:13px/20px ui-monospace,SFMono-Regular,Menlo,monospace;background:var(--soft);border-radius:6px;padding:1px 6px;letter-spacing:0}
.prose a{color:var(--blue);text-decoration:none;font-weight:700}
.prose a:hover{text-decoration:underline}
.access{list-style:none;margin:0;padding:0;max-width:720px}
.access li{padding:12px 0;border-top:1px solid var(--hair);font-size:15px;line-height:22px}
.access li:first-child{border-top:0}
.facts{max-width:720px}
.facts td:first-child{font:inherit;color:var(--muted);width:34%;letter-spacing:inherit}
.facts td:last-child{color:var(--ink)}
.lb{position:fixed;inset:0;background:rgba(10,19,23,.82);display:flex;align-items:center;justify-content:center;padding:32px;z-index:10;flex-direction:column;gap:12px}
.lb img{max-width:100%;max-height:calc(100% - 48px);border-radius:24px;background:#fff}
.lb .cap{color:#fff;font-size:14px;line-height:20px}
@media (max-width:860px){.hero .actions{margin-left:0}.hero .meta h2{font-size:28px;line-height:34px}}
@media (max-width:860px){.grid,.steps{grid-template-columns:1fr}.wrap{padding:32px 16px 80px}h1{font-size:28px;line-height:34px}}
@media (prefers-reduced-motion:reduce){*{transition:none!important}}
</style></head>
<body><div class="wrap">
<div id="hdr"><h1>Extensions</h1>
<p class="lead">Add features to Saturn. Each extension tells you what it can reach before you add it.</p></div>
<div class="tabs" role="tablist" id="tabs"></div>
<div id="view"></div>
</div>
<script>
(function(){
var state = __STATE__;
var tab = 'installed', detailID = null;
var query = '';
function readHash() {
  var m = location.hash.match(/^#\/ext\/(.+)$/);
  if (m) { tab = 'detail'; detailID = decodeURIComponent(m[1]); }
  else { detailID = null; tab = location.hash === '#store' ? 'store' : location.hash === '#build' ? 'build' : 'installed'; }
}
var lastList = 'installed';
readHash();
function post(o){ try { window.webkit.messageHandlers.saturnExtensions.postMessage(o); } catch(e) {} }
function el(tag, cls, text, kids) {
  var n = document.createElement(tag);
  if (cls) n.className = cls;
  if (text !== undefined && text !== null) n.textContent = text;
  (kids || []).forEach(function(k){ if (k) n.appendChild(k); });
  return n;
}
function btn(label, cls, fn, disabled) {
  var b = el('button', 'btn ' + (cls || ''), label);
  b.type = 'button';
  if (disabled) b.disabled = true; else b.addEventListener('click', fn);
  return b;
}
var PERM = {storage: 'Saves its own data', activeTab: 'Talks to the open page', clipboardWrite: 'Copies to the clipboard', tabs: 'Opens tabs'};
function host(p) { return p.replace(/^[^:]+:\/\//, '').replace(/\/.*$/, ''); }
function chips(item, all) {
  var c = el('div', 'chips');
  var sites = item.sites || [];
  if (all || sites.some(function(s){ return s === '<all_urls>' || /^(\*|https?):\/\/\*\//.test(s); })) c.appendChild(el('span', 'chip warn', 'All websites'));
  else {
    var seen = {}, hosts = [];
    sites.forEach(function(s){ var h = host(s); if (!seen[h]) { seen[h] = 1; hosts.push(h); } });
    hosts.slice(0, 3).forEach(function(h){ c.appendChild(el('span', 'chip', h)); });
    if (hosts.length > 3) c.appendChild(el('span', 'chip', '+' + (hosts.length - 3) + ' more'));
  }
  (item.permissions || []).forEach(function(p){ c.appendChild(el('span', 'chip', PERM[p] || p)); });
  if (!c.childNodes.length) c.appendChild(el('span', 'chip', 'No special access'));
  return c;
}
function icon(item) {
  var d = el('div', 'ic');
  var src = item.iconURL || (item.icon ? 'saturn-extension://' + item.id + '/' + item.icon : null);
  if (src) { var i = document.createElement('img'); i.alt = ''; i.src = src; i.onerror = function(){ d.removeChild(i); d.textContent = (item.name || '?').charAt(0); }; d.appendChild(i); }
  else d.textContent = (item.name || '?').charAt(0);
  return d;
}
function detailLink(item) { var a = el('a', null, item.name); a.href = '#/ext/' + encodeURIComponent(item.id); a.setAttribute('aria-label', item.name + ', details'); return a; }
function installedCard(e) {
  var sw = document.createElement('input');
  sw.type = 'checkbox'; sw.className = 'switch'; sw.checked = !!e.enabled; sw.disabled = !!e.error;
  sw.setAttribute('role', 'switch'); sw.setAttribute('aria-label', (e.enabled ? 'Turn off ' : 'Turn on ') + e.name);
  sw.addEventListener('change', function(){ post({action: 'toggle', id: e.id, enabled: sw.checked}); });
  var name = el('div', 'name', null, [detailLink(e), e.version ? el('span', 'by', 'v' + e.version) : null, e.dev ? el('span', 'chip dev', 'Developer') : null]);
  var meta = el('div', 'meta', null, [name, el('div', 'by', e.author ? 'By ' + e.author : e.id)]);
  var actions = el('div', 'actions');
  if (e.dev) { actions.appendChild(btn('Reload', 'outline', function(){ post({action: 'reload', id: e.id}); })); actions.appendChild(btn('Show in Finder', 'outline', function(){ post({action: 'showInFinder', id: e.id}); })); }
  actions.appendChild(el('span', 'sp'));
  actions.appendChild(btn('Remove', 'danger', function(){ post({action: 'remove', id: e.id}); }));
  var kids = [el('div', 'top', null, [icon(e), meta, sw])];
  if (e.error) kids.push(el('div', 'err', e.error));
  else {
    if (e.description) kids.push(el('p', 'desc', e.description));
    kids.push(chips(e));
    if (!e.enabled) kids.push(el('div', 'by', 'Turned off. Reload open pages after turning an extension on or off.'));
  }
  kids.push(actions);
  return el('div', 'card', null, kids);
}
function storeCard(i) {
  var label = i.busy ? 'Adding…' : i.state === 'update' ? 'Update' : i.state === 'installed' ? 'Added' : i.state === 'dev' ? 'Loaded from folder' : 'Add';
  var b = btn(label, i.state === 'available' || i.state === 'update' ? 'primary' : '', function(){ post({action: 'install', id: i.id}); }, i.busy || i.state === 'installed' || i.state === 'dev');
  var meta = el('div', 'meta', null, [el('div', 'name', null, [detailLink(i), el('span', 'by', 'v' + i.version)]), el('div', 'by', i.author ? 'By ' + i.author : '')]);
  return el('div', 'card', null, [el('div', 'top', null, [icon(i), meta]), el('p', 'desc', i.description), chips(i), el('div', 'actions', null, [el('span', 'sp'), b])]);
}
var PERM_LONG = {storage: 'Save its own settings on this Mac', activeTab: 'Talk to the page you have open when you use its toolbar button', clipboardWrite: 'Copy text to your clipboard', tabs: 'Open new tabs'};
function inline(parent, text) {
  var re = /(\*\*[^*]+\*\*|`[^`]+`|\[[^\]]+\]\(https:\/\/[^)\s]+\))/g, last = 0, m;
  while ((m = re.exec(text))) {
    if (m.index > last) parent.appendChild(document.createTextNode(text.slice(last, m.index)));
    var tok = m[0];
    if (tok.charAt(0) === '*') parent.appendChild(el('strong', null, tok.slice(2, -2)));
    else if (tok.charAt(0) === '`') parent.appendChild(el('code', null, tok.slice(1, -1)));
    else {
      var mm = tok.match(/^\[([^\]]+)\]\((https:[^)]+)\)$/), a = el('a', null, mm[1]);
      a.href = '#'; a.addEventListener('click', (function(u){ return function(ev){ ev.preventDefault(); post({action: 'openURL', url: u}); }; })(mm[2]));
      parent.appendChild(a);
    }
    last = m.index + tok.length;
  }
  if (last < text.length) parent.appendChild(document.createTextNode(text.slice(last)));
}
// A small, safe Markdown subset: headings, paragraphs, lists, **bold**, `code` and https links.
function markdown(text) {
  var frag = document.createDocumentFragment(), lines = String(text).replace(/\r/g, '').split('\n'), i = 0, para = [];
  function flush() { if (para.length) { var p = el('p'); inline(p, para.join(' ')); frag.appendChild(p); para = []; } }
  while (i < lines.length) {
    var l = lines[i], h = l.match(/^(#{1,3})\s+(.*)$/), li = l.match(/^\s*[-*]\s+(.*)$/);
    if (!l.trim()) { flush(); i++; continue; }
    if (h) { flush(); var hd = el('h' + (h[1].length + 2)); inline(hd, h[2]); frag.appendChild(hd); i++; continue; }
    if (li) {
      flush();
      var ul = el('ul');
      while (i < lines.length && (li = lines[i].match(/^\s*[-*]\s+(.*)$/))) { var it = el('li'); inline(it, li[1]); ul.appendChild(it); i++; }
      frag.appendChild(ul);
      continue;
    }
    para.push(l.trim()); i++;
  }
  flush();
  return frag;
}
function lightbox(shots, index) {
  var lb = el('div', 'lb'), img = document.createElement('img'), cap = el('div', 'cap');
  lb.setAttribute('role', 'dialog'); lb.setAttribute('aria-label', 'Screenshot');
  function show(n) { index = (n + shots.length) % shots.length; img.src = shots[index].url; img.alt = shots[index].caption || ''; cap.textContent = shots[index].caption || ''; }
  function close() { document.removeEventListener('keydown', key); lb.parentNode && lb.parentNode.removeChild(lb); }
  function key(e) { if (e.key === 'Escape') close(); else if (e.key === 'ArrowRight') show(index + 1); else if (e.key === 'ArrowLeft') show(index - 1); }
  lb.addEventListener('click', close);
  lb.appendChild(img); lb.appendChild(cap);
  document.addEventListener('keydown', key);
  document.body.appendChild(lb);
  show(index);
}
function section(title) { return el('h2', null, title); }
function viewDetail(v) {
  var inst = state.installed.filter(function(x){ return x.id === detailID; })[0];
  var shop = state.store.items.filter(function(x){ return x.id === detailID; })[0];
  var it = inst || shop;
  var back = el('a', 'back', '← Back');
  back.href = '#' + lastList; back.addEventListener('click', function(ev){ ev.preventDefault(); if (history.length > 1) history.back(); else location.hash = '#' + lastList; });
  v.appendChild(back);
  if (!it) {
    v.appendChild(el('div', 'empty', null, [el('b', null, state.store.status === 'loading' ? 'Loading…' : 'Extension not found'), el('span', null, 'It may have been removed from the store.')]));
    return;
  }
  var d = {id: it.id, name: it.name, version: (inst || shop).version, author: it.author, description: it.description,
           long: (inst && inst.longDescription) || (shop && shop.longDescription) || '', shots: (inst && inst.screenshots && inst.screenshots.length ? inst.screenshots : (shop && shop.screenshots)) || [],
           homepage: (inst && inst.homepage) || (shop && shop.homepage) || null, sites: it.sites || [], permissions: it.permissions || [],
           icon: inst ? inst.icon : null, iconURL: shop && shop.iconURL};
  var actions = el('div', 'actions');
  if (inst) {
    var sw = document.createElement('input');
    sw.type = 'checkbox'; sw.className = 'switch'; sw.checked = !!inst.enabled; sw.disabled = !!inst.error;
    sw.setAttribute('role', 'switch'); sw.setAttribute('aria-label', 'Turn ' + inst.name + (inst.enabled ? ' off' : ' on'));
    sw.addEventListener('change', function(){ post({action: 'toggle', id: inst.id, enabled: sw.checked}); });
    if (shop && shop.state === 'update') actions.appendChild(btn('Update', 'primary', function(){ post({action: 'install', id: d.id}); }));
    if (inst.dev) { actions.appendChild(btn('Reload', 'outline', function(){ post({action: 'reload', id: d.id}); })); actions.appendChild(btn('Show in Finder', 'outline', function(){ post({action: 'showInFinder', id: d.id}); })); }
    actions.appendChild(sw);
    actions.appendChild(btn('Remove', 'danger', function(){ post({action: 'remove', id: d.id}); }));
  } else {
    actions.appendChild(btn(shop.busy ? 'Adding…' : 'Add', 'primary', function(){ post({action: 'install', id: d.id}); }, shop.busy));
  }
  var meta = el('div', 'meta', null, [el('h2', null, d.name), el('div', 'by', (d.author ? 'By ' + d.author + ' · ' : '') + 'v' + d.version + (inst && inst.dev ? ' · Developer copy' : '') + (inst && !inst.enabled ? ' · Turned off' : ''))]);
  v.appendChild(el('div', 'hero', null, [icon(d), meta, actions]));
  if (inst && inst.error) v.appendChild(el('p', 'err', inst.error));
  if (d.shots.length) {
    var row = el('div', 'shots');
    d.shots.forEach(function(sh, n){
      var im = document.createElement('img'); im.src = sh.url; im.alt = sh.caption || (d.name + ' screenshot ' + (n + 1)); im.tabIndex = 0;
      im.addEventListener('click', function(){ lightbox(d.shots, n); });
      im.addEventListener('keydown', function(e){ if (e.key === 'Enter') lightbox(d.shots, n); });
      var fig = el('figure', null, null, [im, sh.caption ? el('figcaption', null, sh.caption) : null]);
      row.appendChild(fig);
    });
    v.appendChild(row);
  }
  v.appendChild(section('About'));
  var prose = el('div', 'prose');
  if (d.long.trim()) prose.appendChild(markdown(d.long)); else prose.appendChild(el('p', null, d.description || 'No description yet.'));
  v.appendChild(prose);
  v.appendChild(section('What it can access'));
  var acc = el('ul', 'access');
  var all = d.sites.some(function(s){ return s === '<all_urls>' || /^(\*|https?):\/\/\*\//.test(s); });
  if (all) acc.appendChild(el('li', null, 'Read and change data on all websites'));
  else if (d.sites.length) { var seen = {}, hs = []; d.sites.forEach(function(s){ var h = host(s); if (!seen[h]) { seen[h] = 1; hs.push(h); } }); acc.appendChild(el('li', null, 'Read and change data on ' + hs.join(', '))); }
  d.permissions.forEach(function(p){ acc.appendChild(el('li', null, PERM_LONG[p] || p)); });
  if (!acc.childNodes.length) acc.appendChild(el('li', null, 'No special access'));
  v.appendChild(acc);
  v.appendChild(section('Details'));
  var t = document.createElement('table'); t.className = 'facts';
  var rows = [['Version', d.version], ['Id', d.id], ['Source', inst ? (inst.dev ? 'A folder on this Mac' : 'Extension store') : 'Extension store']];
  rows.forEach(function(r){ var tr = document.createElement('tr'); tr.appendChild(el('td', null, r[0])); tr.appendChild(el('td', null, r[1])); t.appendChild(tr); });
  if (d.homepage) {
    var tr = document.createElement('tr'), td = el('td'), a = el('a', null, d.homepage.replace(/^https:\/\//, ''));
    a.href = '#'; a.style.color = 'var(--blue)'; a.style.fontWeight = '700'; a.style.textDecoration = 'none';
    a.addEventListener('click', function(ev){ ev.preventDefault(); post({action: 'openURL', url: d.homepage}); });
    td.appendChild(a); tr.appendChild(el('td', null, 'Website')); tr.appendChild(td); t.appendChild(tr);
  }
  v.appendChild(t);
}
function renderTabs() {
  var t = document.getElementById('tabs');
  t.textContent = '';
  [['installed', 'Installed' + (state.installed.length ? ' (' + state.installed.length + ')' : '')], ['store', 'Store'], ['build', 'Build your own']].forEach(function(p){
    var b = el('button', 'tab', p[1]);
    b.type = 'button'; b.setAttribute('role', 'tab'); b.setAttribute('aria-selected', tab === p[0] ? 'true' : 'false');
    b.addEventListener('click', function(){ tab = p[0]; history.replaceState(null, '', '#' + tab); render(); });
    t.appendChild(b);
  });
}
function viewInstalled(v) {
  if (!state.installed.length) {
    var e = el('div', 'empty', null, [el('b', null, 'No extensions yet'), el('span', null, 'Browse the store, or build one of your own.')]);
    e.appendChild(btn('Open the store', 'primary', function(){ tab = 'store'; history.replaceState(null, '', '#store'); render(); }));
    v.appendChild(e);
    return;
  }
  var l = el('div', 'list');
  state.installed.forEach(function(e){ l.appendChild(installedCard(e)); });
  v.appendChild(l);
}
function viewStore(v) {
  var s = el('div', 'search');
  s.innerHTML = '<svg viewBox="0 0 24 24"><circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/></svg>';
  var inp = document.createElement('input');
  inp.type = 'search'; inp.placeholder = 'Search the store'; inp.value = query; inp.setAttribute('aria-label', 'Search the store');
  inp.addEventListener('input', function(){ query = inp.value; var pos = inp.selectionStart; render(); var n = document.querySelector('.search input'); if (n) { n.focus(); n.setSelectionRange(pos, pos); } });
  s.appendChild(inp);
  v.appendChild(s);
  var st = state.store;
  if (st.status === 'loading') { v.appendChild(el('p', 'note', 'Loading the store…')); }
  else if (st.status === 'offline') {
    var n = el('p', 'note', 'Couldn’t reach the online store, so this is the catalogue that came with Saturn. ');
    n.appendChild(btn('Try again', 'outline', function(){ post({action: 'refreshStore'}); }));
    v.appendChild(n);
  }
  var q = query.trim().toLowerCase();
  var items = st.items.filter(function(i){ return !q || (i.name + ' ' + i.description + ' ' + (i.author || '') + ' ' + (i.tags || []).join(' ')).toLowerCase().indexOf(q) >= 0; });
  if (!items.length && st.status !== 'loading') { v.appendChild(el('div', 'empty', null, [el('b', null, q ? 'Nothing matches “' + query + '”' : 'The store is empty'), el('span', null, 'Built something? Submit it from the “Build your own” tab.')])); return; }
  var g = el('div', 'grid');
  items.forEach(function(i){ g.appendChild(storeCard(i)); });
  v.appendChild(g);
}
function viewBuild(v) {
  var steps = el('div', 'steps');
  steps.appendChild(el('div', 'card step', null, [el('h3', null, '1. Start from the template'), el('p', null, 'Creates a ready-to-run extension in Documents ▸ Saturn Extensions, with a popup, a content script, styles and saved settings, and loads it.'),
    el('div', 'actions', null, [btn('Create from template', 'primary', function(){ post({action: 'createFromTemplate'}); })])]));
  steps.appendChild(el('div', 'card step', null, [el('h3', null, '2. Edit and test'), el('p', null, 'Change the files, then press Reload on its card. Pages that are already open need a refresh. Load any other folder the same way.'),
    el('div', 'actions', null, [btn('Load a folder…', '', function(){ post({action: 'loadUnpacked'}); })])]));
  steps.appendChild(el('div', 'card step', null, [el('h3', null, '3. Submit it'), el('p', null, 'Open a pull request that adds your folder to the store. Checks run automatically and a person reviews it before it is listed.'),
    el('div', 'actions', null, [btn('Read the submission guide', 'outline', function(){ post({action: 'openGuide', which: 'submit'}); })])]));
  v.appendChild(steps);
  var code = el('pre', null, '{\n  "manifest_version": 1,\n  "id": "yourname.hello",\n  "name": "Hello",\n  "version": "1.0.0",\n  "description": "Says hello on example.com.",\n  "author": "Your Name",\n  "permissions": ["storage"],\n  "content_scripts": [{\n    "matches": ["https://example.com/*"],\n    "js": ["content.js"],\n    "css": ["content.css"]\n  }],\n  "action": { "title": "Hello", "popup": "popup.html" }\n}');
  v.appendChild(code);
  v.appendChild(el('h2', null, 'What your extension can use'));
  var rows = [['saturn.storage.get / set / remove', 'Saved settings, up to 1 MB (needs “storage”).'], ['saturn.runtime.getURL(path)', 'Address of one of your own files.'], ['saturn.runtime.onMessage', 'Receive messages from your popup (content scripts).'],
    ['saturn.tabs.sendMessage(msg)', 'From your popup, talk to the open page (needs “activeTab”).'], ['saturn.tabs.open(url)', 'Open a page in a new tab (needs “tabs”).'], ['saturn.clipboard.writeText(text)', 'Copy text (needs “clipboardWrite”).']];
  var t = document.createElement('table');
  rows.forEach(function(r){ var tr = document.createElement('tr'); tr.appendChild(el('td', null, r[0])); tr.appendChild(el('td', null, r[1])); t.appendChild(tr); });
  v.appendChild(t);
  var more = el('div', 'actions'); more.style.marginTop = '24px';
  more.appendChild(btn('Developer guide', 'outline', function(){ post({action: 'openGuide', which: 'docs'}); }));
  v.appendChild(more);
}
function render() {
  var v = document.getElementById('view');
  v.textContent = '';
  var detail = tab === 'detail';
  document.getElementById('tabs').style.display = detail ? 'none' : '';
  document.getElementById('hdr').style.display = detail ? 'none' : '';
  if (detail) { viewDetail(v); return; }
  lastList = tab;
  renderTabs();
  if (tab === 'store') viewStore(v); else if (tab === 'build') viewBuild(v); else viewInstalled(v);
}
window.__saturnExt = { update: function(s){ state = s; var a = document.activeElement, keep = a && a.tagName === 'INPUT' && a.type === 'search', pos = keep ? a.selectionStart : 0; render(); if (keep) { var n = document.querySelector('.search input'); if (n) { n.focus(); n.setSelectionRange(pos, pos); } } } };
window.addEventListener('hashchange', function(){ readHash(); window.scrollTo(0, 0); render(); });
render();
post({action: 'state'});
})();
</script></body></html>)HTML";
    return [NSString stringWithUTF8String:kPage];
}
