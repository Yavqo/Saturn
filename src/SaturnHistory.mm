#import "SaturnHistory.h"
#import "SaturnBookmarks.h"

NSNotificationName const SaturnHistoryChangedNotification = @"SaturnHistoryChanged";

static const NSUInteger kMaxEntries = 10000;
static const NSUInteger kPageEntries = 5000;

@implementation SaturnHistory {
    NSMutableArray<NSDictionary *> *_entries;
    BOOL _saveScheduled;
    dispatch_queue_t _io;
}

+ (instancetype)shared {
    static SaturnHistory *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[SaturnHistory alloc] init]; });
    return s;
}

+ (NSString *)filePath {
    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"Saturn"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:@"history.json"];
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _io = dispatch_queue_create("saturn.history.io", DISPATCH_QUEUE_SERIAL);
    _entries = [NSMutableArray array];
    NSData *data = [NSData dataWithContentsOfFile:[SaturnHistory filePath]];
    id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if ([json isKindOfClass:[NSArray class]]) {
        for (id e in json) {
            if ([e isKindOfClass:[NSDictionary class]] && [e[@"u"] isKindOfClass:[NSString class]] && [e[@"d"] isKindOfClass:[NSNumber class]]) [_entries addObject:e];
        }
    }
    return self;
}

- (NSArray<NSDictionary *> *)entries { return [_entries copy]; }

- (void)changed {
    [self scheduleSave];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SaturnHistoryChangedNotification object:self];
    });
}

- (void)scheduleSave {
    if (_saveScheduled) return;
    _saveScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self->_saveScheduled = NO;
        [self flush];
    });
}

- (void)flush {
    NSArray *snapshot = [_entries copy];
    dispatch_sync(_io, ^{
        NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot options:0 error:nil];
        if (data) [data writeToFile:[SaturnHistory filePath] atomically:YES];
    });
}

- (void)recordURL:(NSURL *)url title:(NSString *)title {
    NSString *scheme = url.scheme.lowercaseString;
    if (!url.host.length || !([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])) return;
    NSString *u = url.absoluteString;
    NSString *t = [title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!t.length) t = url.host;
    double now = [[NSDate date] timeIntervalSince1970];

    NSDictionary *latest = _entries.firstObject;
    if (latest && [latest[@"u"] isEqualToString:u] && now - [latest[@"d"] doubleValue] < 30) {
        // A reload or redirect bounce: refresh the title instead of adding a second visit
        _entries[0] = @{@"u": u, @"t": t, @"d": latest[@"d"]};
    } else {
        [_entries insertObject:@{@"u": u, @"t": t, @"d": @(now)} atIndex:0];
        if (_entries.count > kMaxEntries) [_entries removeObjectsInRange:NSMakeRange(kMaxEntries, _entries.count - kMaxEntries)];
    }
    [self changed];
}

- (void)removeURLString:(NSString *)url visitedAt:(double)seconds {
    for (NSInteger i = 0; i < (NSInteger)_entries.count; i++) {
        NSDictionary *e = _entries[i];
        if ([e[@"u"] isEqualToString:url] && fabs([e[@"d"] doubleValue] - seconds) < 0.01) {
            [_entries removeObjectAtIndex:i];
            [self changed];
            return;
        }
    }
}

- (void)clearSince:(NSDate *)date {
    if (!date) [_entries removeAllObjects];
    else {
        double cutoff = date.timeIntervalSince1970;
        NSIndexSet *drop = [_entries indexesOfObjectsPassingTest:^BOOL(NSDictionary *e, NSUInteger idx, BOOL *stop) { (void)idx; (void)stop; return [e[@"d"] doubleValue] >= cutoff; }];
        [_entries removeObjectsAtIndexes:drop];
    }
    [self changed];
}

#pragma mark Address bar suggestions

static NSString *SHStripURL(NSString *u) {
    NSString *s = u.lowercaseString;
    for (NSString *p in @[@"https://", @"http://"]) if ([s hasPrefix:p]) { s = [s substringFromIndex:p.length]; break; }
    if ([s hasPrefix:@"www."]) s = [s substringFromIndex:4];
    return s;
}

- (NSArray<NSDictionary *> *)suggestionsForQuery:(NSString *)query limit:(NSUInteger)limit {
    NSString *q = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].lowercaseString;
    if (!q.length) return @[];
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    for (NSString *t in [q componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]) if (t.length) [tokens addObject:t];
    NSString *qStripped = SHStripURL(q);
    double now = [[NSDate date] timeIntervalSince1970];

    // One candidate per page: keep the newest title, count visits
    NSMutableDictionary<NSString *, NSMutableDictionary *> *byKey = [NSMutableDictionary dictionary];
    for (NSDictionary *e in _entries) {
        NSString *key = [SaturnBookmarks keyForURL:[NSURL URLWithString:e[@"u"]]];
        NSMutableDictionary *c = byKey[key];
        if (c) { c[@"visits"] = @([c[@"visits"] integerValue] + 1); continue; }
        byKey[key] = [@{@"url": e[@"u"], @"title": e[@"t"] ?: @"", @"visits": @1, @"last": e[@"d"], @"bookmark": @NO} mutableCopy];
    }
    for (NSDictionary *b in [SaturnBookmarks shared].items) {
        NSString *key = [SaturnBookmarks keyForURL:[NSURL URLWithString:b[@"url"]]];
        NSMutableDictionary *c = byKey[key];
        if (c) { c[@"bookmark"] = @YES; if ([b[@"title"] length]) c[@"title"] = b[@"title"]; }
        else byKey[key] = [@{@"url": b[@"url"], @"title": b[@"title"] ?: @"", @"visits": @0, @"last": @0, @"bookmark": @YES} mutableCopy];
    }

    NSMutableArray<NSDictionary *> *scored = [NSMutableArray array];
    for (NSDictionary *c in byKey.allValues) {
        NSString *url = SHStripURL(c[@"url"]);
        NSString *title = [c[@"title"] lowercaseString];
        NSString *host = [url componentsSeparatedByString:@"/"].firstObject;
        BOOL all = YES;
        for (NSString *t in tokens) if (![url containsString:t] && ![title containsString:t]) { all = NO; break; }
        if (!all) continue;

        double score = 0;
        if ([url hasPrefix:qStripped]) score += 100;
        if ([host hasPrefix:qStripped]) score += 80;
        if ([title hasPrefix:q]) score += 60;
        if ([host containsString:q]) score += 30;
        if ([title containsString:[@" " stringByAppendingString:q]]) score += 20;
        score += 10;
        if ([c[@"bookmark"] boolValue]) score += 40;
        score += MIN(10, [c[@"visits"] integerValue]) * 3;
        if ([c[@"last"] doubleValue] > 0) score += 20.0 / (1.0 + (now - [c[@"last"] doubleValue]) / 86400.0);
        // Prefer a site's front page over deep links when the query looks like a domain
        if ([host isEqualToString:url] || [url isEqualToString:[host stringByAppendingString:@"/"]]) score += 15;
        [scored addObject:@{@"score": @(score), @"item": c}];
    }
    [scored sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"score"] compare:a[@"score"]];
    }];
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *s in scored) {
        NSDictionary *c = s[@"item"];
        NSString *t = [c[@"title"] length] ? c[@"title"] : SHStripURL(c[@"url"]);
        [out addObject:@{@"kind": [c[@"bookmark"] boolValue] ? @"bookmark" : @"history", @"title": t, @"url": c[@"url"]}];
        if (out.count >= limit) break;
    }
    return out;
}

#pragma mark Built-in history page

- (NSString *)historyPageHTML {
    NSArray *slice = _entries.count > kPageEntries ? [_entries subarrayWithRange:NSMakeRange(0, kPageEntries)] : _entries;
    NSData *json = [NSJSONSerialization dataWithJSONObject:slice options:0 error:nil] ?: [@"[]" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *data = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    data = [data stringByReplacingOccurrencesOfString:@"<" withString:@"\\u003c"];
    data = [data stringByReplacingOccurrencesOfString:@" " withString:@"\\u2028"];
    data = [data stringByReplacingOccurrencesOfString:@" " withString:@"\\u2029"];

    static const char *const kTplC = R"HTML(<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>History</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
:root{--blue:#0064E0;--blue-hover:#0457CB;--ink:#1C2B33;--muted:#5D6C7B;--muted2:#647685;--soft:#F1F4F7;--border:#DEE3E9;--hair:rgba(10,19,23,.12);--red:#E41E3F}
*{box-sizing:border-box}
html{background:#fff}
body{margin:0;color:var(--ink);font:16px/24px -apple-system,BlinkMacSystemFont,"Helvetica Neue",Helvetica,Arial,sans-serif;letter-spacing:-.16px}
.wrap{max-width:860px;margin:0 auto;padding:56px 32px 120px}
header{display:flex;align-items:center;justify-content:space-between;gap:16px;flex-wrap:wrap}
h1{margin:0;font-size:36px;line-height:46px;font-weight:500;letter-spacing:normal}
.btn{font-family:inherit;font-weight:700;font-size:14px;line-height:20px;border-radius:100px;padding:10px 22px;min-height:44px;cursor:pointer;border:2px solid transparent;transition:background-color .2s ease-out;letter-spacing:-.14px}
.btn.outline{background:transparent;color:var(--blue);border-color:var(--hair)}
.btn.outline:hover{background:var(--soft)}
.btn.primary{background:var(--blue);color:#fff}
.btn.primary:hover{background:var(--blue-hover)}
.btn.secondary{background:var(--soft);color:var(--ink)}
.btn.secondary:hover{background:#E4E9EE}
.btn:focus-visible,input:focus-visible,a:focus-visible,.x:focus-visible{outline:2px solid #0143B5;outline-offset:3px}
.search{margin:28px 0 8px;position:relative}
.search input{width:100%;height:56px;border-radius:100px;border:1px solid var(--border);padding:0 24px 0 56px;font-family:inherit;font-size:16px;color:var(--ink);background:#fff}
.search input:focus{border-color:#0143B5;box-shadow:0 0 0 1px #0143B5;outline:none}
.search svg{position:absolute;left:22px;top:18px;width:20px;height:20px;stroke:var(--muted2);fill:none;stroke-width:1.8;stroke-linecap:round}
h2{margin:36px 0 8px;font-size:14px;line-height:20px;font-weight:700;color:var(--muted);letter-spacing:-.14px}
.row{display:flex;align-items:center;gap:14px;padding:10px 12px;border-radius:16px}
.row:hover{background:var(--soft)}
.av{flex:none;width:36px;height:36px;border-radius:50%;background:var(--soft);color:var(--muted);font-weight:700;font-size:14px;display:flex;align-items:center;justify-content:center;text-transform:uppercase}
.row:hover .av{background:#fff}
.main{flex:1;min-width:0}
.main a{display:block;color:var(--ink);text-decoration:none;font-size:15px;line-height:22px;font-weight:500;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.main a:hover{text-decoration:underline}
.host{font-size:13px;line-height:18px;color:var(--muted);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.time{flex:none;font-size:13px;color:var(--muted)}
.x{flex:none;width:32px;height:32px;border-radius:50%;border:0;background:transparent;cursor:pointer;color:var(--muted);opacity:0;display:flex;align-items:center;justify-content:center}
.row:hover .x,.x:focus-visible{opacity:1}
.x:hover{background:#E4E9EE;color:var(--ink)}
.x svg{width:12px;height:12px;stroke:currentColor;stroke-width:2;stroke-linecap:round}
.empty{margin:80px 0;text-align:center;color:var(--muted)}
.empty b{display:block;font-size:24px;line-height:30px;font-weight:500;color:var(--ink);margin-bottom:8px}
.scrim{position:fixed;inset:0;background:rgba(10,19,23,.45);display:none;align-items:center;justify-content:center;padding:16px;opacity:0;transition:opacity .2s}
.scrim.on{display:flex;opacity:1}
.card{background:#fff;border-radius:24px;padding:28px;width:100%;max-width:420px;border:1px solid var(--hair)}
.card h3{margin:0 0 4px;font-size:24px;line-height:30px;font-weight:500}
.card p{margin:0 0 16px;color:var(--muted);font-size:14px;line-height:20px}
.opt{display:flex;align-items:center;gap:12px;padding:12px 14px;border-radius:16px;cursor:pointer}
.opt:hover{background:var(--soft)}
.opt input{accent-color:var(--blue);width:20px;height:20px;margin:0}
.actions{display:flex;justify-content:flex-end;gap:10px;margin-top:20px}
@media (max-width:767px){.wrap{padding:32px 16px 80px}h1{font-size:28px;line-height:34px}.time{display:none}}
@media (prefers-reduced-motion:reduce){*{transition:none!important}}
</style></head>
<body><div class="wrap">
<header><h1>History</h1><button class="btn outline" id="clearBtn">Clear browsing data…</button></header>
<div class="search"><svg viewBox="0 0 24 24"><circle cx="11" cy="11" r="7"/><path d="M20 20l-4-4"/></svg><input id="q" type="search" placeholder="Search history" autocomplete="off" aria-label="Search history"></div>
<div id="list"></div>
</div>
<div class="scrim" id="scrim"><div class="card" role="dialog" aria-modal="true" aria-labelledby="mt">
<h3 id="mt">Clear browsing data</h3><p>This removes visited pages from your history. It can’t be undone.</p>
<label class="opt"><input type="radio" name="r" value="hour"> Last hour</label>
<label class="opt"><input type="radio" name="r" value="today"> Today</label>
<label class="opt"><input type="radio" name="r" value="all" checked> All time</label>
<div class="actions"><button class="btn secondary" id="cancel">Cancel</button><button class="btn primary" id="confirm">Clear</button></div>
</div></div>
<script>
var items=__DATA__;
var $=function(s){return document.querySelector(s)};
function host(u){try{return new URL(u).host.replace(/^www\./,'')}catch(e){return u}}
function dayKey(ts){var d=new Date(ts*1000);return new Date(d.getFullYear(),d.getMonth(),d.getDate()).getTime()}
function dayLabel(ts){var d=new Date(ts*1000),n=new Date(),diff=Math.round((dayKey(Date.now()/1000)-dayKey(ts))/864e5);
 if(diff===0)return'Today';if(diff===1)return'Yesterday';
 return d.toLocaleDateString(undefined,{weekday:'long',month:'long',day:'numeric',year:d.getFullYear()!==n.getFullYear()?'numeric':undefined})}
function post(m){try{webkit.messageHandlers.saturnHistory.postMessage(m)}catch(e){}}
function el(t,c,x){var e=document.createElement(t);if(c)e.className=c;if(x!=null)e.textContent=x;return e}
function render(){
 var q=$('#q').value.trim().toLowerCase(),list=$('#list');list.textContent='';
 var shown=items.filter(function(i){return!q||(i.t||'').toLowerCase().indexOf(q)>-1||i.u.toLowerCase().indexOf(q)>-1});
 if(!shown.length){var e=el('div','empty');e.appendChild(el('b',null,q?'No matches':'No history yet'));e.appendChild(el('span',null,q?'Try a different search.':'Pages you visit will show up here.'));list.appendChild(e);return}
 var last=null;
 shown.forEach(function(i){
  var k=dayKey(i.d);if(k!==last){last=k;list.appendChild(el('h2',null,dayLabel(i.d)))}
  var r=el('div','row'),h=host(i.u);
  r.appendChild(el('div','av',(h.replace(/[^a-z0-9]/gi,'')[0]||'•')));
  var m=el('div','main'),a=el('a',null,i.t||h);if(/^https?:/i.test(i.u))a.href=i.u;m.appendChild(a);m.appendChild(el('div','host',h));r.appendChild(m);
  r.appendChild(el('div','time',new Date(i.d*1000).toLocaleTimeString([],{hour:'numeric',minute:'2-digit'})));
  var x=el('button','x');x.title='Remove from history';x.setAttribute('aria-label','Remove from history');x.innerHTML='<svg viewBox="0 0 12 12"><path d="M1 1l10 10M11 1L1 11"/></svg>';
  x.onclick=function(){items=items.filter(function(j){return j!==i});post({action:'delete',u:i.u,d:i.d});render()};
  r.appendChild(x);list.appendChild(r)});
}
var t;$('#q').addEventListener('input',function(){clearTimeout(t);t=setTimeout(render,80)});
function openModal(on){$('#scrim').classList.toggle('on',on);if(on)$('#confirm').focus()}
$('#clearBtn').onclick=function(){openModal(true)};
$('#cancel').onclick=function(){openModal(false)};
$('#scrim').addEventListener('click',function(e){if(e.target.id==='scrim')openModal(false)});
document.addEventListener('keydown',function(e){if(e.key==='Escape')openModal(false)});
$('#confirm').onclick=function(){
 var v=document.querySelector('input[name=r]:checked').value,now=Date.now()/1000,since=0;
 if(v==='hour')since=now-3600;else if(v==='today')since=dayKey(now);
 items=items.filter(function(i){return i.d<since});
 post({action:'clear',since:since});openModal(false);render()};
render();
</script></body></html>)HTML";
    NSString *tpl = [NSString stringWithUTF8String:kTplC];
    return [tpl stringByReplacingOccurrencesOfString:@"__DATA__" withString:data];
}
@end


#pragma mark Built-in shortcuts page

static NSString *SaturnShortcutsPageHTML(void) {
    NSArray *groups = @[
        @[@"Tabs", @[
            @[@"New tab", @"⌘ T"], @[@"Close tab", @"⌘ W"], @[@"Reopen closed tab", @"⇧ ⌘ T"],
            @[@"Next tab", @"⌃ Tab  or  ⇧ ⌘ ]"], @[@"Previous tab", @"⌃ ⇧ Tab  or  ⇧ ⌘ ["],
            @[@"Go to tab 1–8", @"⌘ 1 … 8"], @[@"Go to last tab", @"⌘ 9"], @[@"Pin or unpin tab", @"⌥ ⌘ P"]]],
        @[@"Navigation", @[
            @[@"Focus address bar", @"⌘ L"], @[@"Back", @"⌘ ["], @[@"Forward", @"⌘ ]"],
            @[@"Reload", @"⌘ R"], @[@"Reload ignoring cache", @"⇧ ⌘ R"], @[@"Stop loading", @"⌘ ."]]],
        @[@"Page", @[
            @[@"Find in page", @"⌘ F"], @[@"Find next", @"⌘ G"], @[@"Find previous", @"⇧ ⌘ G"],
            @[@"Zoom in", @"⌘ +"], @[@"Zoom out", @"⌘ −"], @[@"Actual size", @"⌘ 0"],
            @[@"Bookmark this page", @"⌘ D"], @[@"Print", @"⌘ P"]]],
        @[@"Windows and Saturn", @[
            @[@"New window", @"⌘ N"], @[@"New private window", @"⇧ ⌘ N"], @[@"Close window", @"⇧ ⌘ W"],
            @[@"Ask Zarah", @"⌘ I"], @[@"History", @"⌘ Y"], @[@"Downloads", @"⇧ ⌘ J"],
            @[@"Show or hide favorites bar", @"⇧ ⌘ B"], @[@"Settings", @"⌘ ,"], @[@"This page", @"⌘ /"]]],
    ];
    NSMutableString *body = [NSMutableString string];
    for (NSArray *g in groups) {
        [body appendFormat:@"<section><h2>%@</h2>", g[0]];
        for (NSArray *r in g[1]) {
            NSMutableString *keys = [NSMutableString string];
            for (NSString *alt in [r[1] componentsSeparatedByString:@"  or  "]) {
                if (keys.length) [keys appendString:@"<span class=or>or</span>"];
                for (NSString *k in [alt componentsSeparatedByString:@" "]) if (k.length) [keys appendFormat:@"<kbd>%@</kbd>", k];
            }
            [body appendFormat:@"<div class=row><span>%@</span><span class=keys>%@</span></div>", r[0], keys];
        }
        [body appendString:@"</section>"];
    }
    static const char *const kC = R"HTML(<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Keyboard shortcuts</title>
<meta name="viewport" content="width=device-width,initial-scale=1"><style>
:root{--ink:#1C2B33;--muted:#5D6C7B;--soft:#F1F4F7;--hair:rgba(10,19,23,.12)}
*{box-sizing:border-box}body{margin:0;color:var(--ink);background:#fff;font:16px/24px -apple-system,BlinkMacSystemFont,"Helvetica Neue",Helvetica,Arial,sans-serif;letter-spacing:-.16px}
.wrap{max-width:860px;margin:0 auto;padding:56px 32px 120px}
h1{margin:0 0 8px;font-size:36px;line-height:46px;font-weight:500;letter-spacing:normal}
p.lead{margin:0 0 40px;color:var(--muted);font-size:18px;line-height:26px}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:32px}
section{background:var(--soft);border-radius:24px;padding:24px 28px}
h2{margin:0 0 12px;font-size:20px;line-height:26px;font-weight:500;letter-spacing:normal}
.row{display:flex;justify-content:space-between;align-items:center;gap:16px;padding:9px 0;border-top:1px solid var(--hair);font-size:15px}
.row:first-of-type{border-top:0}
.keys{display:flex;gap:4px;align-items:center;flex:none}
kbd{font:600 13px/1 -apple-system,BlinkMacSystemFont,"Helvetica Neue",sans-serif;background:#fff;border:1px solid var(--hair);border-radius:8px;padding:6px 8px;min-width:28px;text-align:center}
.or{color:var(--muted);font-size:12px;margin:0 4px}
@media (max-width:860px){.grid{grid-template-columns:1fr}.wrap{padding:32px 16px 80px}h1{font-size:28px;line-height:34px}}
</style></head><body><div class="wrap"><h1>Keyboard shortcuts</h1><p class="lead">Everything you can do without lifting your hands.</p><div class="grid">__BODY__</div></div></body></html>)HTML";
    return [[NSString stringWithUTF8String:kC] stringByReplacingOccurrencesOfString:@"__BODY__" withString:body];
}

#pragma mark - saturn:// scheme

@implementation SaturnSchemeHandler
+ (instancetype)shared {
    static SaturnSchemeHandler *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[SaturnSchemeHandler alloc] init]; });
    return s;
}
- (void)webView:(WKWebView *)webView startURLSchemeTask:(id<WKURLSchemeTask>)task {
    (void)webView;
    NSURL *url = task.request.URL;
    NSString *host = url.host;
    BOOL ok = [host isEqualToString:@"history"] || [host isEqualToString:@"shortcuts"];
    NSString *html = [host isEqualToString:@"history"] ? [[SaturnHistory shared] historyPageHTML]
                   : [host isEqualToString:@"shortcuts"] ? SaturnShortcutsPageHTML()
                   : @"<!doctype html><title>Not found</title><p>Not found";
    NSData *body = [html dataUsingEncoding:NSUTF8StringEncoding];
    NSHTTPURLResponse *resp = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:ok ? 200 : 404 HTTPVersion:@"HTTP/1.1"
                                                        headerFields:@{@"Content-Type": @"text/html; charset=utf-8", @"Cache-Control": @"no-store"}];
    [task didReceiveResponse:resp];
    [task didReceiveData:body];
    [task didFinish];
}
- (void)webView:(WKWebView *)webView stopURLSchemeTask:(id<WKURLSchemeTask>)task { (void)webView; (void)task; }
@end
