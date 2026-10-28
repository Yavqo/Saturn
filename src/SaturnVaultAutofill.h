#pragma once
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

// Connects Yavqo Vault to one browser window: spots login forms, offers to save a login after you sign in,
// and fills a saved login only when you pick it (nothing is ever filled silently).
@interface SaturnVaultAutofill : NSObject
@property (class, nonatomic, readonly) NSString *messageHandlerName;   // "yavqoVault"
+ (NSString *)pageScriptSource;
+ (WKContentWorld *)world;   // isolated world for the page script and for filling

// keyButton: the key icon in the address bar. isPrivate: private windows never offer to save.
- (instancetype)initWithKeyButton:(NSButton *)keyButton privateWindow:(BOOL)isPrivate currentWebView:(WKWebView *(^)(void))currentWebView;
- (void)handleScriptMessage:(WKScriptMessage *)message;
- (void)refresh;              // call when the tab or page changes
- (void)togglePopover;        // the key button's action
- (void)fillFirstMatch;       // menu command: fill the only/first saved login for this page
@end
