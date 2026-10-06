#pragma once
#import <Foundation/Foundation.h>

// Saves the open windows (tabs, pinned state, groups, active tab) so they come back after a relaunch.
@interface SaturnSession : NSObject
+ (instancetype)shared;
- (void)scheduleSave;                 // debounced; call after any tab change
- (void)saveNow;
- (NSArray<NSDictionary *> *)savedWindows;
@end
