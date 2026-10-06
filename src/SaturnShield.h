#pragma once
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@interface SaturnShieldStats : NSObject
@property (nonatomic, assign) NSInteger adsBlocked;
@property (nonatomic, assign) NSInteger trackersBlocked;
@property (nonatomic, assign) NSInteger annoyancesBlocked;
@property (nonatomic, readonly) NSInteger totalBlocked;
@property (nonatomic, readonly) NSString *dataSavedFormatted;
@property (nonatomic, readonly) NSString *timeSavedFormatted;
@end

@interface SaturnShield : NSObject

+ (instancetype)shared;

@property (nonatomic, assign) BOOL isShieldGloballyEnabled;
@property (nonatomic, assign) BOOL blockCookieNotices;
@property (nonatomic, assign) BOOL blockPopups;
@property (nonatomic, assign) BOOL aggressiveMode;
@property (nonatomic, strong) NSMutableSet<NSString *> *disabledHosts;

- (void)setupContentRulesWithCompletion:(void(^)(WKContentRuleList *ruleList, NSError *error))completion;
- (WKContentRuleList *)currentRuleList;

- (BOOL)isShieldEnabledForHost:(NSString *)host;
- (void)setShieldEnabled:(BOOL)enabled forHost:(NSString *)host;

- (void)recordBlockedCategory:(NSString *)category count:(NSInteger)count forWebView:(WKWebView *)webView;
- (SaturnShieldStats *)statsForWebView:(WKWebView *)webView;
- (NSInteger)blockedCountForWebView:(WKWebView *)webView;
- (void)resetBlockedCountForWebView:(WKWebView *)webView;

@end

NSString *SaturnShieldGetBlockingScript(void);

@interface SaturnShieldPopoverController : NSViewController
@property (nonatomic, copy) NSString *host;
@property (nonatomic, strong) SaturnShieldStats *stats;
@property (nonatomic, weak) WKWebView *webView;
@property (nonatomic, copy) void (^onToggleShield)(BOOL enabled);
- (instancetype)initWithHost:(NSString *)host webView:(WKWebView *)wv;
@end
