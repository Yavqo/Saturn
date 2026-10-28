#import "SaturnExtensions.h"
#import <CommonCrypto/CommonDigest.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>
#import "YavqoTheme.h"

NSString *SaturnExtensionsPageHTMLTemplate(void);   // SaturnExtensionsPage.mm

NSNotificationName const SaturnExtensionsChangedNotification = @"SaturnExtensionsChanged";
NSNotificationName const SaturnExtensionOpenURLNotification = @"SaturnExtensionOpenURL";

static NSString *const kCatalogURL = @"https://raw.githubusercontent.com/Yavqo/Saturn/main/store/index.json";
static NSString *const kDocsURL = @"https://github.com/Yavqo/Saturn/blob/main/docs/extensions.md";
static NSString *const kSubmitURL = @"https://github.com/Yavqo/Saturn/blob/main/docs/extensions.md#submit-to-the-store";
static NSString *const kWorldPrefix = @"saturn-ext-";
static NSString *const kScriptMark = @"/*saturn-ext*/";
static NSString *const kExtScheme = @"saturn-extension";

static const NSUInteger kMaxTotalBytes = 5 * 1024 * 1024;
static const NSUInteger kMaxFileBytes = 1024 * 1024;
static const NSUInteger kMaxFiles = 200;
static const NSUInteger kMaxStorageBytes = 1024 * 1024;

#pragma mark - Helpers

static NSString *SEAppSupport(void) {
    NSString *base = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    return [base stringByAppendingPathComponent:@"Saturn"];
}
static NSString *SERoot(void) {
    NSString *d = [SEAppSupport() stringByAppendingPathComponent:@"Extensions"];
    [[NSFileManager defaultManager] createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil];
    return d;
}
static NSString *SEDataPath(NSString *extID) {
    NSString *d = [SERoot() stringByAppendingPathComponent:@".data"];
    [[NSFileManager defaultManager] createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil];
    return [d stringByAppendingPathComponent:[extID stringByAppendingString:@".json"]];
}
static NSString *SEStatePath(void) { return [SERoot() stringByAppendingPathComponent:@".state.json"]; }

static NSString *SEJSON(id obj) {
    if (!obj) return @"null";
    NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:NSJSONWritingFragmentsAllowed error:nil];
    NSString *s = d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"null";
    s = [s stringByReplacingOccurrencesOfString:@"<" withString:@"\\u003c"];
    s = [s stringByReplacingOccurrencesOfString:@" " withString:@"\\u2028"];
    s = [s stringByReplacingOccurrencesOfString:@" " withString:@"\\u2029"];
    return s;
}

static BOOL SERegexMatches(NSString *pattern, NSString *s) {
    return [s rangeOfString:pattern options:NSRegularExpressionSearch].location != NSNotFound;
}

static NSComparisonResult SEVersionCompare(NSString *a, NSString *b) {
    NSArray *x = [a componentsSeparatedByString:@"."], *y = [b componentsSeparatedByString:@"."];
    for (NSUInteger i = 0; i < MAX(x.count, y.count); i++) {
        NSInteger p = i < x.count ? [x[i] integerValue] : 0, q = i < y.count ? [y[i] integerValue] : 0;
        if (p != q) return p < q ? NSOrderedAscending : NSOrderedDescending;
    }
    return NSOrderedSame;
}

static BOOL SEValidID(NSString *s) {
    return [s isKindOfClass:[NSString class]] && s.length >= 3 && s.length <= 64 && SERegexMatches(@"^[a-z0-9]+([.-][a-z0-9]+)*$", s);
}
static BOOL SERelPathOK(id p) {
    if (![p isKindOfClass:[NSString class]]) return NO;
    NSString *s = p;
    return s.length > 0 && s.length <= 200 && ![s hasPrefix:@"/"] && ![s containsString:@".."] && ![s containsString:@"\\"] && ![s hasPrefix:@"."];
}

static NSString *SESha256(NSData *data) {
    uint8_t d[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, d);
    NSMutableString *h = [NSMutableString string];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [h appendFormat:@"%02x", d[i]];
    return h;
}

// Chrome-style match pattern -> anchored regular expression for JavaScript. nil when the pattern is invalid.
static NSString *SEMatchRegex(NSString *pat) {
    if (![pat isKindOfClass:[NSString class]]) return nil;
    if ([pat isEqualToString:@"<all_urls>"]) return @"^https?://.*$";
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"^(\\*|https?)://(\\*|\\*\\.[^/*:]+|[^/*:]+)(/.*)$" options:0 error:nil];
    NSTextCheckingResult *m = [re firstMatchInString:pat options:0 range:NSMakeRange(0, pat.length)];
    if (!m) return nil;
    NSString *scheme = [pat substringWithRange:[m rangeAtIndex:1]];
    NSString *host = [pat substringWithRange:[m rangeAtIndex:2]];
    NSString *path = [pat substringWithRange:[m rangeAtIndex:3]];
    NSString *(^esc)(NSString *) = ^NSString *(NSString *t) {
        NSMutableString *o = [NSMutableString string];
        for (NSUInteger i = 0; i < t.length; i++) {
            unichar c = [t characterAtIndex:i];
            if (c == '*') [o appendString:@".*"];
            else { if (strchr("\\.^$+?()[]{}|", c)) [o appendString:@"\\"]; [o appendFormat:@"%C", c]; }
        }
        return o;
    };
    NSString *hostRe = [host isEqualToString:@"*"] ? @"[^/:]+" : [host hasPrefix:@"*."] ? [NSString stringWithFormat:@"([^/:]+\\.)?%@", esc([host substringFromIndex:2])] : esc(host);
    return [NSString stringWithFormat:@"^%@://%@(:[0-9]+)?%@$", [scheme isEqualToString:@"*"] ? @"https?" : scheme, hostRe, esc(path)];
}

static NSString *SEMimeForPath(NSString *path) {
    NSString *ext = path.pathExtension.lowercaseString;
    static NSDictionary *known;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        known = @{@"html": @"text/html; charset=utf-8", @"js": @"text/javascript; charset=utf-8", @"css": @"text/css; charset=utf-8", @"json": @"application/json",
                  @"svg": @"image/svg+xml", @"png": @"image/png", @"jpg": @"image/jpeg", @"jpeg": @"image/jpeg", @"gif": @"image/gif", @"webp": @"image/webp",
                  @"ico": @"image/x-icon", @"woff": @"font/woff", @"woff2": @"font/woff2", @"txt": @"text/plain; charset=utf-8", @"md": @"text/plain; charset=utf-8"};
    });
    return known[ext] ?: @"application/octet-stream";
}

static NSSet<NSString *> *SEAllowedFileTypes(void) {
    static NSSet *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [NSSet setWithArray:@[@"json", @"js", @"css", @"html", @"svg", @"png", @"jpg", @"jpeg", @"gif", @"webp", @"ico", @"woff", @"woff2", @"txt", @"md"]]; });
    return s;
}
static NSSet<NSString *> *SEKnownPermissions(void) {
    static NSSet *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [NSSet setWithArray:@[@"storage", @"activeTab", @"clipboardWrite", @"tabs"]]; });
    return s;
}

static NSString *SEPermissionText(NSString *p) {
    if ([p isEqualToString:@"storage"]) return @"Save its own settings on this Mac";
    if ([p isEqualToString:@"activeTab"]) return @"Talk to the page you have open when you use its toolbar button";
    if ([p isEqualToString:@"clipboardWrite"]) return @"Copy text to your clipboard";
    if ([p isEqualToString:@"tabs"]) return @"Open new tabs";
    return p;
}

#pragma mark - Manifest

// Reads and checks an extension folder. On success returns the normalised extension dictionary; otherwise nil and *error is set.
static NSDictionary *SEParseExtension(NSString *dir, NSString * __strong *error) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *(^fail)(NSString *) = ^NSString *(NSString *m) { if (error) *error = m; return nil; };
    NSData *raw = [NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"manifest.json"]];
    if (!raw) { fail(@"manifest.json is missing."); return nil; }
    id parsed = [NSJSONSerialization JSONObjectWithData:raw options:0 error:nil];
    if (![parsed isKindOfClass:[NSDictionary class]]) { fail(@"manifest.json is not valid JSON."); return nil; }
    NSDictionary *m = parsed;

    // Folder contents: sizes, types, no links
    NSUInteger total = 0, files = 0;
    for (NSString *rel in [fm enumeratorAtPath:dir]) {
        if ([rel.lastPathComponent isEqualToString:@".DS_Store"]) continue;
        NSDictionary *attrs = [fm attributesOfItemAtPath:[dir stringByAppendingPathComponent:rel] error:nil];
        NSString *type = attrs[NSFileType];
        if ([type isEqualToString:NSFileTypeSymbolicLink]) { fail([NSString stringWithFormat:@"“%@” is a link. Links are not allowed.", rel]); return nil; }
        if ([type isEqualToString:NSFileTypeDirectory]) continue;
        files++;
        total += [attrs fileSize];
        if ([attrs fileSize] > kMaxFileBytes) { fail([NSString stringWithFormat:@"“%@” is larger than 1 MB.", rel]); return nil; }
        if (![SEAllowedFileTypes() containsObject:rel.pathExtension.lowercaseString]) { fail([NSString stringWithFormat:@"“%@” has a file type extensions can't include.", rel]); return nil; }
    }
    if (files > kMaxFiles || total > kMaxTotalBytes) { fail(@"The extension is larger than 5 MB or has more than 200 files."); return nil; }

    if (![m[@"manifest_version"] isEqual:@1]) { fail(@"manifest_version must be 1."); return nil; }
    NSString *extID = m[@"id"];
    if (!SEValidID(extID)) { fail(@"id must be 3–64 lowercase letters, numbers, dots or dashes, like yourname.my-extension."); return nil; }
    NSString *name = m[@"name"], *version = m[@"version"];
    if (![name isKindOfClass:[NSString class]] || !name.length || name.length > 45) { fail(@"name is required (up to 45 characters)."); return nil; }
    if (![version isKindOfClass:[NSString class]] || !SERegexMatches(@"^[0-9]+\\.[0-9]+\\.[0-9]+$", version)) { fail(@"version must look like 1.0.0."); return nil; }
    NSString *desc = [m[@"description"] isKindOfClass:[NSString class]] ? m[@"description"] : @"";
    if (desc.length > 200) { fail(@"description is longer than 200 characters."); return nil; }
    NSString *author = [m[@"author"] isKindOfClass:[NSString class]] ? m[@"author"] : @"";
    if (author.length > 60) { fail(@"author is longer than 60 characters."); return nil; }

    NSArray *perms = m[@"permissions"] ?: @[];
    if (![perms isKindOfClass:[NSArray class]]) { fail(@"permissions must be a list."); return nil; }
    for (id p in perms) if (![p isKindOfClass:[NSString class]] || ![SEKnownPermissions() containsObject:p]) { fail([NSString stringWithFormat:@"Unknown permission “%@”. Known: storage, activeTab, clipboardWrite, tabs.", p]); return nil; }

    NSMutableArray *scripts = [NSMutableArray array];
    NSMutableOrderedSet *sites = [NSMutableOrderedSet orderedSet];
    id cs = m[@"content_scripts"] ?: @[];
    if (![cs isKindOfClass:[NSArray class]] || [cs count] > 10) { fail(@"content_scripts must be a list of up to 10 entries."); return nil; }
    for (id e in cs) {
        if (![e isKindOfClass:[NSDictionary class]]) { fail(@"Each content_scripts entry must be an object."); return nil; }
        NSArray *matches = e[@"matches"];
        if (![matches isKindOfClass:[NSArray class]] || !matches.count || matches.count > 20) { fail(@"Each content_scripts entry needs 1–20 “matches” patterns."); return nil; }
        NSMutableArray *regexes = [NSMutableArray array];
        for (id p in matches) {
            NSString *re = SEMatchRegex(p);
            if (!re) { fail([NSString stringWithFormat:@"“%@” is not a valid match pattern (use https://example.com/* or <all_urls>).", p]); return nil; }
            [regexes addObject:re]; [sites addObject:p];
        }
        NSMutableArray *exclude = [NSMutableArray array];
        for (id p in (e[@"exclude_matches"] ?: @[])) { NSString *re = SEMatchRegex(p); if (!re) { fail([NSString stringWithFormat:@"“%@” is not a valid exclude pattern.", p]); return nil; } [exclude addObject:re]; }
        NSMutableArray *js = [NSMutableArray array], *css = [NSMutableArray array];
        for (NSString *key in @[@"js", @"css"]) {
            id list = e[key] ?: @[];
            if (![list isKindOfClass:[NSArray class]]) { fail([NSString stringWithFormat:@"“%@” must be a list of files.", key]); return nil; }
            for (id f in list) {
                BOOL isDir = NO;
                if (!SERelPathOK(f) || ![[f pathExtension].lowercaseString isEqualToString:key] || ![fm fileExistsAtPath:[dir stringByAppendingPathComponent:f] isDirectory:&isDir] || isDir) { fail([NSString stringWithFormat:@"Can't find %@ file “%@”.", key, f]); return nil; }
                [([key isEqualToString:@"js"] ? js : css) addObject:f];
            }
        }
        if (!js.count && !css.count) { fail(@"A content_scripts entry needs at least one js or css file."); return nil; }
        NSString *runAt = e[@"run_at"] ?: @"document_idle";
        if (![@[@"document_start", @"document_end", @"document_idle"] containsObject:runAt]) { fail(@"run_at must be document_start, document_end or document_idle."); return nil; }
        [scripts addObject:@{@"matches": regexes, @"exclude": exclude, @"js": js, @"css": css, @"runAt": runAt, @"allFrames": @([e[@"all_frames"] boolValue])}];
    }

    NSDictionary *action = [m[@"action"] isKindOfClass:[NSDictionary class]] ? m[@"action"] : nil;
    NSString *popup = action[@"popup"];
    if (popup) {
        BOOL isDir = NO;
        if (!SERelPathOK(popup) || ![popup.pathExtension.lowercaseString isEqualToString:@"html"] || ![fm fileExistsAtPath:[dir stringByAppendingPathComponent:popup] isDirectory:&isDir] || isDir) { fail([NSString stringWithFormat:@"Can't find popup page “%@”.", popup]); return nil; }
    }
    NSString *icon = m[@"icon"];
    if (icon && (!SERelPathOK(icon) || ![fm fileExistsAtPath:[dir stringByAppendingPathComponent:icon]])) { fail([NSString stringWithFormat:@"Can't find icon “%@”.", icon]); return nil; }
    NSMutableSet *accessible = [NSMutableSet set];
    for (id w in (m[@"web_accessible_resources"] ?: @[])) {
        if (!SERelPathOK(w) || ![fm fileExistsAtPath:[dir stringByAppendingPathComponent:w]]) { fail([NSString stringWithFormat:@"web_accessible_resources: can't find “%@”.", w]); return nil; }
        [accessible addObject:w];
    }
    if (icon) [accessible addObject:icon];
    if (!scripts.count && !popup) { fail(@"The extension does nothing: add content_scripts or an action with a popup."); return nil; }

    return @{@"id": extID, @"name": name, @"version": version, @"description": desc, @"author": author, @"permissions": perms,
             @"sites": sites.array, @"scripts": scripts, @"popup": popup ?: [NSNull null], @"popupWidth": @(MIN(600, MAX(200, [action[@"popup_width"] integerValue] ?: 340))),
             @"popupHeight": @(MIN(600, MAX(100, [action[@"popup_height"] integerValue] ?: 420))), @"title": action[@"title"] ?: name, @"icon": icon ?: [NSNull null],
             @"accessible": accessible.allObjects, @"dir": dir};
}

#pragma mark - Page scripts

static NSString *SEPreludeJS(NSString *extID, BOOL popup) {
    NSString *tpl = @R"JS((function(){
  if (window.saturn) return;
  var ID = __ID__, POPUP = __POPUP__;
  var handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.saturnExt;
  function call(op, args) {
    if (!handler) return Promise.reject(new Error('The Saturn extension API is not available here.'));
    return handler.postMessage({op: op, args: args || {}});
  }
  var listeners = [];
  var api = {
    id: ID,
    storage: {
      get: function(keys) { return call('storage.get', {keys: keys === undefined ? null : keys}); },
      set: function(items) { return call('storage.set', {items: items}); },
      remove: function(keys) { return call('storage.remove', {keys: keys}); },
      clear: function() { return call('storage.clear'); }
    },
    runtime: {
      id: ID,
      getURL: function(path) { return 'saturn-extension://' + ID + '/' + String(path).replace(/^\/+/, ''); },
      onMessage: { addListener: function(fn) { if (typeof fn === 'function') listeners.push(fn); } }
    },
    tabs: { open: function(url) { return call('tabs.open', {url: String(url)}); } },
    clipboard: { writeText: function(text) { return call('clipboard.write', {text: String(text)}); } }
  };
  if (POPUP) {
    api.tabs.active = function() { return call('tabs.active'); };
    api.tabs.sendMessage = function(message) { return call('tabs.sendMessage', {message: message}); };
  }
  Object.defineProperty(window, 'saturn', {value: Object.freeze(api)});
  Object.defineProperty(window, '__saturnDispatch', {value: function(message) {
    return new Promise(function(resolve) {
      var done = false, waiting = false;
      function respond(v) { if (!done) { done = true; resolve(v); } }
      for (var i = 0; i < listeners.length; i++) {
        try {
          var r = listeners[i](message, respond);
          if (r === true) waiting = true;
          else if (r && typeof r.then === 'function') { waiting = true; r.then(respond, function() { respond(undefined); }); }
          else if (r !== undefined) respond(r);
        } catch (e) { console.error('[Saturn extension ' + ID + ']', e); }
      }
      if (!waiting) setTimeout(function() { respond(undefined); }, 0);
      setTimeout(function() { respond(undefined); }, 5000);
    });
  }});
})();)JS";
    tpl = [tpl stringByReplacingOccurrencesOfString:@"__ID__" withString:SEJSON(extID)];
    return [tpl stringByReplacingOccurrencesOfString:@"__POPUP__" withString:popup ? @"true" : @"false"];
}

static NSString *SEReadFile(NSString *dir, NSString *rel) {
    return [NSString stringWithContentsOfFile:[dir stringByAppendingPathComponent:rel] encoding:NSUTF8StringEncoding error:nil] ?: @"";
}

static NSArray<WKUserScript *> *SEBuildScripts(NSDictionary *ext) {
    NSString *extID = ext[@"id"], *dir = ext[@"dir"];
    WKContentWorld *world = [WKContentWorld worldWithName:[kWorldPrefix stringByAppendingString:extID]];
    NSMutableArray *out = [NSMutableArray array];
    NSUInteger index = 0;
    for (NSDictionary *s in ext[@"scripts"]) {
        NSMutableString *css = [NSMutableString string], *js = [NSMutableString string];
        for (NSString *f in s[@"css"]) [css appendFormat:@"%@\n", SEReadFile(dir, f)];
        for (NSString *f in s[@"js"]) [js appendFormat:@"%@\n;\n", SEReadFile(dir, f)];
        NSString *styleID = [NSString stringWithFormat:@"%@:%lu", extID, (unsigned long)index++];
        NSString *src = [NSString stringWithFormat:
            @"%@\n(function(){\n"
            "var M=%@, X=%@, href=location.href;\n"
            "function t(l){for(var i=0;i<l.length;i++){if(new RegExp(l[i]).test(href))return true;}return false;}\n"
            "if(!t(M)||(X.length&&t(X)))return;\n"
            "%@\n"
            "var css=%@;\n"
            "if(css){var addStyle=function(){if(document.querySelector('style[data-saturn-extension=\"'+%@+'\"]'))return;var s=document.createElement('style');s.setAttribute('data-saturn-extension',%@);s.textContent=css;(document.head||document.documentElement).appendChild(s);};if(document.documentElement)addStyle();document.addEventListener('DOMContentLoaded',addStyle);}\n"
            "try{\n%@\n}catch(e){console.error('[Saturn extension '+%@+']',e);}\n"
            "})();",
            kScriptMark, SEJSON(s[@"matches"]), SEJSON(s[@"exclude"]), SEPreludeJS(extID, NO), css.length ? SEJSON(css) : @"null",
            SEJSON(styleID), SEJSON(styleID), js, SEJSON(extID)];
        BOOL start = [s[@"runAt"] isEqualToString:@"document_start"];
        [out addObject:[[WKUserScript alloc] initWithSource:src injectionTime:start ? WKUserScriptInjectionTimeAtDocumentStart : WKUserScriptInjectionTimeAtDocumentEnd
                                           forMainFrameOnly:![s[@"allFrames"] boolValue] inContentWorld:world]];
    }
    return out;
}

#pragma mark - Bridge (extension API calls from pages)

@interface SaturnExtensionBridge : NSObject <WKScriptMessageHandlerWithReply>
@property (nonatomic, weak) SaturnExtensions *owner;
@end

@interface SaturnExtensions ()
- (NSDictionary *)storageForID:(NSString *)extID;
- (void)setStorage:(NSDictionary *)data forID:(NSString *)extID;
- (SaturnExtensionBridge *)bridge;
@end

@implementation SaturnExtensionBridge

static NSString *SEExtensionIDForMessage(WKScriptMessage *m) {
    NSString *wn = m.world.name;
    if ([wn hasPrefix:kWorldPrefix]) return [wn substringFromIndex:kWorldPrefix.length];
    NSURL *u = m.frameInfo.request.URL;
    if (m.world == [WKContentWorld pageWorld] && [u.scheme isEqualToString:kExtScheme]) return u.host.lowercaseString;
    return nil;
}

- (void)userContentController:(WKUserContentController *)ucc didReceiveScriptMessage:(WKScriptMessage *)message replyHandler:(void (^)(id, NSString *))reply {
    (void)ucc;
    SaturnExtensions *owner = self.owner;
    NSString *extID = SEExtensionIDForMessage(message);
    NSDictionary *ext = extID ? [owner extensionWithID:extID] : nil;
    if (!ext || ![ext[@"enabled"] boolValue] || ![message.body isKindOfClass:[NSDictionary class]]) { reply(nil, @"This extension isn't available."); return; }
    NSString *op = message.body[@"op"];
    NSDictionary *args = [message.body[@"args"] isKindOfClass:[NSDictionary class]] ? message.body[@"args"] : @{};
    NSArray *perms = ext[@"permissions"];
    BOOL inPopup = message.world == [WKContentWorld pageWorld];
    BOOL (^need)(NSString *) = ^BOOL(NSString *p) {
        if ([perms containsObject:p]) return YES;
        reply(nil, [NSString stringWithFormat:@"This extension needs the “%@” permission for that.", p]);
        return NO;
    };

    if ([op hasPrefix:@"storage."]) {
        if (!need(@"storage")) return;
        NSMutableDictionary *data = [[owner storageForID:extID] mutableCopy];
        if ([op isEqualToString:@"storage.get"]) {
            id keys = args[@"keys"];
            if (!keys || [keys isKindOfClass:[NSNull class]]) { reply(data, nil); return; }
            NSMutableDictionary *out = [NSMutableDictionary dictionary];
            if ([keys isKindOfClass:[NSString class]]) { if (data[keys]) out[keys] = data[keys]; }
            else if ([keys isKindOfClass:[NSArray class]]) { for (id k in keys) if ([k isKindOfClass:[NSString class]] && data[k]) out[k] = data[k]; }
            else if ([keys isKindOfClass:[NSDictionary class]]) { for (NSString *k in keys) out[k] = data[k] ?: keys[k]; }   // object = defaults
            reply(out, nil);
            return;
        }
        if ([op isEqualToString:@"storage.set"]) {
            NSDictionary *items = args[@"items"];
            if (![items isKindOfClass:[NSDictionary class]]) { reply(nil, @"storage.set needs an object."); return; }
            [data addEntriesFromDictionary:items];
        } else if ([op isEqualToString:@"storage.remove"]) {
            id keys = args[@"keys"];
            for (id k in ([keys isKindOfClass:[NSArray class]] ? keys : (keys ? @[keys] : @[]))) if ([k isKindOfClass:[NSString class]]) [data removeObjectForKey:k];
        } else if ([op isEqualToString:@"storage.clear"]) {
            [data removeAllObjects];
        } else { reply(nil, @"Unknown call."); return; }
        NSData *enc = [NSJSONSerialization dataWithJSONObject:data options:0 error:nil];
        if (!enc || enc.length > kMaxStorageBytes) { reply(nil, @"Storage is limited to 1 MB."); return; }
        [owner setStorage:data forID:extID];
        reply(nil, nil);
        return;
    }
    if ([op isEqualToString:@"clipboard.write"]) {
        if (!need(@"clipboardWrite")) return;
        NSString *text = args[@"text"];
        if (![text isKindOfClass:[NSString class]] || text.length > 100000) { reply(nil, @"Nothing to copy."); return; }
        [[NSPasteboard generalPasteboard] clearContents];
        [[NSPasteboard generalPasteboard] setString:text forType:NSPasteboardTypeString];
        reply(nil, nil);
        return;
    }
    if ([op isEqualToString:@"tabs.open"]) {
        if (!need(@"tabs")) return;
        NSURL *u = [args[@"url"] isKindOfClass:[NSString class]] ? [NSURL URLWithString:args[@"url"]] : nil;
        if (!u || (![u.scheme isEqualToString:@"https"] && ![u.scheme isEqualToString:@"http"])) { reply(nil, @"Only http and https pages can be opened."); return; }
        WKWebView *source = inPopup ? (owner.activeWebViewProvider ? owner.activeWebViewProvider() : nil) : message.webView;
        [[NSNotificationCenter defaultCenter] postNotificationName:SaturnExtensionOpenURLNotification object:source userInfo:@{@"url": u}];
        reply(nil, nil);
        return;
    }
    if ([op isEqualToString:@"tabs.active"] || [op isEqualToString:@"tabs.sendMessage"]) {
        if (!inPopup) { reply(nil, @"That is only available in the popup."); return; }
        if (!need(@"activeTab")) return;
        WKWebView *wv = owner.activeWebViewProvider ? owner.activeWebViewProvider() : nil;
        NSString *scheme = wv.URL.scheme.lowercaseString;
        if (!wv || (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"])) { reply(nil, @"There is no web page open to talk to."); return; }
        if ([op isEqualToString:@"tabs.active"]) { reply(@{@"url": wv.URL.absoluteString ?: @"", @"title": wv.title ?: @""}, nil); return; }
        WKContentWorld *world = [WKContentWorld worldWithName:[kWorldPrefix stringByAppendingString:extID]];
        [wv callAsyncJavaScript:@"return await window.__saturnDispatch(m);" arguments:@{@"m": args[@"message"] ?: [NSNull null]} inFrame:nil inContentWorld:world
              completionHandler:^(id result, NSError *err) {
            if (err) reply(nil, @"This extension isn't running on that page. Reload the page and try again.");
            else reply(result, nil);
        }];
        return;
    }
    reply(nil, @"Unknown call.");
}
@end

#pragma mark - saturn-extension:// scheme

@interface SaturnExtensionSchemeHandler : NSObject <WKURLSchemeHandler>
@property (nonatomic, weak) SaturnExtensions *owner;
@end

@implementation SaturnExtensionSchemeHandler
- (void)webView:(WKWebView *)webView startURLSchemeTask:(id<WKURLSchemeTask>)task {
    (void)webView;
    NSURL *url = task.request.URL;
    NSString *extID = url.host.lowercaseString;
    NSDictionary *ext = [self.owner extensionWithID:extID];
    NSString *rel = [url.path stringByRemovingPercentEncoding];
    if ([rel hasPrefix:@"/"]) rel = [rel substringFromIndex:1];
    // Extension pages (the popup) may read any file; websites and the extensions page only the files the manifest lists.
    NSURL *requester = task.request.mainDocumentURL;
    BOOL fromExtension = [requester.scheme isEqualToString:kExtScheme] && [requester.host.lowercaseString isEqualToString:extID];
    BOOL allowed = ext && [ext[@"enabled"] boolValue] && rel.length && SERelPathOK(rel) && (fromExtension || [ext[@"accessible"] containsObject:rel]);
    NSData *body = nil;
    if (allowed) {
        NSString *dir = [ext[@"dir"] stringByResolvingSymlinksInPath];
        NSString *full = [[dir stringByAppendingPathComponent:rel] stringByResolvingSymlinksInPath];
        BOOL isDir = NO;
        if ([full hasPrefix:[dir stringByAppendingString:@"/"]] && [[NSFileManager defaultManager] fileExistsAtPath:full isDirectory:&isDir] && !isDir) body = [NSData dataWithContentsOfFile:full];
    }
    NSMutableDictionary *headers = [@{@"Content-Type": body ? SEMimeForPath(rel) : @"text/plain", @"Cache-Control": @"no-store", @"Access-Control-Allow-Origin": @"*"} mutableCopy];
    // Extension pages are code the extension ships: no inline or remote scripts, no network from the popup.
    if (body && [rel.pathExtension.lowercaseString isEqualToString:@"html"]) headers[@"Content-Security-Policy"] = @"default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'none'; form-action 'none'";
    NSHTTPURLResponse *resp = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:body ? 200 : 404 HTTPVersion:@"HTTP/1.1" headerFields:headers];
    [task didReceiveResponse:resp];
    [task didReceiveData:body ?: [@"Not found" dataUsingEncoding:NSUTF8StringEncoding]];
    [task didFinish];
}
- (void)webView:(WKWebView *)webView stopURLSchemeTask:(id<WKURLSchemeTask>)task { (void)webView; (void)task; }
@end

#pragma mark - Manager

@implementation SaturnExtensions {
    NSMutableArray<NSMutableDictionary *> *_exts;          // parsed extensions in install order (plus broken ones with "error")
    NSMutableDictionary<NSString *, NSDictionary *> *_state;   // id -> {enabled, dev, path}
    NSMutableDictionary<NSString *, NSArray<WKUserScript *> *> *_scriptCache;
    NSMutableDictionary<NSString *, NSMutableDictionary *> *_storage;
    SaturnExtensionBridge *_bridge;
    SaturnExtensionSchemeHandler *_scheme;
    NSHashTable<WKWebView *> *_pageViews;
    NSArray<NSDictionary *> *_storeItems;
    NSString *_storeStatus;      // loading, ok, offline
    NSURL *_storeBase;
    NSPopover *_popover;
    NSMutableSet<NSString *> *_installing;
}

+ (instancetype)shared {
    static SaturnExtensions *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[SaturnExtensions alloc] init]; });
    return s;
}

+ (NSString *)extensionsDirectory { return SERoot(); }

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _bridge = [[SaturnExtensionBridge alloc] init]; _bridge.owner = self;
    _scheme = [[SaturnExtensionSchemeHandler alloc] init]; _scheme.owner = self;
    _pageViews = [NSHashTable weakObjectsHashTable];
    _storage = [NSMutableDictionary dictionary];
    _installing = [NSMutableSet set];
    _storeStatus = @"loading";
    [self reloadAll];
    return self;
}

- (SaturnExtensionBridge *)bridge { return _bridge; }
- (id<WKURLSchemeHandler>)schemeHandler { return _scheme; }

#pragma mark State

- (void)loadState {
    NSData *d = [NSData dataWithContentsOfFile:SEStatePath()];
    id j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
    _state = [NSMutableDictionary dictionary];
    if ([j isKindOfClass:[NSDictionary class]]) for (NSString *k in j) if (SEValidID(k) && [j[k] isKindOfClass:[NSDictionary class]]) _state[k] = j[k];
}
- (void)saveState {
    NSData *d = [NSJSONSerialization dataWithJSONObject:_state options:0 error:nil];
    [d writeToFile:SEStatePath() atomically:YES];
}

- (void)reloadAll {
    [self loadState];
    _exts = [NSMutableArray array];
    _scriptCache = [NSMutableDictionary dictionary];
    for (NSString *extID in [_state.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        NSDictionary *st = _state[extID];
        BOOL dev = [st[@"dev"] boolValue];
        NSString *dir = dev ? st[@"path"] : [SERoot() stringByAppendingPathComponent:extID];
        NSString *err = nil;
        NSDictionary *parsed = dir.length ? SEParseExtension(dir, &err) : nil;
        if (parsed && ![parsed[@"id"] isEqualToString:extID]) { parsed = nil; err = @"The manifest id changed. Remove this extension and load it again."; }
        NSMutableDictionary *e = parsed ? [parsed mutableCopy] : [@{@"id": extID, @"name": extID, @"version": @"", @"description": @"", @"author": @"", @"permissions": @[], @"sites": @[], @"scripts": @[], @"popup": [NSNull null], @"icon": [NSNull null], @"accessible": @[], @"dir": dir ?: @""} mutableCopy];
        e[@"dev"] = @(dev);
        e[@"enabled"] = @(parsed && [st[@"enabled"] boolValue]);
        e[@"error"] = err ?: [NSNull null];
        [_exts addObject:e];
    }
}

- (NSArray<NSDictionary *> *)installed { return [_exts copy]; }
- (NSDictionary *)extensionWithID:(NSString *)extID {
    for (NSDictionary *e in _exts) if ([e[@"id"] isEqualToString:extID]) return e;
    return nil;
}

- (void)changed {
    _scriptCache = [NSMutableDictionary dictionary];
    [[NSNotificationCenter defaultCenter] postNotificationName:SaturnExtensionsChangedNotification object:self];
    [self pushState];
}

- (void)setEnabled:(BOOL)enabled forExtensionID:(NSString *)extID {
    NSMutableDictionary *st = [_state[extID] mutableCopy];
    if (!st) return;
    st[@"enabled"] = @(enabled);
    _state[extID] = st;
    [self saveState];
    [self reloadAll];
    [self changed];
}

- (void)removeExtensionID:(NSString *)extID {
    NSDictionary *st = _state[extID];
    if (!st) return;
    if (![st[@"dev"] boolValue]) [[NSFileManager defaultManager] removeItemAtPath:[SERoot() stringByAppendingPathComponent:extID] error:nil];   // dev folders are never deleted
    [[NSFileManager defaultManager] removeItemAtPath:SEDataPath(extID) error:nil];
    [_storage removeObjectForKey:extID];
    [_state removeObjectForKey:extID];
    [self saveState];
    [self reloadAll];
    [self changed];
}

- (void)reloadExtensionID:(NSString *)extID { (void)extID; [self reloadAll]; [self changed]; }

#pragma mark Storage

- (NSDictionary *)storageForID:(NSString *)extID {
    NSMutableDictionary *d = _storage[extID];
    if (!d) {
        NSData *raw = [NSData dataWithContentsOfFile:SEDataPath(extID)];
        id j = raw ? [NSJSONSerialization JSONObjectWithData:raw options:NSJSONReadingMutableContainers error:nil] : nil;
        d = [j isKindOfClass:[NSMutableDictionary class]] ? j : [NSMutableDictionary dictionary];
        _storage[extID] = d;
    }
    return d;
}
- (void)setStorage:(NSDictionary *)data forID:(NSString *)extID {
    _storage[extID] = [data mutableCopy];
    [[NSJSONSerialization dataWithJSONObject:data options:0 error:nil] writeToFile:SEDataPath(extID) atomically:YES];
}

#pragma mark Web integration

- (void)applyToController:(WKUserContentController *)ucc {
    // Replace extension scripts, keep everyone else's.
    NSArray<WKUserScript *> *old = ucc.userScripts;
    [ucc removeAllUserScripts];
    for (WKUserScript *s in old) if (![s.source hasPrefix:kScriptMark]) [ucc addUserScript:s];

    NSMutableSet *registered = objc_getAssociatedObject(ucc, "saturn.ext.worlds");
    if (!registered) { registered = [NSMutableSet set]; objc_setAssociatedObject(ucc, "saturn.ext.worlds", registered, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    NSMutableSet *wanted = [NSMutableSet set];
    for (NSDictionary *e in _exts) {
        if (![e[@"enabled"] boolValue]) continue;
        NSString *extID = e[@"id"];
        NSArray *scripts = _scriptCache[extID];
        if (!scripts) { scripts = SEBuildScripts(e); _scriptCache[extID] = scripts; }
        if (!scripts.count) continue;
        for (WKUserScript *s in scripts) [ucc addUserScript:s];
        [wanted addObject:extID];
        if (![registered containsObject:extID]) {
            [ucc addScriptMessageHandlerWithReply:_bridge contentWorld:[WKContentWorld worldWithName:[kWorldPrefix stringByAppendingString:extID]] name:@"saturnExt"];
            [registered addObject:extID];
        }
    }
    for (NSString *extID in [registered copy]) {
        if ([wanted containsObject:extID]) continue;
        [ucc removeScriptMessageHandlerForName:@"saturnExt" contentWorld:[WKContentWorld worldWithName:[kWorldPrefix stringByAppendingString:extID]]];
        [registered removeObject:extID];
    }
}

#pragma mark Install

- (NSArray<NSString *> *)consentLinesFor:(NSDictionary *)ext {
    NSMutableArray *lines = [NSMutableArray array];
    NSArray *sites = ext[@"sites"];
    if (sites.count) {
        BOOL all = NO;
        for (NSString *s in sites) if ([s isEqualToString:@"<all_urls>"] || [s hasPrefix:@"*://*/"] || [s hasPrefix:@"https://*/"] || [s hasPrefix:@"http://*/"]) all = YES;
        [lines addObject:all ? @"Read and change data on all websites" : [NSString stringWithFormat:@"Read and change data on: %@", [sites componentsJoinedByString:@", "]]];
    }
    for (NSString *p in ext[@"permissions"]) [lines addObject:SEPermissionText(p)];
    return lines;
}

// Shows the permission prompt, then calls done(YES) to proceed.
- (void)confirmInstall:(NSDictionary *)ext update:(BOOL)update window:(NSWindow *)window done:(void (^)(BOOL ok))done {
    NSAlert *a = [[NSAlert alloc] init];
    a.messageText = [NSString stringWithFormat:@"%@ “%@”?", update ? @"Update" : @"Add", ext[@"name"]];
    NSMutableString *info = [NSMutableString string];
    if ([ext[@"author"] length]) [info appendFormat:@"By %@. ", ext[@"author"]];
    if ([ext[@"dev"] boolValue]) [info appendString:@"This is a developer extension loaded from a folder on your Mac. "];
    NSArray *lines = [self consentLinesFor:ext];
    [info appendString:lines.count ? @"It can:\n" : @"It asks for no special access."];
    for (NSString *l in lines) [info appendFormat:@"\n•  %@", l];
    a.informativeText = info;
    [a addButtonWithTitle:update ? @"Update" : @"Add extension"];
    [a addButtonWithTitle:@"Cancel"];
    if (window) [a beginSheetModalForWindow:window completionHandler:^(NSModalResponse r) { done(r == NSAlertFirstButtonReturn); }];
    else done([a runModal] == NSAlertFirstButtonReturn);
}

- (void)reportError:(NSString *)msg window:(NSWindow *)window {
    NSAlert *a = [[NSAlert alloc] init];
    a.messageText = @"Couldn't add the extension";
    a.informativeText = msg;
    [a addButtonWithTitle:@"OK"];
    if (window) [a beginSheetModalForWindow:window completionHandler:nil]; else [a runModal];
}

// dev: keep the folder where it is and run it from there. Otherwise copy it into the Extensions folder.
- (void)installParsed:(NSDictionary *)parsed fromDirectory:(NSString *)dir dev:(BOOL)dev window:(NSWindow *)window finished:(void (^)(void))finished {
    NSString *extID = parsed[@"id"];
    NSDictionary *existing = [self extensionWithID:extID];
    BOOL update = existing != nil;
    NSMutableDictionary *shown = [parsed mutableCopy];
    shown[@"dev"] = @(dev);
    BOOL sameAccess = update && [existing[@"permissions"] isEqual:parsed[@"permissions"]] && [existing[@"sites"] isEqual:parsed[@"sites"]];
    void (^go)(void) = ^{
        if (!dev) {
            NSString *dest = [SERoot() stringByAppendingPathComponent:extID];
            NSFileManager *fm = [NSFileManager defaultManager];
            [fm removeItemAtPath:dest error:nil];
            NSError *err = nil;
            if (![fm copyItemAtPath:dir toPath:dest error:&err]) { [self reportError:err.localizedDescription window:window]; return; }
        }
        NSMutableDictionary *st = [@{@"enabled": @YES, @"dev": @(dev)} mutableCopy];
        if (dev) st[@"path"] = dir;
        self->_state[extID] = st;
        [self saveState];
        [self reloadAll];
        [self changed];
    };
    if (sameAccess) { go(); if (finished) finished(); }
    else [self confirmInstall:shown update:update window:window done:^(BOOL ok) { if (ok) go(); [self pushState]; if (finished) finished(); }];
}

- (void)loadUnpackedFromWindow:(NSWindow *)window {
    NSOpenPanel *p = [NSOpenPanel openPanel];
    p.canChooseDirectories = YES; p.canChooseFiles = NO; p.allowsMultipleSelection = NO;
    p.message = @"Choose your extension's folder (the one with manifest.json).";
    p.prompt = @"Load extension";
    void (^handle)(NSModalResponse) = ^(NSModalResponse r) {
        if (r != NSModalResponseOK || !p.URL) return;
        NSString *dir = p.URL.path, *err = nil;
        NSDictionary *parsed = SEParseExtension(dir, &err);
        if (!parsed) { [self reportError:err window:window]; return; }
        [self installParsed:parsed fromDirectory:dir dev:YES window:window finished:nil];
    };
    if (window) [p beginSheetModalForWindow:window completionHandler:handle]; else handle([p runModal]);
}

- (NSString *)templateDirectory {
    NSMutableArray *bases = [NSMutableArray array];
    NSString *res = [NSBundle mainBundle].resourcePath;
    if (res) [bases addObject:res];
    NSString *exeDir = [[[NSBundle mainBundle] executablePath] stringByDeletingLastPathComponent];
    if (exeDir) [bases addObject:exeDir];
    for (NSString *b in bases) {
        NSString *d = [b stringByAppendingPathComponent:@"extensions-template"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:[d stringByAppendingPathComponent:@"manifest.json"]]) return d;
    }
    return nil;
}

// Copies the starter template to ~/Documents/Saturn Extensions/<name> and loads it as a developer extension.
- (void)createFromTemplateInWindow:(NSWindow *)window {
    NSString *tpl = [self templateDirectory];
    if (!tpl) { [self reportError:@"The extension template isn't bundled with this build." window:window]; return; }
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"Saturn Extensions"];
    [fm createDirectoryAtPath:docs withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *name = @"my-extension", *dest = [docs stringByAppendingPathComponent:name];
    for (int n = 2; [fm fileExistsAtPath:dest]; n++) { name = [NSString stringWithFormat:@"my-extension-%d", n]; dest = [docs stringByAppendingPathComponent:name]; }
    NSError *err = nil;
    if (![fm copyItemAtPath:tpl toPath:dest error:&err]) { [self reportError:err.localizedDescription window:window]; return; }
    // Give the copy its own id so several can be loaded side by side.
    NSString *mp = [dest stringByAppendingPathComponent:@"manifest.json"];
    NSMutableDictionary *m = [[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:mp] options:NSJSONReadingMutableContainers error:nil] mutableCopy];
    m[@"id"] = [@"local." stringByAppendingString:name];
    [[NSJSONSerialization dataWithJSONObject:m options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil] writeToFile:mp atomically:YES];
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:dest]]];
    NSString *perr = nil;
    NSDictionary *parsed = SEParseExtension(dest, &perr);
    if (parsed) [self installParsed:parsed fromDirectory:dest dev:YES window:window finished:nil];
}

#pragma mark Store

- (void)fetchStore {
    _storeStatus = @"loading";
    void (^finish)(NSData *, NSURL *, BOOL) = ^(NSData *data, NSURL *base, BOOL remote) {
        id j = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSArray *list = [j isKindOfClass:[NSDictionary class]] ? j[@"extensions"] : nil;
        if (![list isKindOfClass:[NSArray class]]) {
            if (remote) { [self loadBundledStore]; return; }
            self->_storeItems = @[]; self->_storeStatus = @"offline"; [self pushState]; return;
        }
        NSMutableArray *items = [NSMutableArray array];
        for (id e in list) {
            if (![e isKindOfClass:[NSDictionary class]] || !SEValidID(e[@"id"]) || ![e[@"name"] isKindOfClass:[NSString class]] || ![e[@"version"] isKindOfClass:[NSString class]] || ![e[@"download"] isKindOfClass:[NSString class]] || ![e[@"sha256"] isKindOfClass:[NSString class]]) continue;
            NSURL *dl = [NSURL URLWithString:e[@"download"] relativeToURL:base].absoluteURL;
            if (!dl) continue;
            NSMutableDictionary *item = [e mutableCopy];
            item[@"downloadURL"] = dl.absoluteString;
            [items addObject:item];
        }
        self->_storeItems = items; self->_storeBase = base;
        self->_storeStatus = remote ? @"ok" : @"offline";
        [self pushState];
    };
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kCatalogURL] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:10];
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        BOOL ok = !err && [(NSHTTPURLResponse *)resp statusCode] == 200 && data;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (ok) finish(data, [NSURL URLWithString:kCatalogURL], YES);
            else [self loadBundledStore];
        });
    }] resume];
}

- (void)loadBundledStore {
    NSString *res = [NSBundle mainBundle].resourcePath;
    NSString *exeDir = [[[NSBundle mainBundle] executablePath] stringByDeletingLastPathComponent];
    for (NSString *b in @[res ?: @"", exeDir ?: @""]) {
        NSString *idx = [b stringByAppendingPathComponent:@"store/index.json"];
        NSData *d = [NSData dataWithContentsOfFile:idx];
        id j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
        if ([j isKindOfClass:[NSDictionary class]] && [j[@"extensions"] isKindOfClass:[NSArray class]]) {
            NSURL *base = [NSURL fileURLWithPath:idx];
            NSMutableArray *items = [NSMutableArray array];
            for (id e in j[@"extensions"]) {
                if (![e isKindOfClass:[NSDictionary class]] || !SEValidID(e[@"id"]) || ![e[@"download"] isKindOfClass:[NSString class]]) continue;
                NSMutableDictionary *item = [e mutableCopy];
                item[@"downloadURL"] = [NSURL URLWithString:e[@"download"] relativeToURL:base].absoluteURL.absoluteString ?: @"";
                [items addObject:item];
            }
            _storeItems = items; _storeBase = base; _storeStatus = @"offline";
            [self pushState];
            return;
        }
    }
    _storeItems = @[]; _storeStatus = @"offline";
    [self pushState];
}

- (void)installStoreID:(NSString *)extID window:(NSWindow *)window {
    NSDictionary *item = nil;
    for (NSDictionary *i in _storeItems) if ([i[@"id"] isEqualToString:extID]) { item = i; break; }
    if (!item || [_installing containsObject:extID]) return;
    [_installing addObject:extID];
    [self pushState];
    NSURL *url = [NSURL URLWithString:item[@"downloadURL"]];
    void (^fail)(NSString *) = ^(NSString *m) { [self->_installing removeObject:extID]; [self pushState]; [self reportError:m window:window]; };
    void (^process)(NSData *) = ^(NSData *zip) {
        if (!zip || zip.length > 6 * 1024 * 1024) { fail(@"The download failed or is too large."); return; }
        if (![[SESha256(zip) lowercaseString] isEqualToString:[item[@"sha256"] lowercaseString]]) { fail(@"The download doesn't match the store's checksum, so it wasn't installed."); return; }
        NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
        NSString *zipPath = [tmp stringByAppendingPathComponent:@"ext.zip"], *out = [tmp stringByAppendingPathComponent:@"out"];
        [[NSFileManager defaultManager] createDirectoryAtPath:out withIntermediateDirectories:YES attributes:nil error:nil];
        [zip writeToFile:zipPath atomically:YES];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSTask *t = [[NSTask alloc] init];
            t.executableURL = [NSURL fileURLWithPath:@"/usr/bin/ditto"];
            t.arguments = @[@"-x", @"-k", zipPath, out];
            BOOL ran = [t launchAndReturnError:nil];
            if (ran) [t waitUntilExit];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self->_installing removeObject:extID];
                NSFileManager *fm = [NSFileManager defaultManager];
                NSString *root = out;
                if (![fm fileExistsAtPath:[root stringByAppendingPathComponent:@"manifest.json"]]) {   // zipped with a top-level folder
                    NSArray *kids = [[fm contentsOfDirectoryAtPath:out error:nil] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"NOT SELF BEGINSWITH '__MACOSX' AND NOT SELF BEGINSWITH '.'"]];
                    if (kids.count == 1) root = [out stringByAppendingPathComponent:kids[0]];
                }
                NSString *perr = nil;
                NSDictionary *parsed = ran ? SEParseExtension(root, &perr) : nil;
                if (!parsed) { [self pushState]; [self reportError:perr ?: @"The package couldn't be unpacked." window:window]; [fm removeItemAtPath:tmp error:nil]; return; }
                if (![parsed[@"id"] isEqualToString:extID] || ![parsed[@"version"] isEqualToString:item[@"version"]] || [extID hasPrefix:@"local."]) {
                    [self pushState]; [self reportError:@"The package doesn't match its store listing, so it wasn't installed." window:window]; [fm removeItemAtPath:tmp error:nil]; return;
                }
                [self installParsed:parsed fromDirectory:root dev:NO window:window finished:^{ [fm removeItemAtPath:tmp error:nil]; }];
            });
        });
    };
    if (url.isFileURL) process([NSData dataWithContentsOfURL:url]);
    else {
        [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
            BOOL ok = !err && [(NSHTTPURLResponse *)resp statusCode] == 200;
            dispatch_async(dispatch_get_main_queue(), ^{ process(ok ? data : nil); });
        }] resume];
    }
}

#pragma mark Page (saturn://extensions)

- (NSDictionary *)pageState {
    NSMutableArray *installed = [NSMutableArray array];
    for (NSDictionary *e in _exts) {
        BOOL all = NO;
        for (NSString *s in e[@"sites"]) if ([s isEqualToString:@"<all_urls>"] || [s hasPrefix:@"*://*/"] || [s hasPrefix:@"https://*/"] || [s hasPrefix:@"http://*/"]) all = YES;
        [installed addObject:@{@"id": e[@"id"], @"name": e[@"name"], @"version": e[@"version"], @"description": e[@"description"], @"author": e[@"author"],
                               @"enabled": e[@"enabled"], @"dev": e[@"dev"], @"error": e[@"error"], @"allSites": @(all), @"sites": e[@"sites"],
                               @"permissions": e[@"permissions"], @"popup": @(![e[@"popup"] isKindOfClass:[NSNull class]]), @"icon": e[@"icon"]}];
    }
    NSMutableArray *store = [NSMutableArray array];
    for (NSDictionary *i in _storeItems) {
        NSDictionary *have = [self extensionWithID:i[@"id"]];
        NSString *state = !have ? @"available" : (SEVersionCompare(have[@"version"], i[@"version"]) == NSOrderedAscending ? @"update" : @"installed");
        if (have && [have[@"dev"] boolValue]) state = @"dev";
        [store addObject:@{@"id": i[@"id"], @"name": i[@"name"], @"version": i[@"version"], @"description": i[@"description"] ?: @"", @"author": i[@"author"] ?: @"",
                           @"permissions": i[@"permissions"] ?: @[], @"sites": i[@"sites"] ?: @[], @"tags": i[@"tags"] ?: @[], @"state": state, @"busy": @([_installing containsObject:i[@"id"]])}];
    }
    return @{@"installed": installed, @"store": @{@"status": _storeStatus ?: @"loading", @"items": store}};
}

- (void)pushState {
    NSString *js = [NSString stringWithFormat:@"window.__saturnExt&&window.__saturnExt.update(%@)", SEJSON([self pageState])];
    for (WKWebView *wv in _pageViews.allObjects) [wv evaluateJavaScript:js completionHandler:nil];
}

- (NSString *)pageHTML {
    if (!_storeItems && ![_storeStatus isEqualToString:@"loading"]) _storeStatus = @"loading";
    NSString *tpl = SaturnExtensionsPageHTMLTemplate();
    return [tpl stringByReplacingOccurrencesOfString:@"__STATE__" withString:SEJSON([self pageState])];
}

- (void)handlePageMessage:(WKScriptMessage *)m {
    NSURL *origin = m.frameInfo.request.URL;
    if (!m.frameInfo.isMainFrame || ![origin.scheme isEqualToString:@"saturn"] || ![origin.host isEqualToString:@"extensions"]) return;
    if (![m.body isKindOfClass:[NSDictionary class]] || !m.webView) return;
    NSDictionary *b = m.body;
    NSString *action = b[@"action"], *extID = [b[@"id"] isKindOfClass:[NSString class]] ? b[@"id"] : nil;
    WKWebView *wv = m.webView;
    NSWindow *window = wv.window;
    if (![_pageViews containsObject:wv]) [_pageViews addObject:wv];

    if ([action isEqualToString:@"state"]) { [self pushState]; if (!_storeItems) [self fetchStore]; }
    else if ([action isEqualToString:@"refreshStore"]) [self fetchStore];
    else if ([action isEqualToString:@"install"] && extID) [self installStoreID:extID window:window];
    else if ([action isEqualToString:@"remove"] && extID && [self extensionWithID:extID]) {
        NSAlert *a = [[NSAlert alloc] init];
        a.messageText = [NSString stringWithFormat:@"Remove “%@”?", [self extensionWithID:extID][@"name"]];
        a.informativeText = [[self extensionWithID:extID][@"dev"] boolValue] ? @"Your folder is left where it is." : @"Its saved settings are removed too.";
        [a addButtonWithTitle:@"Remove"]; [a addButtonWithTitle:@"Cancel"];
        void (^h)(NSModalResponse) = ^(NSModalResponse r) { if (r == NSAlertFirstButtonReturn) [self removeExtensionID:extID]; };
        if (window) [a beginSheetModalForWindow:window completionHandler:h]; else h([a runModal]);
    }
    else if ([action isEqualToString:@"toggle"] && extID) [self setEnabled:[b[@"enabled"] boolValue] forExtensionID:extID];
    else if ([action isEqualToString:@"reload"]) { [self reloadAll]; [self changed]; }
    else if ([action isEqualToString:@"loadUnpacked"]) [self loadUnpackedFromWindow:window];
    else if ([action isEqualToString:@"createFromTemplate"]) [self createFromTemplateInWindow:window];
    else if ([action isEqualToString:@"showInFinder"] && extID) {
        NSString *dir = [self extensionWithID:extID][@"dir"];
        if (dir.length) [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:dir]]];
    }
    else if ([action isEqualToString:@"openGuide"]) {
        NSString *which = b[@"which"];
        NSURL *u = [NSURL URLWithString:[which isEqualToString:@"submit"] ? kSubmitURL : kDocsURL];
        [[NSNotificationCenter defaultCenter] postNotificationName:SaturnExtensionOpenURLNotification object:wv userInfo:@{@"url": u}];
    }
}

#pragma mark Toolbar

- (void)showPopupForExtensionID:(NSString *)extID relativeToView:(NSView *)view {
    NSDictionary *ext = [self extensionWithID:extID];
    if (!ext || ![ext[@"enabled"] boolValue] || [ext[@"popup"] isKindOfClass:[NSNull class]] || !view.window) { NSBeep(); return; }
    [_popover close];
    WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
    [cfg setURLSchemeHandler:_scheme forURLScheme:kExtScheme];
    [cfg.userContentController addUserScript:[[WKUserScript alloc] initWithSource:SEPreludeJS(extID, YES) injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES]];
    [cfg.userContentController addScriptMessageHandlerWithReply:_bridge contentWorld:[WKContentWorld pageWorld] name:@"saturnExt"];
    CGFloat w = [ext[@"popupWidth"] doubleValue], h = [ext[@"popupHeight"] doubleValue];
    WKWebView *wv = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, w, h) configuration:cfg];
    [wv setValue:@NO forKey:@"drawsBackground"];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@/%@", kExtScheme, extID, ext[@"popup"]]];
    [wv loadRequest:[NSURLRequest requestWithURL:url]];
    NSViewController *vc = [[NSViewController alloc] init];
    vc.view = wv;
    NSPopover *p = [[NSPopover alloc] init];
    p.contentViewController = vc;
    p.contentSize = NSMakeSize(w, h);
    p.behavior = NSPopoverBehaviorTransient;
    p.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    _popover = p;
    [p showRelativeToRect:view.bounds ofView:view preferredEdge:NSRectEdgeMinY];
}

- (NSMenu *)toolbarMenuWithTarget:(id)target manageAction:(SEL)manageAction {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Extensions"];
    BOOL any = NO;
    for (NSDictionary *e in _exts) {
        if (![e[@"enabled"] boolValue]) continue;
        any = YES;
        BOOL hasPopup = ![e[@"popup"] isKindOfClass:[NSNull class]];
        NSMenuItem *it = [menu addItemWithTitle:e[@"title"] ?: e[@"name"] action:hasPopup ? @selector(openExtensionPopup:) : nil keyEquivalent:@""];
        it.target = target;
        it.representedObject = e[@"id"];
        it.toolTip = hasPopup ? e[@"description"] : @"Runs on the pages it matches. No toolbar button.";
        it.enabled = hasPopup;
    }
    if (!any) { NSMenuItem *none = [menu addItemWithTitle:@"No extensions installed" action:nil keyEquivalent:@""]; none.enabled = NO; }
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *manage = [menu addItemWithTitle:@"Manage Extensions…" action:manageAction keyEquivalent:@""]; manage.target = target; manage.tag = 0;
    NSMenuItem *store = [menu addItemWithTitle:@"Extension Store…" action:manageAction keyEquivalent:@""]; store.target = target; store.tag = 1;
    return menu;
}

@end
