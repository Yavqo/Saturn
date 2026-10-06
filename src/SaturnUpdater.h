#pragma once
#import <Foundation/Foundation.h>

// Posted on the main thread whenever the update state or download progress changes.
extern NSNotificationName const SaturnUpdateStateChangedNotification;

typedef NS_ENUM(NSInteger, SaturnUpdateState) {
    SaturnUpdateStateIdle = 0,       // nothing newer known
    SaturnUpdateStateChecking,
    SaturnUpdateStateAvailable,      // a newer release exists
    SaturnUpdateStateDownloading,
    SaturnUpdateStateInstalling,     // unpacked and verified; swapping the app and restarting
    SaturnUpdateStateFailed,         // errorText says why; the update is still available to retry
};

// Self-updater: checks the latest GitHub release of Yavqo/Saturn, downloads its .zip,
// verifies it, replaces the running app and relaunches.
@interface SaturnUpdater : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) SaturnUpdateState state;
@property (nonatomic, readonly) NSString *currentVersion;
@property (nonatomic, readonly) NSString *availableVersion;
@property (nonatomic, readonly) NSString *releaseNotes;
@property (nonatomic, readonly) NSString *releasePageURL;
@property (nonatomic, readonly) NSString *errorText;
@property (nonatomic, readonly) double progress;            // 0...1 while downloading
@property (nonatomic, readonly) BOOL updateIsWaiting;       // available, downloading, installing or failed-with-update
- (void)startAutomaticChecks;                               // first check shortly after launch, then every 6 hours
- (void)checkNowWithCompletion:(void (^)(BOOL updateAvailable, NSError *error))completion;
- (void)installUpdate;
@end
