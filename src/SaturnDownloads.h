#pragma once
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

typedef NS_ENUM(NSInteger, SaturnDownloadState) {
    SaturnDownloadStateActive = 0,
    SaturnDownloadStateDone,
    SaturnDownloadStateFailed,
    SaturnDownloadStateCancelled,
};

// Posted on the main thread whenever a download is added, changes state, makes progress or is removed.
extern NSNotificationName const SaturnDownloadsChangedNotification;

@interface SaturnDownloadItem : NSObject
@property (nonatomic, copy) NSString *filename;
@property (nonatomic, strong) NSURL *sourceURL;
@property (nonatomic, strong) NSURL *destination;
@property (nonatomic, assign) SaturnDownloadState state;
@property (nonatomic, copy) NSString *errorText;
@property (nonatomic, assign) int64_t bytesReceived;
@property (nonatomic, assign) int64_t bytesTotal;      // <= 0 when unknown
@property (nonatomic, readonly) double fraction;        // 0...1, or -1 when unknown
@property (nonatomic, strong) WKDownload *download;
@end

@interface SaturnDownloads : NSObject <WKDownloadDelegate>
+ (instancetype)shared;
@property (nonatomic, readonly) NSArray<SaturnDownloadItem *> *items;   // newest first
@property (nonatomic, readonly) NSInteger activeCount;
@property (nonatomic, readonly) double overallFraction;                 // across active items, -1 if none/unknown
- (void)adopt:(WKDownload *)download;
- (void)cancel:(SaturnDownloadItem *)item;
- (void)open:(SaturnDownloadItem *)item;
- (void)reveal:(SaturnDownloadItem *)item;
- (void)remove:(SaturnDownloadItem *)item;
- (void)clearFinished;
@end
