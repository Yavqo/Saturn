#import "SaturnDownloads.h"

NSNotificationName const SaturnDownloadsChangedNotification = @"SaturnDownloadsChanged";

@implementation SaturnDownloadItem
- (double)fraction {
    if (self.state == SaturnDownloadStateDone) return 1;
    if (self.bytesTotal <= 0) return -1;
    return MIN(1.0, MAX(0.0, (double)self.bytesReceived / (double)self.bytesTotal));
}
@end

@implementation SaturnDownloads {
    NSMutableArray<SaturnDownloadItem *> *_items;
    NSMapTable<WKDownload *, SaturnDownloadItem *> *_byDownload;
    NSMutableSet<SaturnDownloadItem *> *_userCancelled;
    BOOL _notifyScheduled;
}

+ (instancetype)shared {
    static SaturnDownloads *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[SaturnDownloads alloc] init]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _items = [NSMutableArray array];
        _byDownload = [NSMapTable strongToStrongObjectsMapTable];
        _userCancelled = [NSMutableSet set];
    }
    return self;
}

- (NSArray<SaturnDownloadItem *> *)items { return [_items copy]; }

- (NSInteger)activeCount {
    NSInteger n = 0;
    for (SaturnDownloadItem *i in _items) if (i.state == SaturnDownloadStateActive) n++;
    return n;
}

- (double)overallFraction {
    int64_t got = 0, total = 0;
    for (SaturnDownloadItem *i in _items) {
        if (i.state != SaturnDownloadStateActive) continue;
        if (i.bytesTotal <= 0) return -1;
        got += i.bytesReceived; total += i.bytesTotal;
    }
    return total > 0 ? (double)got / (double)total : -1;
}

// Coalesce bursts of progress callbacks into at most ~8 notifications a second.
- (void)changed {
    if (_notifyScheduled) return;
    _notifyScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self->_notifyScheduled = NO;
        [[NSNotificationCenter defaultCenter] postNotificationName:SaturnDownloadsChangedNotification object:self];
    });
}

- (void)adopt:(WKDownload *)download {
    SaturnDownloadItem *item = [[SaturnDownloadItem alloc] init];
    item.download = download;
    item.sourceURL = download.originalRequest.URL;
    item.filename = item.sourceURL.lastPathComponent.length ? item.sourceURL.lastPathComponent : @"Download";
    item.state = SaturnDownloadStateActive;
    [_items insertObject:item atIndex:0];
    [_byDownload setObject:item forKey:download];
    download.delegate = self;
    [download.progress addObserver:self forKeyPath:@"fractionCompleted" options:0 context:(__bridge void *)item];
    [self changed];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    (void)keyPath; (void)change;
    SaturnDownloadItem *item = (__bridge SaturnDownloadItem *)context;
    NSProgress *p = (NSProgress *)object;
    item.bytesReceived = p.completedUnitCount;
    item.bytesTotal = p.totalUnitCount;
    dispatch_async(dispatch_get_main_queue(), ^{ [self changed]; });
}

- (void)stopObserving:(SaturnDownloadItem *)item {
    @try { [item.download.progress removeObserver:self forKeyPath:@"fractionCompleted" context:(__bridge void *)item]; } @catch (NSException *e) {}
}

- (NSURL *)uniqueDestinationForName:(NSString *)name {
    NSString *dir = NSSearchPathForDirectoriesInDomains(NSDownloadsDirectory, NSUserDomainMask, YES).firstObject ?: NSHomeDirectory();
    NSString *clean = [[name lastPathComponent] stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    if (!clean.length) clean = @"Download";
    NSString *base = [clean stringByDeletingPathExtension], *ext = clean.pathExtension;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *path = [dir stringByAppendingPathComponent:clean];
    for (NSInteger n = 1; [fm fileExistsAtPath:path]; n++) {
        NSString *candidate = ext.length ? [NSString stringWithFormat:@"%@ (%ld).%@", base, (long)n, ext] : [NSString stringWithFormat:@"%@ (%ld)", base, (long)n];
        path = [dir stringByAppendingPathComponent:candidate];
    }
    return [NSURL fileURLWithPath:path];
}

#pragma mark WKDownloadDelegate

- (void)download:(WKDownload *)download decideDestinationUsingResponse:(NSURLResponse *)response suggestedFilename:(NSString *)suggestedFilename completionHandler:(void (^)(NSURL *))completionHandler {
    SaturnDownloadItem *item = [_byDownload objectForKey:download];
    NSURL *dest = [self uniqueDestinationForName:suggestedFilename];
    if (item) {
        item.destination = dest;
        item.filename = dest.lastPathComponent;
        if (response.expectedContentLength > 0) item.bytesTotal = response.expectedContentLength;
    }
    completionHandler(dest);
    [self changed];
}

- (void)download:(WKDownload *)download willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request decisionHandler:(void (^)(WKDownloadRedirectPolicy))decisionHandler {
    (void)download; (void)response; (void)request;
    decisionHandler(WKDownloadRedirectPolicyAllow);
}

- (void)downloadDidFinish:(WKDownload *)download {
    SaturnDownloadItem *item = [_byDownload objectForKey:download];
    if (!item) return;
    [self stopObserving:item];
    item.state = SaturnDownloadStateDone;
    if (item.bytesTotal <= 0) item.bytesTotal = item.bytesReceived;
    item.bytesReceived = item.bytesTotal;
    item.download = nil;
    [_byDownload removeObjectForKey:download];
    if (item.destination.path) {
        // Lets the Downloads stack in the Dock bounce, like Safari does.
        [[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"com.apple.DownloadFileFinished" object:item.destination.path];
    }
    [self changed];
}

- (void)download:(WKDownload *)download didFailWithError:(NSError *)error resumeData:(NSData *)resumeData {
    (void)resumeData;
    SaturnDownloadItem *item = [_byDownload objectForKey:download];
    if (!item) return;
    [self stopObserving:item];
    BOOL cancelled = [_userCancelled containsObject:item] || error.code == NSURLErrorCancelled;
    item.state = cancelled ? SaturnDownloadStateCancelled : SaturnDownloadStateFailed;
    item.errorText = cancelled ? nil : error.localizedDescription;
    item.download = nil;
    [_userCancelled removeObject:item];
    [_byDownload removeObjectForKey:download];
    if (item.destination.path) [[NSFileManager defaultManager] removeItemAtURL:item.destination error:nil];  // drop the partial file
    [self changed];
}

#pragma mark Actions

- (void)cancel:(SaturnDownloadItem *)item {
    if (item.state != SaturnDownloadStateActive) return;
    [_userCancelled addObject:item];
    [item.download cancel:^(NSData *resumeData) { (void)resumeData; }];
}

- (void)open:(SaturnDownloadItem *)item {
    if (item.state == SaturnDownloadStateDone && item.destination) [[NSWorkspace sharedWorkspace] openURL:item.destination];
}

- (void)reveal:(SaturnDownloadItem *)item {
    if (item.destination) [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[item.destination]];
}

- (void)remove:(SaturnDownloadItem *)item {
    if (item.state == SaturnDownloadStateActive) [self cancel:item];
    [_items removeObject:item];
    [self changed];
}

- (void)clearFinished {
    NSMutableArray *keep = [NSMutableArray array];
    for (SaturnDownloadItem *i in _items) if (i.state == SaturnDownloadStateActive) [keep addObject:i];
    _items = keep;
    [self changed];
}

@end
