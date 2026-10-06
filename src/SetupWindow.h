#pragma once
#import <Cocoa/Cocoa.h>
#import "Settings.h"

@interface SetupWindow : NSWindowController

+ (instancetype)shared;
- (void)showSetupWithCompletion:(void(^)(SaturnSearchEngine selectedEngine))completion;
- (void)closeSetup;

@end
