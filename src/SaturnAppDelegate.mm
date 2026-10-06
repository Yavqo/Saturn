#import "SaturnAppDelegate.h"
#import "SaturnWindow.h"
#import "Supabase/SupabaseClient.h"
#import "Settings.h"
#import "SettingsWindow.h"
#import "SetupWindow.h"
#import "SaturnSession.h"
#import "SaturnHistory.h"
#import "SaturnPermissions.h"
#import "SaturnUpdater.h"
#import "SaturnDefaultBrowser.h"
#import "SaturnBookmarks.h"
#import "SaturnDownloads.h"
#import <WebKit/WebKit.h>

@implementation SaturnAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self buildMenu];
    [[SaturnUpdater shared] startAutomaticChecks];
    // Links opened from other apps: once the first window exists, open anything that arrived early
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.launched = YES;
        if (self.pendingURLs.count) { NSArray *urls = [self.pendingURLs copy]; [self.pendingURLs removeAllObjects]; [self openURLsInBrowser:urls]; }
    });
    // Offer to become the default browser (at most twice, never if it already is)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (![SaturnDefaultBrowser shouldOffer]) return;
        for (SaturnWindow *w in self.windows) if (!w.isPrivate) { [SaturnDefaultBrowser recordOfferShown]; [w offerDefaultBrowser]; break; }
    });
    // Offer to report a crash from last time, once the first window is up
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        for (SaturnWindow *w in self.windows) if (!w.isPrivate) { [w presentPendingCrashReport]; break; }
    });

    // Supabase scaffold
    [[SupabaseClient shared] configureFromEnvironment];
    if ([SupabaseClient shared].isConfigured) {
        [[SupabaseClient shared] pingWithCompletion:^(BOOL success, NSError *error){
            NSLog(@"[supabase] ping %@", success?@"ok":error.localizedDescription);
        }];
    }

    // Check if first launch setup is needed
    if (!SaturnSettings.shared.hasCompletedSetup) {
        NSLog(@"[saturn] First launch detected — showing Setup Window");
        [[SetupWindow shared] showSetupWithCompletion:^(SaturnSearchEngine selectedEngine) {
            (void)selectedEngine;
            NSString *home = SaturnSettings.shared.currentEngineInfo.homeURL;
            if (!home.length) home = @"https://www.google.com";
            NSURL *url = [NSURL URLWithString:self.initialURLString ?: home];
            [self createWindowWithURL:url];
            [NSApp activateIgnoringOtherApps:YES];
        }];
    } else {
        if (self.startPrivate) {
            [self createWindowWithURL:[NSURL URLWithString:self.initialURLString ?: SaturnSettings.shared.currentEngineInfo.homeURL ?: @"https://www.google.com"] privateMode:YES];
            [NSApp activateIgnoringOtherApps:YES];
            return;
        }
        // Reopen last session's windows, unless a URL was passed on launch
        NSArray<NSDictionary *> *saved = self.initialURLString.length ? @[] : [[SaturnSession shared] savedWindows];
        if (saved.count) {
            for (NSDictionary *state in saved) {
                NSURL *first = [NSURL URLWithString:state[@"tabs"][0][@"url"]];
                [self createWindowWithURL:first];
                [self.windows.lastObject restoreSessionState:state];
            }
        } else {
            NSString *home = SaturnSettings.shared.currentEngineInfo.homeURL;
            if (!home.length) home = @"https://www.google.com";
            NSURL *url = [NSURL URLWithString:self.initialURLString ?: home];
            [self createWindowWithURL:url];
        }
        [NSApp activateIgnoringOtherApps:YES];
    }
}

#pragma mark - Opening links from other apps

// macOS calls this when Saturn is the default browser and a link (or an .html file) is opened elsewhere.
- (void)application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls {
    (void)application;
    NSMutableArray<NSURL *> *ok = [NSMutableArray array];
    for (NSURL *u in urls) {
        NSString *scheme = u.scheme.lowercaseString;
        if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) [ok addObject:u];
        else if (u.isFileURL && [@[@"html", @"htm", @"xhtml", @"xht", @"pdf"] containsObject:u.pathExtension.lowercaseString]) [ok addObject:u];
    }
    if (!ok.count) return;
    if (!self.launched) {
        if (!self.pendingURLs) self.pendingURLs = [NSMutableArray array];
        [self.pendingURLs addObjectsFromArray:ok];
        return;
    }
    [self openURLsInBrowser:ok];
}

- (void)openURLsInBrowser:(NSArray<NSURL *> *)urls {
    SaturnWindow *w = nil;
    SaturnWindow *key = (SaturnWindow *)NSApp.keyWindow;
    if ([key isKindOfClass:[SaturnWindow class]] && !key.isPrivate) w = key;
    if (!w) for (SaturnWindow *x in self.windows) if (!x.isPrivate) { w = x; break; }
    if (!w) {
        if (!SaturnSettings.shared.hasCompletedSetup) { self.initialURLString = urls.firstObject.absoluteString; return; }   // first-run setup opens it
        [self createWindowWithURL:urls.firstObject];
        w = self.windows.lastObject;
        urls = [urls subarrayWithRange:NSMakeRange(1, urls.count - 1)];
    }
    for (NSURL *u in urls) [w createNewTabWithURL:u];
    [w makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

#pragma mark - Reset

// Settings > Reset Saturn: forget everything, close every window and run the first-run setup again.
- (void)resetBrowserAndRestartSetup {
    for (SaturnWindow *w in [self.windows copy]) [w close];

    [[SaturnHistory shared] clearSince:nil];
    [[SaturnHistory shared] flush];
    [[SaturnDownloads shared] clearFinished];
    [SaturnPermissions resetAll];
    [[SupabaseClient shared] clearSession];
    // Settings, session, sign-in, counters and every other saved preference
    [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:NSBundle.mainBundle.bundleIdentifier];
    [[SaturnBookmarks shared] resetToDefaults];
    [[SaturnSettings shared] load];   // nothing saved any more: setup not done, search engine back to the default

    // Cookies, logins, caches and site storage
    [[WKWebsiteDataStore defaultDataStore] removeDataOfTypes:[WKWebsiteDataStore allWebsiteDataTypes] modifiedSince:[NSDate distantPast] completionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [[SetupWindow shared] showSetupWithCompletion:^(SaturnSearchEngine selectedEngine) {
                (void)selectedEngine;
                NSString *home = SaturnSettings.shared.currentEngineInfo.homeURL;
                if (!home.length) home = @"https://www.google.com";
                [self createWindowWithURL:[NSURL URLWithString:home]];
                [NSApp activateIgnoringOtherApps:YES];
            }];
        });
    }];
}

#pragma mark - Default browser

- (void)makeDefaultBrowser:(id)sender {
    (void)sender;
    [SaturnDefaultBrowser makeDefaultWithCompletion:nil];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (item.action == @selector(makeDefaultBrowser:)) {
        BOOL already = [SaturnDefaultBrowser isDefault];
        item.title = already ? @"Saturn Is Your Default Browser" : @"Make Saturn Your Default Browser…";
        return !already;
    }
    return YES;
}

- (void)createWindowWithURL:(NSURL *)url { [self createWindowWithURL:url privateMode:NO]; }

- (void)newPrivateWindow:(id)sender {
    (void)sender;
    NSString *home = SaturnSettings.shared.currentEngineInfo.homeURL;
    if (!home.length) home = @"https://www.google.com";
    [self createWindowWithURL:[NSURL URLWithString:home] privateMode:YES];
}

- (void)createWindowWithURL:(NSURL *)url privateMode:(BOOL)privateMode {
    if (!self.windows) self.windows = [NSMutableArray array];
    SaturnWindow *w = [[SaturnWindow alloc] initWithURL:url privateMode:privateMode];
    [self.windows addObject:w];
    [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowWillCloseNotification object:w queue:nil usingBlock:^(NSNotification *note){
        [self.windows removeObject:w];
    }];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    if (!flag) {
        NSString *home = SaturnSettings.shared.currentEngineInfo.homeURL;
        if (!home.length) home = @"https://www.google.com";
        [self createWindowWithURL:[NSURL URLWithString:home]];
    }
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [[SaturnSession shared] saveNow];
    [[SaturnHistory shared] flush];
}

#pragma mark - Menu
- (void)buildMenu {
    NSMenu *mainMenu = [[NSMenu alloc] init];
    NSMenuItem *appItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:appItem];
    NSMenu *appMenu = [[NSMenu alloc] init];
    appItem.submenu = appMenu;
    [appMenu addItemWithTitle:@"About Saturn" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItemWithTitle:@"Check for Updates…" action:@selector(checkForUpdates:) keyEquivalent:@""];
    [appMenu addItemWithTitle:@"Make Saturn Your Default Browser…" action:@selector(makeDefaultBrowser:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Saturn Setup…" action:@selector(openSetup:) keyEquivalent:@""];
    [appMenu addItemWithTitle:@"Settings…" action:@selector(openSettings:) keyEquivalent:@","];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Reset Site Permissions…" action:@selector(resetSitePermissions:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Hide Saturn" action:@selector(hide:) keyEquivalent:@"h"];
    NSMenuItem *hideOthers = [appMenu addItemWithTitle:@"Hide Others" action:@selector(hideOtherApplications:) keyEquivalent:@"h"];
    hideOthers.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    [appMenu addItemWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit Saturn" action:@selector(terminate:) keyEquivalent:@"q"];

    NSMenuItem *fileItem = [[NSMenuItem alloc] init]; fileItem.title = @"File";
    [mainMenu addItem:fileItem];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"]; fileItem.submenu = fileMenu;
    [fileMenu addItemWithTitle:@"New Window" action:@selector(newWindow:) keyEquivalent:@"n"];
    [fileMenu addItemWithTitle:@"New Private Window" action:@selector(newPrivateWindow:) keyEquivalent:@"N"];
    [fileMenu addItemWithTitle:@"New Tab" action:@selector(newTab:) keyEquivalent:@"t"];
    [fileMenu addItemWithTitle:@"Close Tab" action:@selector(closeTab:) keyEquivalent:@"w"];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Print…" action:@selector(printPage:) keyEquivalent:@"p"];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Close Window" action:@selector(closeWindow:) keyEquivalent:@"W"];

    NSMenuItem *editItem = [[NSMenuItem alloc] init]; editItem.title = @"Edit";
    [mainMenu addItem:editItem];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"]; editItem.submenu = editMenu;
    [editMenu addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
    [editMenu addItemWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"Z"];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Find…" action:@selector(showFindBar:) keyEquivalent:@"f"];
    [editMenu addItemWithTitle:@"Find Next" action:@selector(findNextInPage:) keyEquivalent:@"g"];
    [editMenu addItemWithTitle:@"Find Previous" action:@selector(findPreviousInPage:) keyEquivalent:@"G"];

    NSMenuItem *viewItem = [[NSMenuItem alloc] init]; viewItem.title = @"View";
    [mainMenu addItem:viewItem];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"]; viewItem.submenu = viewMenu;
    [viewMenu addItemWithTitle:@"Reload" action:@selector(reloadView:) keyEquivalent:@"r"];
    [viewMenu addItemWithTitle:@"Reload Ignoring Cache" action:@selector(hardReload:) keyEquivalent:@"R"];
    [viewMenu addItemWithTitle:@"Stop Loading" action:@selector(stopLoadingPage:) keyEquivalent:@"."];
    [viewMenu addItemWithTitle:@"Back" action:@selector(backView:) keyEquivalent:@"["];
    [viewMenu addItemWithTitle:@"Forward" action:@selector(forwardView:) keyEquivalent:@"]"];
    [viewMenu addItem:[NSMenuItem separatorItem]];
    [viewMenu addItemWithTitle:@"Ask Zarah" action:@selector(toggleHanna:) keyEquivalent:@"i"];
    NSMenuItem *fs = [viewMenu addItemWithTitle:@"Enter Full Screen" action:@selector(toggleFullScreen:) keyEquivalent:@"f"];
    fs.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagControl;
    [viewMenu addItem:[NSMenuItem separatorItem]];
    [viewMenu addItemWithTitle:@"Focus Address Bar" action:@selector(focusAddress:) keyEquivalent:@"l"];
    [viewMenu addItemWithTitle:@"Downloads" action:@selector(showDownloads:) keyEquivalent:@"J"];
    [viewMenu addItem:[NSMenuItem separatorItem]];
    [viewMenu addItemWithTitle:@"Actual Size" action:@selector(actualSize:) keyEquivalent:@"0"];
    [viewMenu addItemWithTitle:@"Zoom In" action:@selector(zoomIn:) keyEquivalent:@"+"];
    [viewMenu addItemWithTitle:@"Zoom Out" action:@selector(zoomOut:) keyEquivalent:@"-"];

    NSMenuItem *histItem = [[NSMenuItem alloc] init]; histItem.title = @"History";
    [mainMenu addItem:histItem];
    NSMenu *histMenu = [[NSMenu alloc] initWithTitle:@"History"]; histItem.submenu = histMenu;
    [histMenu addItemWithTitle:@"Show All History" action:@selector(showHistoryPage:) keyEquivalent:@"y"];
    [histMenu addItemWithTitle:@"Reopen Closed Tab" action:@selector(reopenClosedTab:) keyEquivalent:@"T"];

    NSMenuItem *bmItem = [[NSMenuItem alloc] init]; bmItem.title = @"Bookmarks";
    [mainMenu addItem:bmItem];
    NSMenu *bmMenu = [[NSMenu alloc] initWithTitle:@"Bookmarks"]; bmItem.submenu = bmMenu;
    [bmMenu addItemWithTitle:@"Bookmark This Page" action:@selector(bookmarkPage:) keyEquivalent:@"d"];
    [bmMenu addItemWithTitle:@"Show or Hide Favorites Bar" action:@selector(toggleFavoritesBar:) keyEquivalent:@"B"];

    NSMenuItem *tabItem = [[NSMenuItem alloc] init]; tabItem.title = @"Tab";
    [mainMenu addItem:tabItem];
    NSMenu *tabMenu = [[NSMenu alloc] initWithTitle:@"Tab"]; tabItem.submenu = tabMenu;
    [tabMenu addItemWithTitle:@"Show Next Tab" action:@selector(selectNextTab:) keyEquivalent:@"}"];
    [tabMenu addItemWithTitle:@"Show Previous Tab" action:@selector(selectPreviousTab:) keyEquivalent:@"{"];
    [tabMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *pin = [tabMenu addItemWithTitle:@"Pin or Unpin Tab" action:@selector(togglePinActiveTab:) keyEquivalent:@"p"];
    pin.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    [tabMenu addItem:[NSMenuItem separatorItem]];
    for (NSInteger n = 1; n <= 9; n++) {
        NSMenuItem *it = [tabMenu addItemWithTitle:n == 9 ? @"Last Tab" : [NSString stringWithFormat:@"Go to Tab %ld", (long)n]
                                            action:@selector(selectTabByNumber:) keyEquivalent:[NSString stringWithFormat:@"%ld", (long)n]];
        it.tag = n;
    }

    NSMenuItem *winItem = [[NSMenuItem alloc] init]; winItem.title = @"Window";
    [mainMenu addItem:winItem];
    NSMenu *winMenu = [[NSMenu alloc] initWithTitle:@"Window"]; winItem.submenu = winMenu;
    [winMenu addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    [winMenu addItemWithTitle:@"Bring All to Front" action:@selector(arrangeInFront:) keyEquivalent:@""];

    NSMenuItem *helpItem = [[NSMenuItem alloc] init]; helpItem.title = @"Help";
    [mainMenu addItem:helpItem];
    NSMenu *helpMenu = [[NSMenu alloc] initWithTitle:@"Help"]; helpItem.submenu = helpMenu;
    [helpMenu addItemWithTitle:@"Keyboard Shortcuts" action:@selector(showShortcutsPage:) keyEquivalent:@"/"];
    [helpMenu addItem:[NSMenuItem separatorItem]];
    [helpMenu addItemWithTitle:@"Send Feedback…" action:@selector(showFeedbackSheet:) keyEquivalent:@""];
    NSApp.helpMenu = helpMenu;

    NSApp.mainMenu = mainMenu;
}

#pragma mark - Menu actions
- (void)newWindow:(id)sender {
    NSString *home = SaturnSettings.shared.currentEngineInfo.homeURL;
    if (!home.length) home = @"https://www.google.com";
    [self createWindowWithURL:[NSURL URLWithString:home]];
}
- (void)newTab:(id)sender {
    NSString *home = SaturnSettings.shared.currentEngineInfo.homeURL;
    if (!home.length) home = @"https://www.google.com";
    NSURL *u = [NSURL URLWithString:home];
    SaturnWindow *w = (SaturnWindow *)NSApp.keyWindow;
    if ([w isKindOfClass:[SaturnWindow class]]) {
        [w createNewTabWithURL:u];
    } else if (self.windows.count > 0) {
        SaturnWindow *last = self.windows.lastObject;
        [last createNewTabWithURL:u];
        [last makeKeyAndOrderFront:nil];
    } else {
        [self createWindowWithURL:u];
    }
}
- (void)openSetup:(id)sender {
    [[SetupWindow shared] showSetupWithCompletion:^(SaturnSearchEngine selectedEngine) {
        (void)selectedEngine;
        NSLog(@"[saturn] Setup updated");
    }];
}
- (void)openSettings:(id)sender {
    SaturnWindow *w = (SaturnWindow *)NSApp.keyWindow;
    if (w) [[SettingsWindow shared] showForWindow:w];
    else [[SettingsWindow shared] showStandalone];
}
- (void)closeTab:(id)sender {
    SaturnWindow *w = (SaturnWindow *)NSApp.keyWindow;
    if ([w isKindOfClass:[SaturnWindow class]] && w.activeTab) {
        [w closeTabView:w.activeTab];
    }
}
- (void)closeWindow:(id)sender { [NSApp.keyWindow close]; }
- (void)checkForUpdates:(id)sender {
    (void)sender;
    [[SaturnUpdater shared] checkNowWithCompletion:^(BOOL available, NSError *error) {
        SaturnWindow *w = (SaturnWindow *)NSApp.keyWindow;
        if (available && [w isKindOfClass:[SaturnWindow class]]) { [w showUpdatePopover:nil]; return; }
        NSAlert *al = [[NSAlert alloc] init];
        if (error) { al.messageText = @"Couldn't check for updates"; al.informativeText = error.localizedDescription; }
        else { al.messageText = @"Saturn is up to date"; al.informativeText = [NSString stringWithFormat:@"Version %@ is the latest.", [SaturnUpdater shared].currentVersion]; }
        [al addButtonWithTitle:@"OK"];
        [al runModal];
    }];
}
- (void)resetSitePermissions:(id)sender {
    (void)sender;
    NSAlert *al = [[NSAlert alloc] init];
    al.messageText = @"Reset site permissions?";
    al.informativeText = @"Sites you allowed or blocked from using the camera and microphone will ask again.";
    [al addButtonWithTitle:@"Reset"];
    [al addButtonWithTitle:@"Cancel"];
    if ([al runModal] == NSAlertFirstButtonReturn) [SaturnPermissions resetAll];
}
- (void)reloadView:(id)sender { SaturnWindow *w = (SaturnWindow *)NSApp.keyWindow; [w.webView reload]; }
- (void)backView:(id)sender { SaturnWindow *w = (SaturnWindow *)NSApp.keyWindow; if (w.webView.canGoBack) [w.webView goBack]; }
- (void)forwardView:(id)sender { SaturnWindow *w = (SaturnWindow *)NSApp.keyWindow; if (w.webView.canGoForward) [w.webView goForward]; }
- (void)focusAddress:(id)sender { SaturnWindow *w = (SaturnWindow *)NSApp.keyWindow; [w makeFirstResponder:w.addressBar]; }
- (void)actualSize:(id)sender { SaturnWindow *w = (SaturnWindow *)NSApp.keyWindow; w.webView.magnification = 1.0; }
- (void)zoomIn:(id)sender { SaturnWindow *w = (SaturnWindow *)NSApp.keyWindow; w.webView.magnification *= 1.12; }
- (void)zoomOut:(id)sender { SaturnWindow *w = (SaturnWindow *)NSApp.keyWindow; w.webView.magnification /= 1.12; }

@end
