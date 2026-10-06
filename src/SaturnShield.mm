#import "YavqoTheme.h"
#import "SaturnShield.h"
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

    // WebKit's content-rule regex has no alternation ("a|b"), so each domain gets its own rule.
    NSMutableArray<NSDictionary *> *rules = [NSMutableArray array];
    NSString *(^esc)(NSString *) = ^NSString *(NSString *d) { return [d stringByReplacingOccurrencesOfString:@"." withString:@"\\."]; };
    void (^blockDomains)(NSArray<NSString *> *) = ^(NSArray<NSString *> *domains) {
        for (NSString *d in domains) {
            [rules addObject:@{@"trigger": @{@"url-filter": [@"[/.]" stringByAppendingString:esc(d)]}, @"action": @{@"type": @"block"}}];
        }
    };
    // 1. Ad networks and ad servers
    blockDomains(@[@"doubleclick.net", @"googlesyndication.com", @"googleadservices.com", @"adservice.google.", @"adnxs.com", @"criteo.com",
                   @"taboola.com", @"outbrain.com", @"scorecardresearch.com", @"ads.twitter.com", @"amazon-adsystem.com", @"popads.net",
                   @"adcolony.com", @"unityads.unity3d.com", @"rubiconproject.com", @"moatads.com", @"openx.net", @"pubmatic.com",
                   @"casalemedia.com", @"advertising.com", @"adroll.com", @"adtechus.com", @"bidswitch.net", @"smartadserver.com",
                   @"indexexchange.com", @"revcontent.com", @"adcash.com", @"propellerads.com", @"sovrn.com", @"thetradedesk.com", @"media.net"]);
    // 2. Tracking, telemetry and pixels
    blockDomains(@[@"google-analytics.com", @"hotjar.com", @"segment.io", @"mixpanel.com", @"clarity.ms", @"quantserve.com", @"appsflyer.com",
                   @"facebook.com/tr/", @"analytics.tiktok.com", @"mc.yandex.ru", @"statcounter.com", @"crazyegg.com", @"mouseflow.com",
                   @"newrelic.com/nr-spa"]);
    [rules addObject:@{@"trigger": @{@"url-filter": @"sentry\\.io/api/[0-9]+/envelope"}, @"action": @{@"type": @"block"}}];
    // 3. Crypto-miners
    blockDomains(@[@"coinhive.com", @"crypto-loot.com", @"webminerpool.com", @"minr.pw", @"coin-have.com"]);
    // 4. Ad URL paths (scripts and images only)
    for (NSString *path in @[@"/pagead/", @"/advert/", @"/adserver/", @"/ad_tag", @"/banner_ad", @"/popunder", @"/adclick"]) {
        [rules addObject:@{@"trigger": @{@"url-filter": esc(path), @"resource-type": @[@"script", @"image", @"raw"]}, @"action": @{@"type": @"block"}}];
    }
    // 5. Cosmetic element hiding
    NSString *cosmeticJSON = @"{\"trigger\":{\"url-filter\":\".*\"},\"action\":{\"type\":\"css-display-none\",\"selector\":\".adsbygoogle, [class*=\\\"ad-banner\\\"], [class*=\\\"ad_banner\\\"], [id*=\\\"ad-slot\\\"], [id*=\\\"ad_slot\\\"], .sponsored-post, [class*=\\\"sponsored\\\"], .ad-container, #ad-wrapper, .ad_unit, [class*=\\\"google-ad\\\"], [class*=\\\"google_ad\\\"], .dfp-ad-container, [id*=\\\"google_ads_iframe\\\"], iframe[src*=\\\"doubleclick\\\"], iframe[src*=\\\"adservice\\\"], iframe[src*=\\\"adnxs\\\"], .taboola, .outbrain, #carbonads, [class*=\\\"advertisement\\\"], [id*=\\\"advertisement\\\"], ytd-display-ad-renderer, ytd-promoted-sparkles-web-renderer, ytd-banner-promo-renderer, ytd-in-feed-ad-layout-renderer, #player-ads, .ytp-ad-module, .cookie-banner, #onetrust-banner-sdk, .qc-cmp2-container, [class*=\\\"cookie-notice\\\"]\"}}";
    id cosmetic = [NSJSONSerialization JSONObjectWithData:[cosmeticJSON dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if (cosmetic) [rules addObject:cosmetic];
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:rules options:0 error:nil];
    NSString *json = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

    WKContentRuleListStore *store = [WKContentRuleListStore defaultStore];
    [store compileContentRuleListForIdentifier:@"SaturnShieldProRules"
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

NSString *SaturnShieldGetBlockingScript(void) {
    return
    @"(function() {\n"
    "  if (window.__saturn_shield_pro_injected) return;\n"
    "  window.__saturn_shield_pro_injected = true;\n"
    "  \n"
    "  // 1. Anti-Adblock Defuser: mock probes so sites never show 'AdBlock Detected'\n"
    "  try {\n"
    "    window.fuckAdBlock = { check: function(){}, onDetected: function(){}, onNotDetected: function(cb){ if(typeof cb==='function') cb(); } };\n"
    "    window.blockAdBlock = window.fuckAdBlock;\n"
    "    window.canRunAds = true;\n"
    "    window.isAdBlockActive = false;\n"
    "    window.adsbygoogle = { loaded: true, push: function(e){ reportBlocked('ads', 1); } };\n"
    "    window.ga = function(){ reportBlocked('trackers', 1); };\n"
    "    window.gtag = function(){ reportBlocked('trackers', 1); };\n"
    "    window._gaq = { push: function(){ reportBlocked('trackers', 1); } };\n"
    "    window.fbq = function(){ reportBlocked('trackers', 1); };\n"
    "  } catch(e) {}\n"
    "  \n"
    "  // 2. Global Cosmetic Ad & Tracker Annihilation CSS\n"
    "  var css = '.adsbygoogle, [class*=\"ad-banner\"], [class*=\"ad_banner\"], [id*=\"ad-slot\"], [id*=\"ad_slot\"], .sponsored-post, [class*=\"sponsored\"], .ad-container, #ad-wrapper, .ad_unit, [class*=\"google-ad\"], [class*=\"google_ad\"], .dfp-ad-container, [id*=\"google_ads_iframe\"], iframe[src*=\"doubleclick.net\"], iframe[src*=\"adservice.google\"], iframe[src*=\"adnxs.com\"], iframe[src*=\"criteo.com\"], iframe[src*=\"taboola.com\"], iframe[src*=\"outbrain.com\"], .taboola, .outbrain, #carbonads, [class*=\"advertisement\"], [id*=\"advertisement\"], ytd-display-ad-renderer, ytd-promoted-sparkles-web-renderer, ytd-banner-promo-renderer, ytd-in-feed-ad-layout-renderer, #player-ads, .ytp-ad-module, .ytp-ad-overlay-container, .ytp-ad-message-container, .cookie-banner, #onetrust-banner-sdk, .qc-cmp2-container, [class*=\"cookie-notice\"], .didomi-popup-container { display: none !important; visibility: hidden !important; height: 0 !important; min-height: 0 !important; max-height: 0 !important; pointer-events: none !important; opacity: 0 !important; overflow: hidden !important; }';\n"
    "  function injectCSS() {\n"
    "    if (document.getElementById('__saturn_shield_style')) return;\n"
    "    var style = document.createElement('style');\n"
    "    style.id = '__saturn_shield_style';\n"
    "    style.textContent = css;\n"
    "    (document.head || document.documentElement).appendChild(style);\n"
    "  }\n"
    "  injectCSS();\n"
    "  if (document.readyState === 'loading') {\n"
    "    document.addEventListener('DOMContentLoaded', injectCSS);\n"
    "  }\n"
    "  \n"
    "  // 3. WebKit Reporting Function with Category Categorization\n"
    "  function reportBlocked(cat, count) {\n"
    "    try {\n"
    "      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.shieldBlocked) {\n"
    "        window.webkit.messageHandlers.shieldBlocked.postMessage({ category: cat || 'ads', count: count || 1 });\n"
    "      }\n"
    "    } catch(e) {}\n"
    "  }\n"
    "  \n"
    "  // 4. Tracker & Ad URL Regex Matcher\n"
    "  var trackerPattern = /(google-analytics\\.com|hotjar\\.com|segment\\.io|mixpanel\\.com|clarity\\.ms|quantserve\\.com|appsflyer\\.com|facebook\\.com\\/tr\\/|analytics\\.tiktok\\.com|mc\\.yandex\\.ru|statcounter\\.com|crazyegg\\.com|mouseflow\\.com|newrelic\\.com|sentry\\.io)/i;\n"
    "  var adPattern = /(doubleclick\\.net|googlesyndication\\.com|googleadservices\\.com|adservice\\.google\\.|adnxs\\.com|criteo\\.com|taboola\\.com|outbrain\\.com|scorecardresearch\\.com|ads\\.twitter\\.com|amazon-adsystem\\.com|popads\\.net|adcolony\\.com|unityads\\.unity3d\\.com|rubiconproject\\.com|moatads\\.com|openx\\.net|pubmatic\\.com|casalemedia\\.com|advertising\\.com|adroll\\.com|adtechus\\.com|bidswitch\\.net|smartadserver\\.com|indexexchange\\.com|revcontent\\.com|adcash\\.com|propellerads\\.com|sovrn\\.com|thetradedesk\\.com|media\\.net|\\/pagead\\/|\\/advert\\/|\\/adserver\\/|\\/ad_tag|\\/banner_ad|\\/popunder|\\/adclick)/i;\n"
    "  \n"
    "  // 5. Intercept Dynamic Script & Iframe Elements\n"
    "  var origCreateElement = document.createElement.bind(document);\n"
    "  document.createElement = function(tagName, options) {\n"
    "    var el = origCreateElement(tagName, options);\n"
    "    var tag = (tagName || '').toLowerCase();\n"
    "    if (tag === 'script' || tag === 'iframe') {\n"
    "      var origSetAttribute = el.setAttribute.bind(el);\n"
    "      el.setAttribute = function(name, value) {\n"
    "        if (name === 'src' && typeof value === 'string') {\n"
    "          if (trackerPattern.test(value)) { reportBlocked('trackers', 1); return; }\n"
    "          if (adPattern.test(value)) { reportBlocked('ads', 1); return; }\n"
    "        }\n"
    "        return origSetAttribute(name, value);\n"
    "      };\n"
    "      Object.defineProperty(el, 'src', {\n"
    "        set: function(val) {\n"
    "          if (typeof val === 'string') {\n"
    "            if (trackerPattern.test(val)) { reportBlocked('trackers', 1); return; }\n"
    "            if (adPattern.test(val)) { reportBlocked('ads', 1); return; }\n"
    "          }\n"
    "          el.setAttribute('src', val);\n"
    "        },\n"
    "        get: function() {\n"
    "          return el.getAttribute('src') || '';\n"
    "        }\n"
    "      });\n"
    "    }\n"
    "    return el;\n"
    "  };\n"
    "  \n"
    "  // 6. Network Interception (Fetch & XHR)\n"
    "  if (window.fetch) {\n"
    "    var origFetch = window.fetch;\n"
    "    window.fetch = function(input, init) {\n"
    "      var url = typeof input === 'string' ? input : (input && input.url ? input.url : '');\n"
    "      if (url) {\n"
    "        if (trackerPattern.test(url)) {\n"
    "          reportBlocked('trackers', 1);\n"
    "          return Promise.resolve(new Response('{}', { status: 200, statusText: 'Blocked by Saturn Shield' }));\n"
    "        }\n"
    "        if (adPattern.test(url)) {\n"
    "          reportBlocked('ads', 1);\n"
    "          return Promise.resolve(new Response('', { status: 200, statusText: 'Blocked by Saturn Shield' }));\n"
    "        }\n"
    "      }\n"
    "      return origFetch.apply(this, arguments);\n"
    "    };\n"
    "  }\n"
    "  if (window.XMLHttpRequest) {\n"
    "    var origOpen = XMLHttpRequest.prototype.open;\n"
    "    XMLHttpRequest.prototype.open = function(method, url) {\n"
    "      if (typeof url === 'string') {\n"
    "        if (trackerPattern.test(url)) { reportBlocked('trackers', 1); return; }\n"
    "        if (adPattern.test(url)) { reportBlocked('ads', 1); return; }\n"
    "      }\n"
    "      return origOpen.apply(this, arguments);\n"
    "    };\n"
    "  }\n"
    "  \n"
    "  // 7. Video Ad Fast-Forwarder & Auto-Skipper\n"
    "  setInterval(function() {\n"
    "    var skipBtn = document.querySelector('.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button, .ytp-ad-overlay-close-button');\n"
    "    if (skipBtn) {\n"
    "      skipBtn.click();\n"
    "      reportBlocked('ads', 1);\n"
    "    }\n"
    "    var adShowing = document.querySelector('.ad-showing, .ad-interrupting, .video-ads.ytp-ad-module');\n"
    "    if (adShowing) {\n"
    "      var video = document.querySelector('video');\n"
    "      if (video && !isNaN(video.duration) && video.duration > 0) {\n"
    "        video.currentTime = video.duration;\n"
    "        reportBlocked('ads', 1);\n"
    "      }\n"
    "    }\n"
    "  }, 200);\n"
    "  \n"
    "  // 8. Auto-Dismiss Cookie Consent Banners\n"
    "  setInterval(function() {\n"
    "    var cookieSelectors = ['#onetrust-accept-btn-handler', '.cc-btn.cc-dismiss', '.cmp-intro_acceptAll', '[id*=\"cookie-accept\"]', '[class*=\"cookie-accept\"]', '.accept-cookies-button', 'button[id*=\"accept-all\"]'];\n"
    "    for (var i = 0; i < cookieSelectors.length; i++) {\n"
    "      var btn = document.querySelector(cookieSelectors[i]);\n"
    "      if (btn && !btn.__saturn_dismissed) {\n"
    "        btn.__saturn_dismissed = true;\n"
    "        btn.click();\n"
    "        reportBlocked('annoyances', 1);\n"
    "        break;\n"
    "      }\n"
    "    }\n"
    "  }, 600);\n"
    "  \n"
    "  // 9. DOM Mutation Observer to Eliminate Injected Ad Nodes\n"
    "  var observer = new MutationObserver(function(mutations) {\n"
    "    var nodes = document.querySelectorAll('.adsbygoogle, [class*=\"ad-banner\"], [id*=\"ad-slot\"], .sponsored-post, [class*=\"sponsored\"], .ad-container, [id*=\"google_ads_iframe\"], iframe[src*=\"doubleclick\"], iframe[src*=\"adservice\"]');\n"
    "    for (var i = 0; i < nodes.length; i++) {\n"
    "      var el = nodes[i];\n"
    "      if (el && !el.__saturn_blocked) {\n"
    "        el.__saturn_blocked = true;\n"
    "        el.style.setProperty('display', 'none', 'important');\n"
    "        el.style.setProperty('height', '0px', 'important');\n"
    "        reportBlocked('ads', 1);\n"
    "      }\n"
    "    }\n"
    "  });\n"
    "  if (document.body || document.documentElement) {\n"
    "    observer.observe(document.body || document.documentElement, { childList: true, subtree: true });\n"
    "  }\n"
    "})();";
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
