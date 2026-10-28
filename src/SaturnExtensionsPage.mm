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
@media (max-width:860px){.grid,.steps{grid-template-columns:1fr}.wrap{padding:32px 16px 80px}h1{font-size:28px;line-height:34px}}
@media (prefers-reduced-motion:reduce){*{transition:none!important}}
</style></head>
<body><div class="wrap">
<h1>Extensions</h1>
<p class="lead">Add features to Saturn. Each extension tells you what it can reach before you add it.</p>
<div class="tabs" role="tablist" id="tabs"></div>
<div id="view"></div>
</div>
<script>
(function(){
var state = __STATE__;
var tab = location.hash === '#store' ? 'store' : location.hash === '#build' ? 'build' : 'installed';
var query = '';
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
  if (item.icon) { var i = document.createElement('img'); i.alt = ''; i.src = 'saturn-extension://' + item.id + '/' + item.icon; i.onerror = function(){ d.removeChild(i); d.textContent = (item.name || '?').charAt(0); }; d.appendChild(i); }
  else d.textContent = (item.name || '?').charAt(0);
  return d;
}
function installedCard(e) {
  var sw = document.createElement('input');
  sw.type = 'checkbox'; sw.className = 'switch'; sw.checked = !!e.enabled; sw.disabled = !!e.error;
  sw.setAttribute('role', 'switch'); sw.setAttribute('aria-label', (e.enabled ? 'Turn off ' : 'Turn on ') + e.name);
  sw.addEventListener('change', function(){ post({action: 'toggle', id: e.id, enabled: sw.checked}); });
  var name = el('div', 'name', e.name, [e.version ? el('span', 'by', 'v' + e.version) : null, e.dev ? el('span', 'chip dev', 'Developer') : null]);
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
  var meta = el('div', 'meta', null, [el('div', 'name', i.name, [el('span', 'by', 'v' + i.version)]), el('div', 'by', i.author ? 'By ' + i.author : '')]);
  return el('div', 'card', null, [el('div', 'top', null, [icon(i), meta]), el('p', 'desc', i.description), chips(i), el('div', 'actions', null, [el('span', 'sp'), b])]);
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
  renderTabs();
  var v = document.getElementById('view');
  v.textContent = '';
  if (tab === 'store') viewStore(v); else if (tab === 'build') viewBuild(v); else viewInstalled(v);
}
window.__saturnExt = { update: function(s){ state = s; var a = document.activeElement, keep = a && a.tagName === 'INPUT' && a.type === 'search', pos = keep ? a.selectionStart : 0; render(); if (keep) { var n = document.querySelector('.search input'); if (n) { n.focus(); n.setSelectionRange(pos, pos); } } } };
window.addEventListener('hashchange', function(){ tab = location.hash === '#store' ? 'store' : location.hash === '#build' ? 'build' : 'installed'; render(); });
render();
post({action: 'state'});
})();
</script></body></html>)HTML";
    return [NSString stringWithUTF8String:kPage];
}
