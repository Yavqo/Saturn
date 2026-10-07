#import "SaturnUpdater.h"
#import <Cocoa/Cocoa.h>
#import <CommonCrypto/CommonDigest.h>

NSNotificationName const SaturnUpdateStateChangedNotification = @"SaturnUpdateStateChanged";

static NSString *const kDefaultFeed = @"https://api.github.com/repos/Yavqo/Saturn/releases/latest";

// "v1.2.3-beta" -> @[1,2,3]
static NSArray<NSNumber *> *VersionParts(NSString *v) {
    NSString *s = [v hasPrefix:@"v"] || [v hasPrefix:@"V"] ? [v substringFromIndex:1] : v;
    s = [s componentsSeparatedByString:@"-"].firstObject ?: s;
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *p in [s componentsSeparatedByString:@"."]) [parts addObject:@(p.integerValue)];
    return parts;
}
static BOOL VersionIsNewer(NSString *candidate, NSString *current) {
    NSArray *a = VersionParts(candidate), *b = VersionParts(current);
    for (NSUInteger i = 0; i < MAX(a.count, b.count); i++) {
        NSInteger x = i < a.count ? [a[i] integerValue] : 0, y = i < b.count ? [b[i] integerValue] : 0;
        if (x != y) return x > y;
    }
    return NO;
}

@interface SaturnUpdater () <NSURLSessionDownloadDelegate>
@end

@implementation SaturnUpdater {
    SaturnUpdateState _state;
    NSString *_availableVersion, *_releaseNotes, *_releasePageURL, *_errorText, *_assetName, *_assetDigest;
    NSURL *_assetURL;
    double _progress;
    NSURLSession *_session;
    NSTimer *_timer;
}

+ (instancetype)shared {
    static SaturnUpdater *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[SaturnUpdater alloc] init]; });
    return s;
}

- (SaturnUpdateState)state { return _state; }
- (NSString *)availableVersion { return _availableVersion; }
- (NSString *)releaseNotes { return _releaseNotes; }
- (NSString *)releasePageURL { return _releasePageURL; }
- (NSString *)errorText { return _errorText; }
- (double)progress { return _progress; }
- (NSString *)currentVersion { return [NSBundle mainBundle].infoDictionary[@"CFBundleShortVersionString"] ?: @"0.0.0"; }
- (BOOL)updateIsWaiting { return _availableVersion.length && _assetURL && _state != SaturnUpdateStateIdle && _state != SaturnUpdateStateChecking; }

- (void)setState:(SaturnUpdateState)state {
    _state = state;
    [[NSNotificationCenter defaultCenter] postNotificationName:SaturnUpdateStateChangedNotification object:self];
}

+ (NSString *)workDir {
    NSString *base = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    NSString *dir = [base stringByAppendingPathComponent:@"com.saturn.browser/update"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

#pragma mark Checking

- (void)startAutomaticChecks {
    // Clear leftovers from the last update
    NSString *dir = [SaturnUpdater workDir];
    for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil]) {
        if (![f isEqualToString:@"update.log"]) [[NSFileManager defaultManager] removeItemAtPath:[dir stringByAppendingPathComponent:f] error:nil];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self checkNowWithCompletion:nil]; });
    _timer = [NSTimer scheduledTimerWithTimeInterval:6 * 3600 repeats:YES block:^(NSTimer *t) { (void)t; [self checkNowWithCompletion:nil]; }];
}

- (void)checkNowWithCompletion:(void (^)(BOOL, NSError *))completion {
    if (_state == SaturnUpdateStateDownloading || _state == SaturnUpdateStateInstalling) { if (completion) completion(YES, nil); return; }
    NSString *feed = NSProcessInfo.processInfo.environment[@"SATURN_UPDATE_FEED"] ?: kDefaultFeed;   // override is for testing
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:feed]];
    req.timeoutInterval = 20;
    req.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    [req setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [req setValue:[NSString stringWithFormat:@"Saturn/%@", self.currentVersion] forHTTPHeaderField:@"User-Agent"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSInteger code = [(NSHTTPURLResponse *)resp statusCode];
        NSDictionary *rel = nil;
        NSError *outErr = err;
        if (!err) {
            id j = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            if (code == 404) { /* no releases yet: not an error */ }
            else if (code < 200 || code >= 300 || ![j isKindOfClass:[NSDictionary class]])
                outErr = [NSError errorWithDomain:@"SaturnUpdater" code:code userInfo:@{NSLocalizedDescriptionKey: @"Could not reach the update server."}];
            else rel = j;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL available = [self applyRelease:rel];
            if (completion) completion(available, outErr);
        });
    }] resume];
}

- (BOOL)applyRelease:(NSDictionary *)rel {
    if (_state == SaturnUpdateStateDownloading || _state == SaturnUpdateStateInstalling) return YES;
    NSString *tag = rel[@"tag_name"];
    if (!tag.length || [rel[@"draft"] boolValue] || [rel[@"prerelease"] boolValue] || !VersionIsNewer(tag, self.currentVersion)) {
        if (_state != SaturnUpdateStateIdle) { _availableVersion = nil; _assetURL = nil; [self setState:SaturnUpdateStateIdle]; }
        return NO;
    }
    // Pick the app archive from the release assets
    NSDictionary *chosen = nil;
    for (NSDictionary *a in rel[@"assets"]) {
        NSString *n = [a[@"name"] lowercaseString];
        if ([n hasSuffix:@".zip"] && [n containsString:@"saturn"]) { chosen = a; break; }
        if ([n hasSuffix:@".zip"] && !chosen) chosen = a;
    }
    NSURL *url = chosen ? [NSURL URLWithString:chosen[@"browser_download_url"]] : nil;
    BOOL testFeed = NSProcessInfo.processInfo.environment[@"SATURN_UPDATE_FEED"] != nil;   // plain http only for local testing
    if (!url || !([url.scheme isEqualToString:@"https"] || (testFeed && [url.scheme isEqualToString:@"http"]))) return NO;
    _availableVersion = [tag hasPrefix:@"v"] ? [tag substringFromIndex:1] : tag;
    _releaseNotes = [rel[@"body"] isKindOfClass:[NSString class]] ? rel[@"body"] : @"";
    _releasePageURL = rel[@"html_url"];
    _assetURL = url;
    _assetName = chosen[@"name"];
    _assetDigest = [chosen[@"digest"] isKindOfClass:[NSString class]] ? chosen[@"digest"] : nil;   // "sha256:…" when GitHub provides it
    _errorText = nil;
    [self setState:SaturnUpdateStateAvailable];
    return YES;
}

#pragma mark Downloading + installing

// Where the new build goes. Normally the app's own location. When Saturn runs from a disk image or from a
// quarantined (translocated) path that location is read-only, so the update installs into Applications instead.
- (NSString *)installDestination {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *bundlePath = [NSBundle mainBundle].bundlePath;
    BOOL readOnlyPlace = [bundlePath containsString:@"/AppTranslocation/"] || [bundlePath hasPrefix:@"/Volumes/"];
    if (!readOnlyPlace && [fm isWritableFileAtPath:[bundlePath stringByDeletingLastPathComponent]]) return bundlePath;
    if ([fm isWritableFileAtPath:@"/Applications"]) return @"/Applications/Saturn.app";
    NSString *home = [NSHomeDirectory() stringByAppendingPathComponent:@"Applications"];
    [fm createDirectoryAtPath:home withIntermediateDirectories:YES attributes:nil error:nil];
    if ([fm isWritableFileAtPath:home]) return [home stringByAppendingPathComponent:@"Saturn.app"];
    return nil;
}

- (void)installUpdate {
    if (!_assetURL || _state == SaturnUpdateStateDownloading || _state == SaturnUpdateStateInstalling) return;
    if (![self installDestination]) {
        [self failWith:@"Saturn can't find a place to install the update. Drag Saturn into your Applications folder and try again."];
        return;
    }
    _progress = 0;
    _errorText = nil;
    [self setState:SaturnUpdateStateDownloading];
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    _session = [NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:[NSOperationQueue mainQueue]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:_assetURL];
    [req setValue:[NSString stringWithFormat:@"Saturn/%@", self.currentVersion] forHTTPHeaderField:@"User-Agent"];
    [[_session downloadTaskWithRequest:req] resume];
}

- (void)failWith:(NSString *)text {
    _errorText = text;
    [self setState:SaturnUpdateStateFailed];
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didWriteData:(int64_t)written totalBytesWritten:(int64_t)total totalBytesExpectedToWrite:(int64_t)expected {
    (void)session; (void)task; (void)written;
    _progress = expected > 0 ? (double)total / (double)expected : 0;
    [[NSNotificationCenter defaultCenter] postNotificationName:SaturnUpdateStateChangedNotification object:self];
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didFinishDownloadingToURL:(NSURL *)location {
    (void)session;
    NSInteger code = [(NSHTTPURLResponse *)task.response statusCode];
    if (code && (code < 200 || code >= 300)) { [self failWith:[NSString stringWithFormat:@"The download failed (HTTP %ld).", (long)code]]; return; }
    // The temporary file disappears when this method returns, so move it now.
    NSString *dir = [[SaturnUpdater workDir] stringByAppendingPathComponent:_availableVersion ?: @"new"];
    [[NSFileManager defaultManager] removeItemAtPath:dir error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *zip = [dir stringByAppendingPathComponent:@"Saturn.zip"];
    NSError *mv = nil;
    if (![[NSFileManager defaultManager] moveItemAtURL:location toURL:[NSURL fileURLWithPath:zip] error:&mv]) { [self failWith:@"Could not save the download."]; return; }

    NSString *digest = _assetDigest, *version = _availableVersion;
    [self setState:SaturnUpdateStateInstalling];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *problem = nil;
        NSString *newApp = [self unpackAndVerifyZip:zip inDir:dir digest:digest version:version problem:&problem];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!newApp) { [self failWith:problem ?: @"The update could not be verified."]; return; }
            [self launchSwapScriptWithNewApp:newApp inDir:dir];
        });
    });
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    (void)session; (void)task;
    if (error && _state == SaturnUpdateStateDownloading) [self failWith:[NSString stringWithFormat:@"The download failed: %@", error.localizedDescription]];
}

static NSString *SHA256OfFile(NSString *path) {
    NSFileHandle *h = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!h) return nil;
    CC_SHA256_CTX ctx; CC_SHA256_Init(&ctx);
    for (;;) {
        @autoreleasepool {
            NSData *chunk = [h readDataOfLength:1 << 20];
            if (!chunk.length) break;
            CC_SHA256_Update(&ctx, chunk.bytes, (CC_LONG)chunk.length);
        }
    }
    unsigned char out[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(out, &ctx);
    NSMutableString *hex = [NSMutableString string];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", out[i]];
    return hex;
}

static int RunTool(NSString *path, NSArray<NSString *> *args) {
    NSTask *t = [[NSTask alloc] init];
    t.executableURL = [NSURL fileURLWithPath:path];
    t.arguments = args;
    t.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    t.standardError = [NSFileHandle fileHandleWithNullDevice];
    NSError *e = nil;
    if (![t launchAndReturnError:&e]) return -1;
    [t waitUntilExit];
    return t.terminationStatus;
}

// Background thread. Returns the path of the unpacked, verified .app (or nil with a reason).
- (NSString *)unpackAndVerifyZip:(NSString *)zip inDir:(NSString *)dir digest:(NSString *)digest version:(NSString *)version problem:(NSString **)problem {
    if ([digest hasPrefix:@"sha256:"]) {
        NSString *want = [[digest substringFromIndex:7] lowercaseString], *got = SHA256OfFile(zip);
        if (![want isEqualToString:got]) { *problem = @"The download is corrupted (checksum mismatch), so it was not installed."; return nil; }
    }
    NSString *out = [dir stringByAppendingPathComponent:@"unpacked"];
    if (RunTool(@"/usr/bin/ditto", @[@"-x", @"-k", zip, out]) != 0) { *problem = @"The update archive could not be unpacked."; return nil; }
    NSString *app = nil;
    for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:out error:nil]) if ([f hasSuffix:@".app"]) { app = [out stringByAppendingPathComponent:f]; break; }
    if (!app) { *problem = @"The update archive doesn't contain the app."; return nil; }

    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[app stringByAppendingPathComponent:@"Contents/Info.plist"]];
    NSString *myID = [NSBundle mainBundle].bundleIdentifier;
    if (![info[@"CFBundleIdentifier"] isEqualToString:myID]) { *problem = @"The update is not a Saturn build, so it was not installed."; return nil; }
    if (!VersionIsNewer(info[@"CFBundleShortVersionString"] ?: @"0", self.currentVersion)) { *problem = @"The downloaded build is not newer than this one, so it was not installed."; return nil; }
    (void)version;
    if (RunTool(@"/usr/bin/codesign", @[@"--verify", @"--deep", app]) != 0) { *problem = @"The update's signature is broken, so it was not installed."; return nil; }
    return app;
}

// The running app cannot replace itself, so a small script waits for it to quit, swaps the bundle and reopens it.
- (void)launchSwapScriptWithNewApp:(NSString *)newApp inDir:(NSString *)dir {
    NSString *dest = [self installDestination];
    if (!dest) { [self failWith:@"Saturn can't find a place to install the update. Drag Saturn into your Applications folder and try again."]; return; }
    NSString *log = [[SaturnUpdater workDir] stringByAppendingPathComponent:@"update.log"];
    NSString *script = @"#!/bin/sh\n"
        "# args: pid new-app destination\n"
        "PID=\"$1\"; NEW=\"$2\"; DEST=\"$3\"; OLD=\"$DEST.previous\"\n"
        "echo \"$(date) updating $DEST from $NEW\"\n"
        "i=0; while kill -0 \"$PID\" 2>/dev/null && [ $i -lt 100 ]; do sleep 0.3; i=$((i+1)); done\n"
        "rm -rf \"$OLD\"\n"
        "if [ ! -e \"$DEST\" ] || mv \"$DEST\" \"$OLD\"; then\n"
        "  if /usr/bin/ditto \"$NEW\" \"$DEST\"; then\n"
        "    /usr/bin/xattr -dr com.apple.quarantine \"$DEST\" 2>/dev/null\n"
        "    rm -rf \"$OLD\"\n"
        "    echo \"updated\"\n"
        "  else\n"
        "    echo \"copy failed, restoring\"; rm -rf \"$DEST\"; [ -e \"$OLD\" ] && mv \"$OLD\" \"$DEST\"\n"
        "  fi\n"
        "else\n"
        "  echo \"could not move the old app\"\n"
        "fi\n"
        "/usr/bin/open \"$DEST\"\n";
    NSString *path = [dir stringByAppendingPathComponent:@"apply-update.sh"];
    NSError *e = nil;
    if (![script writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&e]) { [self failWith:@"Could not prepare the update."]; return; }
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0755} ofItemAtPath:path error:nil];

    NSTask *t = [[NSTask alloc] init];
    t.executableURL = [NSURL fileURLWithPath:@"/bin/sh"];
    // Detached, so it keeps running after Saturn quits
    t.arguments = @[@"-c", @"nohup /bin/sh \"$0\" \"$1\" \"$2\" \"$3\" >> \"$4\" 2>&1 &", path,
                    [NSString stringWithFormat:@"%d", NSProcessInfo.processInfo.processIdentifier], newApp, dest, log];
    t.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    t.standardError = [NSFileHandle fileHandleWithNullDevice];
    if (![t launchAndReturnError:&e]) { [self failWith:@"Could not start the installer."]; return; }
    [NSApp terminate:nil];   // session is saved on quit and restored by the new version
}

@end
