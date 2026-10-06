#pragma once
#import <Cocoa/Cocoa.h>

@interface SettingsWindow : NSWindow
+ (instancetype)shared;
- (void)showForWindow:(NSWindow *)parent;
- (void)showStandalone;
@end
