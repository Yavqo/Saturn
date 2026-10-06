#pragma once
#import <Cocoa/Cocoa.h>

// Simple auth sheet / window for Saturn
@interface AuthWindow : NSWindow <NSWindowDelegate>

+ (instancetype)shared;
- (void)showForWindow:(NSWindow *)parent; // shows as sheet if parent, else as window
- (void)showStandalone;

@end
