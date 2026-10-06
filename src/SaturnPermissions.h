#pragma once
#import <Foundation/Foundation.h>

// Remembered per-site choices for camera and microphone ("allow" / "block").
// Private windows keep their choices in memory only.
@interface SaturnPermissions : NSObject
+ (NSString *)originKeyForProtocol:(NSString *)protocol host:(NSString *)host port:(NSInteger)port;
+ (NSString *)decisionForOrigin:(NSString *)origin kind:(NSString *)kind privateMode:(BOOL)privateMode;   // nil = ask
+ (void)setDecision:(NSString *)decision forOrigin:(NSString *)origin kinds:(NSArray<NSString *> *)kinds privateMode:(BOOL)privateMode;
+ (void)resetAll;
@end
