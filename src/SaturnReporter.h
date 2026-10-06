#pragma once
#import <Foundation/Foundation.h>

// Sends user feedback and crash reports to Saturn's Supabase project (insert-only tables, see
// supabase/feedback_and_crash_reports.sql) and finds new crash logs written by macOS.
@interface SaturnReporter : NSObject
+ (instancetype)shared;

+ (NSString *)appVersion;
+ (NSString *)osVersion;
+ (NSString *)deviceModel;

// kind: "bug", "idea" or "other". Completion runs on the main thread; error is nil on success.
- (void)submitFeedbackKind:(NSString *)kind message:(NSString *)message email:(NSString *)email
        includeDiagnostics:(BOOL)diagnostics completion:(void (^)(NSError *error))completion;

// The newest Saturn crash log macOS wrote since the last one was handled, or nil.
// Keys: summary, exception, details (redacted, no browsing data), crashedAt (NSDate), appVersion, osVersion, mtime (NSNumber).
- (NSDictionary *)pendingCrashReport;
- (void)markCrashHandled:(NSDictionary *)crash;
- (void)submitCrash:(NSDictionary *)crash note:(NSString *)note includeDetails:(BOOL)includeDetails completion:(void (^)(NSError *error))completion;

// Exposed for tests
+ (NSDictionary *)parseCrashFileAtPath:(NSString *)path;
@end
