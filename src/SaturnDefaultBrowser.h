#pragma once
#import <Foundation/Foundation.h>

// Whether Saturn handles web links system-wide, and asking macOS to make it so.
@interface SaturnDefaultBrowser : NSObject
+ (BOOL)isDefault;
+ (NSString *)currentDefaultName;                 // e.g. "Safari", or nil if unknown
// Shows macOS's own confirmation dialog. Completion runs on the main thread.
+ (void)makeDefaultWithCompletion:(void (^)(BOOL isNowDefault, NSError *error))completion;
// First-run offer: at most twice, never once Saturn is already the default.
+ (BOOL)shouldOffer;
+ (void)recordOfferShown;
@end
