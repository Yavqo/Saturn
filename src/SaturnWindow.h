#pragma once
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@class SaturnWindow;

@interface ChromeTabView : NSView
@property (nonatomic, assign) NSInteger tabIndex;
@property (nonatomic, weak) SaturnWindow *hostWindow;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) NSImage *favicon;
@property (nonatomic, assign) BOOL active;
@property (nonatomic, assign) BOOL hovered;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) BOOL pinned;
@property (nonatomic, assign) BOOL privateMode;   // dark palette in private windows
@property (nonatomic, strong) NSURL *pendingURL;   // restored tab that has not been loaded yet
@property (nonatomic, copy) NSString *groupID;
@property (nonatomic, assign) BOOL dropTarget;
- (void)playAppear;
- (void)updateTitle:(NSString *)title favicon:(NSImage *)icon active:(BOOL)active;
@end

#import "SaturnVoiceAgent.h"

@interface SaturnWindow : NSWindow <WKNavigationDelegate, WKUIDelegate, NSTextFieldDelegate, WKScriptMessageHandler, SaturnVoiceAgentDelegate>
@property (nonatomic, strong) NSTextField *addressBar;
@property (nonatomic, strong) NSView *omniboxContainer;
@property (nonatomic, strong) NSButton *backBtn;
@property (nonatomic, strong) NSButton *forwardBtn;
@property (nonatomic, strong) NSButton *reloadBtn;
@property (nonatomic, strong) NSProgressIndicator *progress;
@property (nonatomic, strong) NSView *tabBar;
@property (nonatomic, strong) NSView *bookmarksBar;
@property (nonatomic, strong) NSMutableArray<ChromeTabView*> *tabs;
@property (nonatomic, strong) NSMutableArray<WKWebView*> *tabWebViews;
@property (nonatomic, assign) NSInteger activeTabIndex;
@property (nonatomic, strong) NSButton *addTabButton;
@property (nonatomic, strong) NSMutableDictionary<NSString*, NSImage*> *faviconCache;
@property (nonatomic, strong) NSButton *avatarButton;
@property (nonatomic, strong) NSImageView *avatarImageView;
@property (nonatomic, strong) NSButton *aiButton;
@property (nonatomic, strong) NSVisualEffectView *aiSidebar;
@property (nonatomic, assign) BOOL aiSidebarVisible;
@property (nonatomic, strong) NSMutableArray<NSDictionary*> *hannaHistory;
@property (nonatomic, strong) NSScrollView *hannaScrollView;
@property (nonatomic, strong) NSTextView *hannaTextView;
@property (nonatomic, strong) NSTextField *hannaInputField;
@property (nonatomic, strong) NSButton *hannaSendButton;
@property (nonatomic, strong) NSButton *hannaVoiceButton;
@property (nonatomic, strong) NSButton *hannaHeaderVoiceButton;
@property (nonatomic, strong) NSView *hannaVoiceHUD;
@property (nonatomic, strong) NSTextField *hannaVoiceStatusLabel;
@property (nonatomic, strong) NSTextField *hannaVoiceTranscriptLabel;
@property (nonatomic, strong) NSMutableArray<NSView *> *hannaVoiceWaveBars;
@property (nonatomic, strong) NSProgressIndicator *hannaSpinner;
@property (nonatomic, strong) NSView *hannaTypingView;
@property (nonatomic, strong) NSPopover *explainPopover;
@property (nonatomic, strong) NSMutableDictionary *lastContextMenuInfo;
@property (nonatomic, strong) NSButton *shieldButton;
@property (nonatomic, strong) NSPopover *shieldPopover;
// active webView convenience
@property (nonatomic, readonly) WKWebView *webView;
@property (nonatomic, readonly) ChromeTabView *activeTab;
- (void)toggleVoiceAgent:(id)sender;
- (void)showShieldPopover:(id)sender;
- (void)updateAvatarFromProfile;
- (void)toggleAISidebar;
- (void)hannaSend:(id)sender;
- (void)explainSelectionWithHannaText:(NSString *)text targetRect:(NSRect)rect webView:(WKWebView *)wv;
- (NSMenu *)buildCustomContextMenuForEvent:(NSEvent *)event webView:(WKWebView *)wv;
- (instancetype)initWithURL:(NSURL *)url;
- (instancetype)initWithURL:(NSURL *)url privateMode:(BOOL)privateMode;
@property (nonatomic, readonly) BOOL isPrivate;
- (void)navigateToString:(NSString *)urlString;
- (void)createNewTabWithURL:(NSURL *)url;
- (void)switchToTabAtIndex:(NSInteger)idx;
- (void)closeTabView:(ChromeTabView *)tab;
- (void)layoutTabs;
@property (nonatomic, assign) BOOL hannaActMode;   // Zarah can drive the browser
- (void)stopHannaAgent;
- (void)showUpdatePopover:(id)sender;
- (void)showFeedbackSheet:(id)sender;
- (void)offerDefaultBrowser;
- (void)presentPendingCrashReport;
- (void)agentStarted;
- (void)agentStep:(NSString *)text;
- (void)agentFinished:(NSString *)message isError:(BOOL)isError;
- (void)agentConfirmWithTitle:(NSString *)title detail:(NSString *)detail completion:(void (^)(BOOL allow))completion;
- (NSDictionary *)sessionState;
- (void)restoreSessionState:(NSDictionary *)state;
- (void)showHistoryPage:(id)sender;
- (void)reopenClosedTab:(id)sender;
@end
