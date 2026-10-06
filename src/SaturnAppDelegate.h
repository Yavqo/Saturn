#pragma once
#import <Cocoa/Cocoa.h>
@class SaturnWindow;

@interface SaturnAppDelegate : NSObject <NSApplicationDelegate, NSMenuItemValidation>
@property (nonatomic, strong) NSMutableArray<SaturnWindow *> *windows;
@property (nonatomic, copy) NSString *initialURLString;
@property (nonatomic, strong) NSMutableArray<NSURL *> *pendingURLs;   // links that arrived before the first window existed
@property (nonatomic, assign) BOOL launched;
@property (nonatomic, assign) BOOL startPrivate;   // --private: open a private window at launch
- (void)createWindowWithURL:(NSURL *)url;
- (void)resetBrowserAndRestartSetup;   // wipes all local data and settings, closes windows, shows first-run setup
- (void)createWindowWithURL:(NSURL *)url privateMode:(BOOL)privateMode;
@end
