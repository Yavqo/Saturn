#pragma once
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

// Posted on the main thread when extensions are installed, removed, enabled, disabled or reloaded.
extern NSNotificationName const SaturnExtensionsChangedNotification;
// Posted when an extension asks to open a tab. object = the web view the request came from, userInfo[@"url"] = NSURL.
extern NSNotificationName const SaturnExtensionOpenURLNotification;

// Saturn extensions: small packages (manifest.json + scripts, styles and an optional popup) that add features to pages.
// See docs/extensions.md. Content scripts run in an isolated JavaScript world per extension, so websites cannot see
// or tamper with them; permissions are shown to you before anything is installed.
//
// Each installed extension is an NSDictionary:
//   id, name, version, description, author, enabled (BOOL), dev (BOOL: loaded from a folder), dir, error (NSString or nil),
//   permissions (NSArray<NSString *>), sites (NSArray<NSString *> match patterns), popup (BOOL), icon (relative path or nil)
@interface SaturnExtensions : NSObject
+ (instancetype)shared;

@property (nonatomic, readonly) NSArray<NSDictionary *> *installed;
@property (nonatomic, copy) WKWebView *(^activeWebViewProvider)(void);   // the page a popup talks to ("activeTab")

+ (NSString *)extensionsDirectory;        // ~/Library/Application Support/Saturn/Extensions

// Web integration ---------------------------------------------------------------------------------------------------
// Adds the content scripts of every enabled extension to a tab's controller (replacing any added earlier).
- (void)applyToController:(WKUserContentController *)controller;
// Serves saturn-extension://<id>/<file> (popup pages, icons, web-accessible resources).
- (id<WKURLSchemeHandler>)schemeHandler;
// The saturn://extensions page.
- (NSString *)pageHTML;
// Messages from the saturn://extensions page. Ignored unless they come from that page.
- (void)handlePageMessage:(WKScriptMessage *)message;

// Managing -----------------------------------------------------------------------------------------------------------
- (void)setEnabled:(BOOL)enabled forExtensionID:(NSString *)extID;
- (void)removeExtensionID:(NSString *)extID;
- (void)reloadExtensionID:(NSString *)extID;
- (void)reloadAll;
- (NSDictionary *)extensionWithID:(NSString *)extID;

// Toolbar ------------------------------------------------------------------------------------------------------------
- (void)showPopupForExtensionID:(NSString *)extID relativeToView:(NSView *)view;
// Menu for the toolbar puzzle button: one item per enabled extension (action -openExtensionPopup:, representedObject = id),
// plus "Manage Extensions…" (tag 0) and "Extension Store…" (tag 1) which both call manageAction.
- (NSMenu *)toolbarMenuWithTarget:(id)target manageAction:(SEL)manageAction;
@end
