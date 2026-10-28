#import "SaturnVaultAutofill.h"
#import "SaturnVault.h"
#import "SaturnVaultWindow.h"
#import "YavqoTheme.h"
#import <objc/runtime.h>

// The page script runs in its own WKContentWorld, so the website's own scripts can neither see the
// "yavqoVault" message handler nor read anything this script holds. Fill and save always go through native UI.

static WKContentWorld *VaultWorld(void) {
    static WKContentWorld *w;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ w = [WKContentWorld worldWithName:@"YavqoVault"]; });
    return w;
}

static NSString *const kHelpers = @R"JS(
function visible(el){
  if (!el || el.disabled) return false;
  var r = el.getBoundingClientRect();
  if (r.width < 2 || r.height < 2) return false;
  var s = getComputedStyle(el);
  return s.visibility !== 'hidden' && s.display !== 'none';
}
function pwFields(){ return Array.prototype.filter.call(document.querySelectorAll('input[type=password]'), visible); }
function userField(pw){
  var scope = pw.form || document, list = scope.querySelectorAll('input'), best = null;
  for (var i = 0; i < list.length; i++) {
    var el = list[i]; if (el === pw) break;
    var t = (el.type || 'text').toLowerCase();
    if ((t === 'text' || t === 'email' || t === 'tel' || t === 'search') && visible(el)) best = el;
  }
  return best;
}
)JS";

@interface SaturnVaultAutofill ()
@end

@implementation SaturnVaultAutofill {
    __weak NSButton *_key;
    BOOL _private;
    WKWebView *(^_current)(void);
    NSMapTable<WKWebView *, NSMutableDictionary *> *_state;
    NSPopover *_popover;
    NSArray<NSDictionary *> *_matches;
}

+ (NSString *)messageHandlerName { return @"yavqoVault"; }

+ (WKContentWorld *)world { return VaultWorld(); }

+ (NSString *)pageScriptSource {
    NSString *body = @R"JS(
(function(){
  if (window.__yavqoVault) return; window.__yavqoVault = true;
  if (!/^https?:$/.test(location.protocol)) return;
  var H = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.yavqoVault;
  if (!H) return;
  function post(o){ try { H.postMessage(o); } catch(e){} }
  function chosenPassword(fields){
    if (fields.length === 1) return fields[0];
    for (var i = 0; i < fields.length - 1; i++) if (fields[i].value === fields[i + 1].value) return fields[i];
    return fields[fields.length - 1];
  }
  var lastHas = null, lastKey = '', lastAt = 0;
  function report(force){
    var has = pwFields().length > 0;
    if (force === true || has !== lastHas) { lastHas = has; post({kind: 'form', hasPassword: has}); }
  }
  function capture(){
    var filled = pwFields().filter(function(f){ return f.value; });
    if (!filled.length) return;
    var pw = chosenPassword(filled), u = userField(pw);
    var key = (u ? u.value : '') + '\u0000' + pw.value, now = Date.now();
    if (key === lastKey && now - lastAt < 1500) return;
    lastKey = key; lastAt = now;
    post({kind: 'submit', username: u ? u.value : '', password: pw.value});
    setTimeout(function(){ report(true); }, 1800);
  }
  document.addEventListener('submit', capture, true);
  document.addEventListener('click', function(e){
    var t = e.target && e.target.closest ? e.target.closest('button, input[type=submit], input[type=button], [role=button], a') : null;
    if (!t) return;
    var form = t.form || t.closest('form');
    var inForm = form ? form.querySelector('input[type=password]') : null;
    var label = ((t.innerText || t.value || t.getAttribute('aria-label') || '') + '').toLowerCase();
    if (inForm || /(sign|log) ?in|log ?on|continue|next|submit|create|register|join|enter/.test(label)) capture();
  }, true);
  document.addEventListener('keydown', function(e){
    if (e.key === 'Enter' && e.target && e.target.tagName === 'INPUT') capture();
  }, true);
  var timer = null;
  function start(){
    report(true);
    try {
      new MutationObserver(function(){ clearTimeout(timer); timer = setTimeout(report, 400); })
        .observe(document.documentElement, {childList: true, subtree: true, attributes: true, attributeFilter: ['style', 'class', 'hidden']});
    } catch(e) {}
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();
})();
)JS";
    return [NSString stringWithFormat:@"(function(){%@})();", [kHelpers stringByAppendingString:body]];
}

- (instancetype)initWithKeyButton:(NSButton *)keyButton privateWindow:(BOOL)isPrivate currentWebView:(WKWebView *(^)(void))currentWebView {
    self = [super init];
    if (!self) return nil;
    _key = keyButton; _private = isPrivate; _current = [currentWebView copy];
    _state = [NSMapTable weakToStrongObjectsMapTable];
    keyButton.hidden = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(vaultChanged:) name:SaturnVaultChangedNotification object:nil];
    return self;
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (NSMutableDictionary *)stateFor:(WKWebView *)wv {
    NSMutableDictionary *st = [_state objectForKey:wv];
    if (!st) { st = [NSMutableDictionary dictionary]; [_state setObject:st forKey:wv]; }
    return st;
}

static NSString *HostOf(WKWebView *wv) { return [SaturnVault hostForURLString:wv.URL.absoluteString]; }
static NSString *OriginOf(WKWebView *wv) {
    NSURL *u = wv.URL;
    return u.host ? [NSString stringWithFormat:@"%@://%@", u.scheme, u.host] : nil;
}

#pragma mark Messages from the page

- (void)handleScriptMessage:(WKScriptMessage *)message {
    WKWebView *wv = message.webView;
    if (!wv || !message.frameInfo.isMainFrame || ![message.body isKindOfClass:[NSDictionary class]]) return;
    NSString *scheme = wv.URL.scheme.lowercaseString;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) return;
    NSDictionary *b = message.body;
    NSString *host = HostOf(wv);
    if (!host) return;
    NSMutableDictionary *st = [self stateFor:wv];
    NSString *kind = b[@"kind"];

    if ([kind isEqualToString:@"submit"]) {
        NSString *pass = [b[@"password"] isKindOfClass:[NSString class]] ? b[@"password"] : @"";
        NSString *user = [b[@"username"] isKindOfClass:[NSString class]] ? b[@"username"] : @"";
        if (_private || !pass.length || pass.length > 256 || user.length > 256) return;
        if ([[SaturnVault shared] neverSavesHost:host]) return;
        st[@"pending"] = @{@"host": host, @"origin": OriginOf(wv) ?: @"", @"username": user, @"password": pass, @"at": [NSDate date]};
        st[@"offerShown"] = @NO;
        return;
    }
    if ([kind isEqualToString:@"form"]) {
        BOOL has = [b[@"hasPassword"] boolValue];
        st[@"hasPassword"] = @(has);
        NSDictionary *pending = st[@"pending"];
        if (pending) {
            BOOL fresh = [[NSDate date] timeIntervalSinceDate:pending[@"at"]] < 30;
            BOOL sameSite = [pending[@"host"] isEqualToString:host];
            if (!fresh || !sameSite) st[@"pending"] = nil;
            else if (!has) {          // the sign-in page is gone: the login most likely worked
                st[@"offer"] = pending; st[@"pending"] = nil;
            }
        }
        if (wv == _current()) [self refresh];
    }
}

#pragma mark Key button

- (void)vaultChanged:(NSNotification *)n { (void)n; [self refresh]; }

- (void)refresh {
    WKWebView *wv = _current ? _current() : nil;
    NSMutableDictionary *st = wv ? [_state objectForKey:wv] : nil;
    NSDictionary *offer = st[@"offer"];
    SaturnVault *vault = [SaturnVault shared];

    // Drop an offer that is already saved exactly as typed.
    if (offer && vault.unlocked && [vault resultOfSavingLoginForURLString:offer[@"origin"] username:offer[@"username"] password:offer[@"password"]] == SaturnVaultSaveUnchanged) {
        st[@"offer"] = nil; offer = nil;
    }
    NSString *scheme = wv.URL.scheme.lowercaseString;
    BOOL web = [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"];
    BOOL show = web && ([st[@"hasPassword"] boolValue] || offer != nil);
    _key.hidden = !show;
    if (!show) { [_popover close]; return; }

    NSUInteger n = vault.unlocked ? [vault entriesForHost:HostOf(wv)].count : 0;
    _key.contentTintColor = offer ? Y_blue() : (n ? Y_positive() : Y_ink());
    _key.toolTip = offer ? @"Save this login to Yavqo Vault" : (n ? @"Fill a saved login (Yavqo Vault)" : @"Yavqo Vault");
    if (offer && ![st[@"offerShown"] boolValue] && _key.window.isKeyWindow && !_popover.shown) {
        st[@"offerShown"] = @YES;
        dispatch_async(dispatch_get_main_queue(), ^{ [self showPopover]; });
    }
}

#pragma mark Popover

- (void)togglePopover {
    if (_popover.shown) { [_popover close]; return; }
    [self showPopover];
}

- (void)showPopover {
    if (!_key.window || _key.hidden) return;
    if (!_popover) {
        _popover = [[NSPopover alloc] init];
        _popover.behavior = NSPopoverBehaviorTransient;
        _popover.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    }
    [self reloadPopoverContent];
    if (!_popover.shown) [_popover showRelativeToRect:_key.bounds ofView:_key preferredEdge:NSRectEdgeMinY];
}

- (void)reloadPopoverContent {
    WKWebView *wv = _current();
    NSMutableDictionary *st = [self stateFor:wv];
    NSDictionary *offer = st[@"offer"];
    SaturnVault *vault = [SaturnVault shared];
    const CGFloat W = 320, P = 16;
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, W, 100)];
    root.wantsLayer = YES;
    // Content is built top-down in a flipped helper, then handed to the popover.

    NSMutableArray<NSView *> *items = [NSMutableArray array];
    __block CGFloat y = P;
    void (^add)(NSView *, CGFloat, CGFloat) = ^(NSView *v, CGFloat h, CGFloat gapAfter) {
        v.frame = NSMakeRect(P, y, W - 2 * P, h);
        [items addObject:v];
        y += h + gapAfter;
    };
    NSTextField *(^label)(NSString *, CGFloat, NSFontWeight, NSColor *) = ^NSTextField *(NSString *t, CGFloat s, NSFontWeight w, NSColor *c) {
        NSTextField *l = [NSTextField labelWithString:t];
        l.font = [NSFont systemFontOfSize:s weight:w]; l.textColor = c;
        l.lineBreakMode = NSLineBreakByTruncatingTail;
        return l;
    };

    NSString *host = HostOf(wv) ?: @"";
    NSString *title = offer ? ([vault resultOfSavingLoginForURLString:offer[@"origin"] username:offer[@"username"] password:offer[@"password"]] == SaturnVaultSaveUpdated ? @"Update password?" : @"Save password?") : @"Yavqo Vault";
    if (offer && !vault.unlocked) title = vault.exists ? @"Save password?" : @"Save password?";
    add(label(title, 16, NSFontWeightMedium, Y_ink()), 20, 2);
    add(label(host, 12, NSFontWeightRegular, Y_muted()), 16, 14);

    __weak typeof(self) weakSelf = self;
    if (!vault.unlocked) {
        NSString *msg = offer ? (vault.exists ? @"Enter your master password to save this login." : @"Create a master password to save this login in Yavqo Vault.")
                              : (vault.exists ? @"Enter your master password to fill a saved login." : @"Create a master password to start saving logins.");
        SaturnVaultGate *gate = [[SaturnVaultGate alloc] initWithWidth:W - 2 * P message:msg];
        gate.onUnlocked = ^{ [weakSelf reloadPopoverContent]; };
        add(gate, gate.height, 0);
    } else if (offer) {
        NSTextField *ul = label(@"Username", 12, NSFontWeightBold, Y_ink());
        add(ul, 16, 4);
        NSTextField *uf = [[NSTextField alloc] init];
        uf.stringValue = offer[@"username"] ?: @"";
        uf.bezeled = NO; uf.drawsBackground = NO; uf.focusRingType = NSFocusRingTypeNone; uf.font = [NSFont systemFontOfSize:14]; uf.textColor = Y_ink();
        uf.placeholderString = @"Username or email";
        NSView *box = [[NSView alloc] init];
        box.wantsLayer = YES; box.layer.cornerRadius = 12; box.layer.borderWidth = 1; box.layer.borderColor = YT_rgb(10, 19, 23, 0.45).CGColor;
        uf.frame = NSMakeRect(14, 11, W - 2 * P - 28, 20);
        [box addSubview:uf];
        add(box, 42, 10);
        NSTextField *pl = label([NSString stringWithFormat:@"Password   %@", [@"" stringByPaddingToLength:MIN(12, [offer[@"password"] length]) withString:@"•" startingAtIndex:0]], 13, NSFontWeightRegular, Y_muted());
        add(pl, 18, 14);

        NSButton *save = [NSButton buttonWithTitle:@"Save" target:nil action:nil];
        save.frame = NSMakeRect(P, 0, 140, 40); YT_pill(save, YES);
        NSButton *later = [NSButton buttonWithTitle:@"Not now" target:nil action:nil];
        later.frame = NSMakeRect(P + 148, 0, 120, 40); YT_pill(later, NO);
        NSView *row = [[NSView alloc] init];
        save.frame = NSMakeRect(0, 0, 150, 40); later.frame = NSMakeRect(158, 0, 126, 40);
        [row addSubview:save]; [row addSubview:later];
        add(row, 40, 6);
        NSButton *never = [NSButton buttonWithTitle:@"Never for this site" target:nil action:nil];
        never.bordered = NO;
        never.attributedTitle = [[NSAttributedString alloc] initWithString:@"Never for this site" attributes:@{NSForegroundColorAttributeName: Y_muted(), NSFontAttributeName: [NSFont systemFontOfSize:12]}];
        never.alignment = NSTextAlignmentLeft;
        add(never, 24, 0);

        save.target = self; save.action = @selector(saveOfferTapped:);
        objc_setAssociatedObject(save, "field", uf, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        later.target = self; later.action = @selector(dismissOfferTapped:);
        never.target = self; never.action = @selector(neverTapped:);
    } else {
        _matches = [vault entriesForHost:host];
        if (!_matches.count) {
            add(label(@"No saved logins for this site.", 13, NSFontWeightRegular, Y_muted()), 18, 14);
        }
        for (NSUInteger i = 0; i < _matches.count && i < 6; i++) {
            NSDictionary *e = _matches[i];
            NSButton *b = [NSButton buttonWithTitle:@"" target:self action:@selector(fillTapped:)];
            b.tag = (NSInteger)i;
            b.bordered = NO; b.wantsLayer = YES;
            b.layer.cornerRadius = 14; b.layer.backgroundColor = Y_soft().CGColor;
            NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
            ps.alignment = NSTextAlignmentLeft; ps.firstLineHeadIndent = 14; ps.headIndent = 14; ps.lineSpacing = 2;
            NSMutableAttributedString *at = [[NSMutableAttributedString alloc] initWithString:e[@"title"] ?: @"" attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:14 weight:NSFontWeightMedium], NSForegroundColorAttributeName: Y_ink(), NSParagraphStyleAttributeName: ps}];
            NSString *u = [e[@"username"] length] ? e[@"username"] : @"No username";
            [at appendAttributedString:[[NSAttributedString alloc] initWithString:[@"\n" stringByAppendingString:u] attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:12], NSForegroundColorAttributeName: Y_muted(), NSParagraphStyleAttributeName: ps}]];
            b.attributedTitle = at;
            b.alignment = NSTextAlignmentLeft;
            add(b, 52, 8);
        }
        NSButton *open = [NSButton buttonWithTitle:@"Open Yavqo Vault" target:self action:@selector(openVaultTapped:)];
        open.frame = NSMakeRect(0, 0, 160, 40);
        YT_pill(open, NO);
        add(open, 40, 0);
    }

    CGFloat total = y + P;
    root.frame = NSMakeRect(0, 0, W, total);
    // Convert top-down y to AppKit bottom-up coordinates.
    for (NSView *v in items) {
        NSRect f = v.frame;
        f.origin.y = total - f.origin.y - f.size.height;
        v.frame = f;
        [root addSubview:v];
    }
    NSViewController *vc = [[NSViewController alloc] init];
    vc.view = root;
    _popover.contentViewController = vc;
    _popover.contentSize = NSMakeSize(W, total);
    if (!vault.unlocked) {
        for (NSView *v in items) if ([v isKindOfClass:[SaturnVaultGate class]]) { dispatch_async(dispatch_get_main_queue(), ^{ [(SaturnVaultGate *)v focus]; }); }
    }
}

#pragma mark Actions

- (void)saveOfferTapped:(NSButton *)sender {
    WKWebView *wv = _current();
    NSMutableDictionary *st = [self stateFor:wv];
    NSDictionary *offer = st[@"offer"];
    NSTextField *uf = objc_getAssociatedObject(sender, "field");
    if (!offer) { [_popover close]; return; }
    SaturnVaultSaveResult r = [[SaturnVault shared] saveLoginForURLString:offer[@"origin"] username:uf.stringValue password:offer[@"password"]];
    st[@"offer"] = nil;
    NSString *msg = r == SaturnVaultSaveFailed ? @"Couldn't save. Unlock Yavqo Vault and try again." : (r == SaturnVaultSaveUpdated ? @"Password updated in Yavqo Vault" : @"Saved to Yavqo Vault");
    [self showConfirmation:msg ok:r != SaturnVaultSaveFailed];
    [self refresh];
}

- (void)showConfirmation:(NSString *)msg ok:(BOOL)ok {
    NSTextField *l = [NSTextField labelWithString:msg];
    l.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
    l.textColor = ok ? Y_positive() : Y_negative();
    l.alignment = NSTextAlignmentCenter;
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 320, 64)];
    l.frame = NSMakeRect(16, 22, 288, 20);
    [root addSubview:l];
    NSViewController *vc = [[NSViewController alloc] init];
    vc.view = root;
    _popover.contentViewController = vc;
    _popover.contentSize = NSMakeSize(320, 64);
    __weak NSPopover *p = _popover;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [p close]; });
}

- (void)dismissOfferTapped:(id)sender {
    (void)sender;
    [self stateFor:_current()][@"offer"] = nil;
    [_popover close];
    [self refresh];
}

- (void)neverTapped:(id)sender {
    (void)sender;
    WKWebView *wv = _current();
    [[SaturnVault shared] setNeverSaves:YES host:HostOf(wv)];
    [self stateFor:wv][@"offer"] = nil;
    [_popover close];
    [self refresh];
}

- (void)openVaultTapped:(id)sender {
    (void)sender;
    [_popover close];
    [[SaturnVaultWindow shared] showVault];
}

- (void)fillTapped:(NSButton *)sender {
    if (sender.tag < 0 || (NSUInteger)sender.tag >= _matches.count) return;
    [self fillEntry:_matches[sender.tag]];
    [_popover close];
}

- (void)fillFirstMatch {
    WKWebView *wv = _current();
    NSArray *m = [SaturnVault shared].unlocked ? [[SaturnVault shared] entriesForHost:HostOf(wv)] : @[];
    if (m.count) { [self fillEntry:m.firstObject]; return; }
    if (!_key.hidden) [self showPopover];
    else NSBeep();
}

- (void)fillEntry:(NSDictionary *)e {
    WKWebView *wv = _current();
    if (!wv || !HostOf(wv)) return;
    NSString *user = e[@"username"] ?: @"", *pass = e[@"password"] ?: @"";
    NSData *json = [NSJSONSerialization dataWithJSONObject:@[user, pass] options:0 error:nil];
    NSString *args = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    NSString *fill = @R"JS(
(function(a){
  var u = a[0], p = a[1];
  function setValue(el, v){
    var d = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
    d.set.call(el, v);
    el.dispatchEvent(new Event('input', {bubbles: true}));
    el.dispatchEvent(new Event('change', {bubbles: true}));
  }
  var pws = pwFields();
  if (pws.length) {
    var pw = pws[0], us = userField(pw);
    if (us && u) setValue(us, u);
    setValue(pw, p);
    return 'filled';
  }
  var cands = Array.prototype.filter.call(document.querySelectorAll('input'), function(el){
    var t = (el.type || 'text').toLowerCase();
    return (t === 'text' || t === 'email' || t === 'tel') && visible(el);
  });
  if (cands.length && u) { setValue(cands[0], u); return 'username'; }
  return 'none';
})
)JS";
    NSString *js = [NSString stringWithFormat:@"(function(){%@ return %@(%@);})()", kHelpers, fill, args];
    [wv evaluateJavaScript:js inFrame:nil inContentWorld:VaultWorld() completionHandler:^(id r, NSError *err) { (void)r; (void)err; }];
}

@end
