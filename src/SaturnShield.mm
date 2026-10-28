#import "YavqoTheme.h"
#import "SaturnShield.h"
#import "SaturnShieldLists.h"
#import <QuartzCore/QuartzCore.h>

@implementation SaturnShieldStats

- (NSInteger)totalBlocked {
    return _adsBlocked + _trackersBlocked + _annoyancesBlocked;
}

- (NSString *)dataSavedFormatted {
    NSInteger total = [self totalBlocked];
    double kb = total * 75.0; // Approx 75KB per blocked tracker/script/ad
    if (kb > 1024) {
        return [NSString stringWithFormat:@"%.1f MB", kb / 1024.0];
    }
    return [NSString stringWithFormat:@"%.0f KB", kb];
}

- (NSString *)timeSavedFormatted {
    NSInteger total = [self totalBlocked];
    double s = (total * 95.0) / 1000.0; // Approx 95ms saved per blocked tracker
    return [NSString stringWithFormat:@"%.1fs", MAX(0.2, s)];
}

@end

// Regex for one list entry: a host (optionally with a path) anchored to the start of the URL.
static NSString *SaturnShieldURLFilterForEntry(NSString *entry) {
    NSString *host = entry, *path = nil;
    NSRange slash = [entry rangeOfString:@"/"];
    if (slash.location != NSNotFound) { host = [entry substringToIndex:slash.location]; path = [entry substringFromIndex:slash.location]; }
    NSString *(^esc)(NSString *) = ^NSString *(NSString *t) {
        t = [t stringByReplacingOccurrencesOfString:@"." withString:@"\\."];
        return [t stringByReplacingOccurrencesOfString:@"?" withString:@"\\?"];
    };
    return [NSString stringWithFormat:@"^[^:]+://+([^:/]+\\.)?%@%@", esc(host), path ? esc(path) : @"[:/]"];
}

@implementation SaturnShield {
    WKContentRuleList *_ruleList;
    NSMapTable<WKWebView *, SaturnShieldStats *> *_statsMap;
}

+ (instancetype)shared {
    static SaturnShield *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[SaturnShield alloc] init]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _isShieldGloballyEnabled = YES;
        _blockCookieNotices = YES;
        _blockPopups = YES;
        _aggressiveMode = YES;
        _disabledHosts = [NSMutableSet set];
        _statsMap = [NSMapTable weakToStrongObjectsMapTable];
        [self loadSettings];
        [self setupContentRulesWithCompletion:nil];
    }
    return self;
}

- (void)loadSettings {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if ([ud objectForKey:@"saturn.shieldEnabled"] != nil) {
        _isShieldGloballyEnabled = [ud boolForKey:@"saturn.shieldEnabled"];
    } else {
        _isShieldGloballyEnabled = YES;
    }
    if ([ud objectForKey:@"saturn.shieldCookieNotices"] != nil) {
        _blockCookieNotices = [ud boolForKey:@"saturn.shieldCookieNotices"];
    } else {
        _blockCookieNotices = YES;
    }
    if ([ud objectForKey:@"saturn.shieldPopups"] != nil) {
        _blockPopups = [ud boolForKey:@"saturn.shieldPopups"];
    } else {
        _blockPopups = YES;
    }
    NSArray *dis = [ud arrayForKey:@"saturn.shieldDisabledHosts"];
    if (dis) {
        _disabledHosts = [NSMutableSet setWithArray:dis];
    }
}

- (void)saveSettings {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:_isShieldGloballyEnabled forKey:@"saturn.shieldEnabled"];
    [ud setBool:_blockCookieNotices forKey:@"saturn.shieldCookieNotices"];
    [ud setBool:_blockPopups forKey:@"saturn.shieldPopups"];
    [ud setObject:[_disabledHosts allObjects] forKey:@"saturn.shieldDisabledHosts"];
    [ud synchronize];
}

- (BOOL)isShieldEnabledForHost:(NSString *)host {
    if (!self.isShieldGloballyEnabled) return NO;
    if (!host.length) return YES;
    return ![_disabledHosts containsObject:[host lowercaseString]];
}

- (void)setShieldEnabled:(BOOL)enabled forHost:(NSString *)host {
    if (!host.length) return;
    NSString *h = [host lowercaseString];
    if (enabled) {
        [_disabledHosts removeObject:h];
    } else {
        [_disabledHosts addObject:h];
    }
    [self saveSettings];
}

- (WKContentRuleList *)currentRuleList {
    return _ruleList;
}

- (void)recordBlockedCategory:(NSString *)category count:(NSInteger)count forWebView:(WKWebView *)webView {
    if (!webView) return;
    SaturnShieldStats *st = [_statsMap objectForKey:webView];
    if (!st) {
        st = [[SaturnShieldStats alloc] init];
        [_statsMap setObject:st forKey:webView];
    }
    if ([category isEqualToString:@"trackers"]) {
        st.trackersBlocked += count;
    } else if ([category isEqualToString:@"annoyances"]) {
        st.annoyancesBlocked += count;
    } else {
        st.adsBlocked += count;
    }
}

- (SaturnShieldStats *)statsForWebView:(WKWebView *)webView {
    if (!webView) return [[SaturnShieldStats alloc] init];
    SaturnShieldStats *st = [_statsMap objectForKey:webView];
    if (!st) {
        st = [[SaturnShieldStats alloc] init];
        [_statsMap setObject:st forKey:webView];
    }
    return st;
}

- (NSInteger)blockedCountForWebView:(WKWebView *)webView {
    return [[self statsForWebView:webView] totalBlocked];
}

- (void)resetBlockedCountForWebView:(WKWebView *)webView {
    if (!webView) return;
    [_statsMap removeObjectForKey:webView];
}

- (void)setupContentRulesWithCompletion:(void(^)(WKContentRuleList *ruleList, NSError *error))completion {
    if (_ruleList) {
        if (completion) completion(_ruleList, nil);
        return;
    }

    // WebKit's content-rule regex has no alternation ("a|b"), so each host gets its own rule. Rules are anchored to the
    // request's host, so "hotjar.com" blocks script.hotjar.com but never a page that merely mentions it in a query string.
    NSMutableArray<NSDictionary *> *rules = [NSMutableArray array];
    NSArray *subresourceTypes = @[@"image", @"style-sheet", @"script", @"font", @"raw", @"svg-document", @"media", @"popup", @"ping"];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    void (^blockHosts)(NSArray<NSString *> *) = ^(NSArray<NSString *> *entries) {
        for (NSString *entry in entries) {
            if (!entry.length || [seen containsObject:entry]) continue;
            [seen addObject:entry];
            NSString *re = SaturnShieldURLFilterForEntry(entry);
            // Subresources and requests from scripts...
            [rules addObject:@{@"trigger": @{@"url-filter": re, @"resource-type": subresourceTypes}, @"action": @{@"type": @"block"}}];
            // ...and ad iframes. Opening one of these sites yourself (a top-level page) still works.
            [rules addObject:@{@"trigger": @{@"url-filter": re, @"resource-type": @[@"document"], @"load-context": @[@"child-frame"]}, @"action": @{@"type": @"block"}}];
        }
    };
    blockHosts(SaturnShieldAdHosts());
    blockHosts(SaturnShieldTrackerHosts());
    blockHosts(SaturnShieldMinerHosts());
    // Regional Google ad service hosts (adservice.google.de, adservice.google.co.uk, ...)
    [rules addObject:@{@"trigger": @{@"url-filter": @"^[^:]+://+adservice\\.google\\.", @"resource-type": subresourceTypes}, @"action": @{@"type": @"block"}}];
    [rules addObject:@{@"trigger": @{@"url-filter": @"sentry\\.io/api/[0-9]+/envelope"}, @"action": @{@"type": @"block"}}];
    // Ad and tracker URL paths (scripts, images and requests only)
    for (NSString *path in @[@"/pagead/", @"/advert/", @"/adserver/", @"/ad_tag", @"/banner_ad", @"/popunder", @"/adclick", @"/adframe.", @"/ads.js",
                             @"/adsbygoogle.js", @"/show_ads", @"/prebid.js", @"/prebid-", @"/adsense/", @"/admanager/", @"/adloader", @"/fbevents.js",
                             @"/gtag/js", @"/analytics.js?", @"/ga.js", @"/beacon.js"]) {
        [rules addObject:@{@"trigger": @{@"url-filter": [path stringByReplacingOccurrencesOfString:@"." withString:@"\\."], @"resource-type": @[@"script", @"image", @"raw", @"ping"]}, @"action": @{@"type": @"block"}}];
    }
    // Cosmetic element hiding, in chunks so one odd selector cannot take the whole list down
    NSArray<NSString *> *selectors = SaturnShieldCosmeticSelectors();
    for (NSUInteger i = 0; i < selectors.count; i += 24) {
        NSArray *chunk = [selectors subarrayWithRange:NSMakeRange(i, MIN(24, selectors.count - i))];
        [rules addObject:@{@"trigger": @{@"url-filter": @".*"}, @"action": @{@"type": @"css-display-none", @"selector": [chunk componentsJoinedByString:@", "]}}];
    }
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:rules options:0 error:nil];
    NSString *json = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

    WKContentRuleListStore *store = [WKContentRuleListStore defaultStore];
    [store compileContentRuleListForIdentifier:@"SaturnShieldRules2"
                        encodedContentRuleList:json
                             completionHandler:^(WKContentRuleList *list, NSError *err) {
        if (list) {
            self->_ruleList = list;
            NSLog(@"[saturn] Saturn Shield Pro rule list compiled successfully");
        } else {
            NSLog(@"[saturn] Saturn Shield Pro rule compilation error: %@", err.localizedDescription);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(list, err);
        });
    }];
}

@end

static NSString *HostAlternation(NSArray<NSString *> *entries) {
    NSMutableArray *parts = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSString *e in entries) {
        if ([e containsString:@"/"] || [e containsString:@"*"] || [seen containsObject:e]) continue;   // plain hosts only
        [seen addObject:e];
        [parts addObject:[e stringByReplacingOccurrencesOfString:@"." withString:@"\\\\."]];
    }
    return [parts componentsJoinedByString:@"|"];
}

NSString *SaturnShieldGetBlockingScript(void) {
    static NSString *cached;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *tpl = @R"JS((function() {
  if (window.__saturn_shield_pro_injected) return;
  window.__saturn_shield_pro_injected = true;

  function reportBlocked(cat, count) {
    try { window.webkit.messageHandlers.shieldBlocked.postMessage({ category: cat || 'ads', count: count || 1 }); } catch (e) {}
  }

  // Requests to listed hosts are blocked by the browser's own rules (so they fail like any blocked request).
  // These patterns only count them for the shield popover; every call still goes through unchanged.
  var adRe = new RegExp('^[a-z][a-z0-9+.-]*://([^/:?#]+\\.)?(__AD_HOSTS__)([:/?#]|$)', 'i');
  var trRe = new RegExp('^[a-z][a-z0-9+.-]*://([^/:?#]+\\.)?(__TRACKER_HOSTS__)([:/?#]|$)', 'i');
  function classify(u) {
    try { u = new URL(String(u), location.href).href; } catch (e) { return null; }
    if (adRe.test(u)) return 'ads';
    if (trRe.test(u)) return 'trackers';
    return null;
  }
  function count(u) { var c = classify(u); if (c) reportBlocked(c, 1); }

  // 1. Anti-adblock wall defusers: stub the well-known detector libraries so they never show "AdBlock detected".
  try {
    var det = {
      check: function() { return false; }, onDetected: function() { return det; },
      onNotDetected: function(cb) { if (typeof cb === 'function') { try { cb(); } catch (e) {} } return det; },
      setOption: function() { return det; }, clearEvent: function() { return det; }, emitEvent: function() { return det; }
    };
    if (!window.fuckAdBlock) window.fuckAdBlock = det;
    if (!window.blockAdBlock) window.blockAdBlock = det;
    if (!window.adsbygoogle) window.adsbygoogle = [];
  } catch (e) {}

  // 2. Cosmetic filters
  var css = '__CSS__ { display: none !important; visibility: hidden !important; height: 0 !important; min-height: 0 !important; max-height: 0 !important; pointer-events: none !important; }';
  function injectCSS() {
    if (document.getElementById('__saturn_shield_style')) return;
    var style = document.createElement('style');
    style.id = '__saturn_shield_style';
    style.textContent = css;
    (document.head || document.documentElement).appendChild(style);
  }
  injectCSS();
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', injectCSS);

  // 3. Count requests that scripts make to listed hosts (fetch, XHR, beacons, dynamic <script>/<iframe>/<img>)
  if (window.fetch) {
    var origFetch = window.fetch;
    window.fetch = function(input) {
      try { count(typeof input === 'string' ? input : (input && input.url) || ''); } catch (e) {}
      return origFetch.apply(this, arguments);
    };
  }
  if (window.XMLHttpRequest) {
    var origOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(method, url) {
      try { count(url); } catch (e) {}
      return origOpen.apply(this, arguments);
    };
  }
  if (navigator.sendBeacon) {
    var origBeacon = navigator.sendBeacon.bind(navigator);
    navigator.sendBeacon = function(url) { try { count(url); } catch (e) {} return origBeacon.apply(null, arguments); };
  }
  try {
    var origSetAttr = Element.prototype.setAttribute;
    Element.prototype.setAttribute = function(name, value) {
      if (name === 'src' && /^(SCRIPT|IFRAME|IMG)$/.test(this.tagName)) { try { count(value); } catch (e) {} }
      return origSetAttr.apply(this, arguments);
    };
  } catch (e) {}

  // 4. Hide ads that appear after load, and count them
  var adSelector = '.adsbygoogle, [id^="div-gpt-ad"], [id*="google_ads_iframe"], [data-ad-slot], [data-ad-client], iframe[src*="doubleclick"], iframe[src*="googlesyndication"], iframe[src*="adservice"], .sponsored-post, .ad-container, .ad-slot';
  var scheduled = false;
  function sweep() {
    scheduled = false;
    var nodes = document.querySelectorAll(adSelector);
    for (var i = 0; i < nodes.length; i++) {
      var el = nodes[i];
      if (el && !el.__saturn_blocked) {
        el.__saturn_blocked = true;
        el.style.setProperty('display', 'none', 'important');
        reportBlocked('ads', 1);
      }
    }
  }
  var observer = new MutationObserver(function() { if (!scheduled) { scheduled = true; setTimeout(sweep, 250); } });
  function observe() { if (document.documentElement) observer.observe(document.documentElement, { childList: true, subtree: true }); }
  observe();
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', sweep); else sweep();

  // 5. Video ad skipper
  setInterval(function() {
    var skipBtn = document.querySelector('.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button, .ytp-ad-overlay-close-button');
    if (skipBtn) { skipBtn.click(); reportBlocked('ads', 1); }
    var adShowing = document.querySelector('.ad-showing, .ad-interrupting, .video-ads.ytp-ad-module');
    if (adShowing) {
      var video = document.querySelector('video');
      if (video && !isNaN(video.duration) && video.duration > 0 && isFinite(video.duration)) { video.currentTime = video.duration; reportBlocked('ads', 1); }
    }
  }, 250);

  // 6. Dismiss cookie consent banners
  setInterval(function() {
    var sels = ['#onetrust-reject-all-handler', '#onetrust-accept-btn-handler', '.cc-btn.cc-dismiss', '.cmp-intro_acceptAll', '[id*="cookie-accept"]', '[class*="cookie-accept"]', '.accept-cookies-button', 'button[id*="accept-all"]'];
    for (var i = 0; i < sels.length; i++) {
      var btn = document.querySelector(sels[i]);
      if (btn && !btn.__saturn_dismissed) { btn.__saturn_dismissed = true; btn.click(); reportBlocked('annoyances', 1); break; }
    }
  }, 700);
})();)JS";
        NSString *css = [SaturnShieldCosmeticSelectors() componentsJoinedByString:@", "];
        css = [css stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
        tpl = [tpl stringByReplacingOccurrencesOfString:@"__AD_HOSTS__" withString:HostAlternation(SaturnShieldAdHosts())];
        tpl = [tpl stringByReplacingOccurrencesOfString:@"__TRACKER_HOSTS__" withString:HostAlternation(SaturnShieldTrackerHosts())];
        cached = [tpl stringByReplacingOccurrencesOfString:@"__CSS__" withString:css];
    });
    return cached;
}

#pragma mark - Saturn Shield Pro Popover Controller

@implementation SaturnShieldPopoverController {
    NSVisualEffectView *_rootView;
    NSTextField *_statusTitle;
    NSTextField *_hostLabel;
    NSTextField *_adsCountLabel;
    NSTextField *_trackersCountLabel;
    NSTextField *_annoyancesCountLabel;
    NSTextField *_dataSavedLabel;
    NSButton *_toggleBtn;
    BOOL _isEnabled;
}

- (instancetype)initWithHost:(NSString *)host webView:(WKWebView *)wv {
    self = [super init];
    if (self) {
        _host = [host copy] ?: @"Current Site";
        _webView = wv;
        _stats = [[SaturnShield shared] statsForWebView:wv];
        _isEnabled = [[SaturnShield shared] isShieldEnabledForHost:_host];
    }
    return self;
}

- (void)loadView {
    CGFloat W = 330;
    CGFloat H = 290;
    _rootView = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0, 0, W, H)];
    _rootView.material = NSVisualEffectMaterialHUDWindow;
    _rootView.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    _rootView.state = NSVisualEffectStateActive;
    _rootView.wantsLayer = YES;
    _rootView.layer.cornerRadius = 14;
    _rootView.layer.masksToBounds = YES;

    // Dark tint
    NSView *tint = [[NSView alloc] initWithFrame:_rootView.bounds];
    tint.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    tint.wantsLayer = YES;
    tint.layer.backgroundColor = [NSColor whiteColor].CGColor;
    [_rootView addSubview:tint positioned:NSWindowBelow relativeTo:nil];

    // 1. Header (Shield icon + Title + Version Badge)
    NSImageView *shieldIcon = [[NSImageView alloc] initWithFrame:NSMakeRect(16, H - 36, 22, 22)];
    shieldIcon.image = [NSImage imageWithSystemSymbolName:@"shield.fill" accessibilityDescription:nil];
    shieldIcon.contentTintColor = Y_positive();
    [_rootView addSubview:shieldIcon];

    _statusTitle = [NSTextField labelWithString:_isEnabled ? @"Saturn Shield Pro" : @"Shield Paused"];
    _statusTitle.font = [NSFont systemFontOfSize:14 weight:NSFontWeightBold];
    _statusTitle.textColor = Y_ink();
    _statusTitle.frame = NSMakeRect(44, H - 35, 160, 20);
    [_rootView addSubview:_statusTitle];

    NSTextField *proBadge = [NSTextField labelWithString:@"ACTIVE"];
    proBadge.font = [NSFont systemFontOfSize:9.5 weight:NSFontWeightBold];
    proBadge.textColor = Y_positive();
    proBadge.alignment = NSTextAlignmentCenter;
    proBadge.wantsLayer = YES;
    proBadge.layer.backgroundColor = Y_soft().CGColor;
    proBadge.layer.borderColor = Y_hairline().CGColor;
    proBadge.layer.borderWidth = 0.5;
    proBadge.layer.cornerRadius = 4;
    proBadge.frame = NSMakeRect(W - 74, H - 33, 58, 18);
    [_rootView addSubview:proBadge];

    // 2. Host Pill Box
    NSView *hostBox = [[NSView alloc] initWithFrame:NSMakeRect(16, H - 68, W - 32, 24)];
    hostBox.wantsLayer = YES;
    hostBox.layer.cornerRadius = 6;
    hostBox.layer.backgroundColor = Y_soft().CGColor;
    hostBox.layer.borderColor = Y_hairline().CGColor;
    hostBox.layer.borderWidth = 0.5;

    _hostLabel = [NSTextField labelWithString:_host];
    _hostLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    _hostLabel.textColor = Y_ink();
    _hostLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _hostLabel.frame = NSMakeRect(8, 3, hostBox.bounds.size.width - 16, 16);
    [hostBox addSubview:_hostLabel];
    [_rootView addSubview:hostBox];

    // 3. 3-Column Metrics Dashboard (Ads, Trackers, Annoyances)
    CGFloat colW = (W - 32 - 16) / 3.0;
    CGFloat cardH = 62;
    CGFloat cardY = H - 140;

    // Col 1: Ads
    NSView *c1 = [self makeMetricCardWithFrame:NSMakeRect(16, cardY, colW, cardH)
                                         title:@"Ads Blocked"
                                         count:[NSString stringWithFormat:@"%ld", (long)_stats.adsBlocked]
                                         color:Y_blue()];
    _adsCountLabel = [c1 viewWithTag:101];
    [_rootView addSubview:c1];

    // Col 2: Trackers
    NSView *c2 = [self makeMetricCardWithFrame:NSMakeRect(16 + colW + 8, cardY, colW, cardH)
                                         title:@"Trackers"
                                         count:[NSString stringWithFormat:@"%ld", (long)_stats.trackersBlocked]
                                         color:Y_ink()];
    _trackersCountLabel = [c2 viewWithTag:101];
    [_rootView addSubview:c2];

    // Col 3: Annoyances
    NSView *c3 = [self makeMetricCardWithFrame:NSMakeRect(16 + (colW + 8)*2, cardY, colW, cardH)
                                         title:@"Annoyances"
                                         count:[NSString stringWithFormat:@"%ld", (long)_stats.annoyancesBlocked]
                                         color:Y_positive()];
    _annoyancesCountLabel = [c3 viewWithTag:101];
    [_rootView addSubview:c3];

    // 4. Savings Banner (Data & Time saved)
    NSView *savingsBox = [[NSView alloc] initWithFrame:NSMakeRect(16, cardY - 44, W - 32, 34)];
    savingsBox.wantsLayer = YES;
    savingsBox.layer.cornerRadius = 8;
    savingsBox.layer.backgroundColor = Y_soft().CGColor;
    savingsBox.layer.borderColor = Y_hairline().CGColor;
    savingsBox.layer.borderWidth = 0.5;

    _dataSavedLabel = [NSTextField labelWithString:[NSString stringWithFormat:@"⚡️ ~%@ bandwidth saved  •  %@ faster", _stats.dataSavedFormatted, _stats.timeSavedFormatted]];
    _dataSavedLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    _dataSavedLabel.textColor = Y_blue();
    _dataSavedLabel.alignment = NSTextAlignmentCenter;
    _dataSavedLabel.frame = NSMakeRect(6, 8, savingsBox.bounds.size.width - 12, 18);
    [savingsBox addSubview:_dataSavedLabel];
    [_rootView addSubview:savingsBox];

    // 5. Toggle Switch Action Button
    _toggleBtn = [NSButton buttonWithTitle:_isEnabled ? @"Shield Protection: ON" : @"Shield Protection: OFF" target:self action:@selector(toggleAction:)];
    _toggleBtn.frame = NSMakeRect(16, 16, W - 32, 34);
    _toggleBtn.bezelStyle = NSBezelStyleRounded;
    _toggleBtn.bordered = NO;
    _toggleBtn.font = [NSFont systemFontOfSize:12.5 weight:NSFontWeightSemibold];
    _toggleBtn.wantsLayer = YES;
    _toggleBtn.layer.cornerRadius = 17;
    [self updateToggleAppearance];
    [_rootView addSubview:_toggleBtn];

    self.view = _rootView;
}

- (NSView *)makeMetricCardWithFrame:(NSRect)frame title:(NSString *)title count:(NSString *)count color:(NSColor *)color {
    NSView *card = [[NSView alloc] initWithFrame:frame];
    card.wantsLayer = YES;
    card.layer.cornerRadius = 8;
    card.layer.backgroundColor = Y_soft().CGColor;
    card.layer.borderColor = Y_hairline().CGColor;
    card.layer.borderWidth = 0.5;

    NSTextField *countLbl = [NSTextField labelWithString:count];
    countLbl.font = [NSFont systemFontOfSize:18 weight:NSFontWeightBold];
    countLbl.textColor = color;
    countLbl.alignment = NSTextAlignmentCenter;
    countLbl.frame = NSMakeRect(4, 24, frame.size.width - 8, 22);
    countLbl.tag = 101;
    [card addSubview:countLbl];

    NSTextField *titleLbl = [NSTextField labelWithString:title];
    titleLbl.font = [NSFont systemFontOfSize:9.5 weight:NSFontWeightMedium];
    titleLbl.textColor = Y_muted();
    titleLbl.alignment = NSTextAlignmentCenter;
    titleLbl.frame = NSMakeRect(4, 6, frame.size.width - 8, 14);
    [card addSubview:titleLbl];

    return card;
}

- (void)updateToggleAppearance {
    if (_isEnabled) {
        _toggleBtn.title = @"Shield Protection: ON";
        _toggleBtn.layer.backgroundColor = Y_positive().CGColor;
        _toggleBtn.contentTintColor = [NSColor whiteColor];
        _statusTitle.stringValue = @"Saturn Shield Pro";
    } else {
        _toggleBtn.title = @"Shield Protection: OFF";
        _toggleBtn.layer.backgroundColor = Y_soft().CGColor;
        _toggleBtn.contentTintColor = Y_ink();
        _statusTitle.stringValue = @"Shield Paused";
    }
}

- (void)toggleAction:(id)sender {
    _isEnabled = !_isEnabled;
    [[SaturnShield shared] setShieldEnabled:_isEnabled forHost:_host];
    [self updateToggleAppearance];

    if (self.onToggleShield) {
        self.onToggleShield(_isEnabled);
    }
    if (_webView) {
        [_webView reload];
    }
}

@end
