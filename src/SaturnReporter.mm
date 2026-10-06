#import "SaturnReporter.h"
#import "Supabase/SupabaseClient.h"
#include <sys/sysctl.h>

static NSString *const kCrashBaselineKey = @"saturn.crash.baseline";

// Remove anything that identifies the person: home folder and user name in file paths.
static NSString *Redact(NSString *s) {
    if (!s.length) return s;
    NSString *home = NSHomeDirectory();
    if (home.length > 1) s = [s stringByReplacingOccurrencesOfString:home withString:@"~"];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"/Users/[^/\\s\"']+" options:0 error:nil];
    return [re stringByReplacingMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@"/Users/<user>"];
}

static NSString *Clip(NSString *s, NSUInteger max) {
    if (!s) return nil;
    return s.length > max ? [s substringToIndex:max] : s;
}

@implementation SaturnReporter

+ (instancetype)shared {
    static SaturnReporter *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[SaturnReporter alloc] init]; });
    return s;
}

+ (NSString *)appVersion {
    NSDictionary *i = [NSBundle mainBundle].infoDictionary;
    return i[@"CFBundleShortVersionString"] ?: @"unknown";
}
+ (NSString *)osVersion { return [NSString stringWithFormat:@"macOS %@", NSProcessInfo.processInfo.operatingSystemVersionString]; }
+ (NSString *)deviceModel {
    size_t len = 0;
    sysctlbyname("hw.model", NULL, &len, NULL, 0);
    if (!len) return @"Mac";
    char *buf = (char *)malloc(len);
    sysctlbyname("hw.model", buf, &len, NULL, 0);
    NSString *m = [NSString stringWithUTF8String:buf];
    free(buf);
    return m ?: @"Mac";
}

#pragma mark Sending

- (void)postRow:(NSDictionary *)row table:(NSString *)table completion:(void (^)(NSError *))completion {
    NSDictionary *env = NSProcessInfo.processInfo.environment;
    SupabaseClient *sb = [SupabaseClient shared];
    NSString *base = env[@"SATURN_REPORT_ENDPOINT"] ?: (sb.supabaseURL.length ? [sb.supabaseURL stringByAppendingString:@"/rest/v1"] : nil);   // override is for testing
    NSString *key = env[@"SATURN_REPORT_KEY"] ?: sb.anonKey;
    if (!base.length || !key.length) {
        NSError *e = [NSError errorWithDomain:@"SaturnReporter" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Reporting isn't set up in this build."}];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(e); });
        return;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/%@", base, table]]];
    req.HTTPMethod = @"POST";
    req.timeoutInterval = 25;
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:row options:0 error:nil];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:key forHTTPHeaderField:@"apikey"];
    [req setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    [req setValue:@"return=minimal" forHTTPHeaderField:@"Prefer"];   // the tables are insert-only, so nothing can be read back
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSError *out = err;
        NSInteger code = [(NSHTTPURLResponse *)resp statusCode];
        if (!err && (code < 200 || code >= 300)) {
            id j = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            NSString *msg = [j isKindOfClass:[NSDictionary class]] ? (j[@"message"] ?: j[@"error"]) : nil;
            out = [NSError errorWithDomain:@"SaturnReporter" code:code userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"The server refused it (%ld)%@", (long)code, msg ? [@": " stringByAppendingString:msg] : @""]}];
        } else if (err) {
            out = [NSError errorWithDomain:@"SaturnReporter" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Couldn't reach the server. Check your connection and try again."}];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(out); });
    }] resume];
}

- (void)submitFeedbackKind:(NSString *)kind message:(NSString *)message email:(NSString *)email includeDiagnostics:(BOOL)diagnostics completion:(void (^)(NSError *))completion {
    NSString *msg = [message stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *mail = [email stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableDictionary *row = [@{@"kind": [@[@"bug", @"idea", @"other"] containsObject:kind] ? kind : @"other", @"message": Clip(msg, 5000)} mutableCopy];
    if (mail.length) row[@"email"] = Clip(mail, 200);
    NSString *uid = [SupabaseClient shared].currentUserId;
    if (uid.length) row[@"user_id"] = uid;
    if (diagnostics) {
        row[@"app_version"] = [SaturnReporter appVersion];
        row[@"os_version"] = [SaturnReporter osVersion];
        row[@"device"] = [SaturnReporter deviceModel];
    }
    [self postRow:row table:@"saturn_feedback" completion:completion];
}

- (void)submitCrash:(NSDictionary *)crash note:(NSString *)note includeDetails:(BOOL)includeDetails completion:(void (^)(NSError *))completion {
    NSMutableDictionary *row = [NSMutableDictionary dictionary];
    row[@"app_version"] = crash[@"appVersion"] ?: [SaturnReporter appVersion];
    row[@"os_version"] = crash[@"osVersion"] ?: [SaturnReporter osVersion];
    row[@"device"] = [SaturnReporter deviceModel];
    if (crash[@"summary"]) row[@"summary"] = Clip(crash[@"summary"], 2000);
    if (crash[@"exception"]) row[@"exception"] = Clip(crash[@"exception"], 400);
    NSDate *when = crash[@"crashedAt"];
    if (when) { NSISO8601DateFormatter *f = [[NSISO8601DateFormatter alloc] init]; row[@"crashed_at"] = [f stringFromDate:when]; }
    if (includeDetails && crash[@"details"]) row[@"details"] = Clip(crash[@"details"], 60000);
    NSString *n = [note stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (n.length) row[@"note"] = Clip(n, 3000);
    NSString *uid = [SupabaseClient shared].currentUserId;
    if (uid.length) row[@"user_id"] = uid;
    [self postRow:row table:@"saturn_crash_reports" completion:completion];
}

#pragma mark Crash logs

+ (NSString *)crashDir {
    return NSProcessInfo.processInfo.environment[@"SATURN_CRASH_DIR"] ?: [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/DiagnosticReports"];
}

// macOS writes .ips files ("saturn-2026-10-06-153000.ips"): a JSON header line, then a JSON body.
+ (NSDictionary *)parseCrashFileAtPath:(NSString *)path {
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!text.length) return nil;
    id header = nil, body = nil;
    NSRange nl = [text rangeOfString:@"\n"];
    if (nl.location != NSNotFound) {
        header = [NSJSONSerialization JSONObjectWithData:[[text substringToIndex:nl.location] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        body = [NSJSONSerialization JSONObjectWithData:[[text substringFromIndex:nl.location + 1] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    }
    if (![body isKindOfClass:[NSDictionary class]]) {   // single-document variant
        body = [NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        if (!header) header = body;
    }
    NSDictionary *h = [header isKindOfClass:[NSDictionary class]] ? header : @{};
    NSDictionary *b = [body isKindOfClass:[NSDictionary class]] ? body : @{};

    NSString *bundleID = h[@"bundleID"] ?: b[@"bundleID"];
    NSString *mine = [NSBundle mainBundle].bundleIdentifier;
    if (mine.length && bundleID.length && ![bundleID isEqualToString:mine]) return nil;   // some other app's report

    NSDictionary *exc = b[@"exception"] ?: @{};
    NSDictionary *term = b[@"termination"] ?: @{};
    NSArray *threads = b[@"threads"], *images = b[@"usedImages"];
    NSInteger ft = [b[@"faultingThread"] integerValue];
    NSArray *frames = (ft >= 0 && ft < (NSInteger)threads.count) ? threads[ft][@"frames"] : nil;

    NSMutableString *lines = [NSMutableString string];
    NSString *ver = h[@"app_version"] ?: b[@"app_version"] ?: [SaturnReporter appVersion];
    NSString *os = h[@"os_version"] ?: b[@"osVersion"][@"train"] ?: [SaturnReporter osVersion];
    [lines appendFormat:@"Saturn %@ on %@\n", ver, os];
    if (h[@"timestamp"]) [lines appendFormat:@"Time: %@\n", h[@"timestamp"]];
    if (exc.count) [lines appendFormat:@"Exception: %@ %@ %@\n", exc[@"type"] ?: @"", exc[@"signal"] ? [NSString stringWithFormat:@"(%@)", exc[@"signal"]] : @"", exc[@"subtype"] ?: @""];
    if (term.count) [lines appendFormat:@"Termination: %@ %@ %@\n", term[@"namespace"] ?: @"", term[@"indicator"] ?: @"", term[@"details"] ? [term[@"details"] componentsJoinedByString:@"; "] : @""];

    NSString *topImage = nil;
    if (frames.count) {
        [lines appendString:@"\nCrashed thread:\n"];
        for (NSInteger i = 0; i < (NSInteger)frames.count && i < 30; i++) {
            NSDictionary *f = frames[i];
            NSInteger idx = [f[@"imageIndex"] integerValue];
            NSString *img = (idx >= 0 && idx < (NSInteger)images.count) ? images[idx][@"name"] : @"?";
            if (i == 0) topImage = img;
            [lines appendFormat:@"%2ld  %@  %@ + %@\n", (long)i, img ?: @"?", f[@"symbol"] ?: @"(no symbol)", f[@"imageOffset"] ?: f[@"symbolLocation"] ?: @0];
        }
    }
    NSString *type = exc[@"type"] ?: term[@"indicator"] ?: @"Crash";
    NSString *sig = exc[@"signal"] ? [NSString stringWithFormat:@" (%@)", exc[@"signal"]] : @"";
    NSString *summary = [NSString stringWithFormat:@"%@%@%@", type, sig, topImage.length ? [@" in " stringByAppendingString:topImage] : @""];

    NSDate *when = nil;
    if ([h[@"timestamp"] isKindOfClass:[NSString class]]) {
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        df.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS Z";
        when = [df dateFromString:h[@"timestamp"]];
    }
    return @{@"summary": Redact(summary), @"exception": Redact([NSString stringWithFormat:@"%@%@", type, sig]),
             @"details": Redact(Clip(lines, 40000)), @"crashedAt": when ?: [NSDate date],
             @"appVersion": ver, @"osVersion": os};
}

- (NSDictionary *)pendingCrashReport {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    double baseline = [d doubleForKey:kCrashBaselineKey];
    if (baseline == 0) {   // first run with crash reporting: ignore anything that happened before
        [d setDouble:[NSDate date].timeIntervalSince1970 forKey:kCrashBaselineKey];
        return nil;
    }
    NSString *dir = [SaturnReporter crashDir];
    NSString *newest = nil; double newestTime = baseline;
    for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil]) {
        if (![f hasPrefix:@"saturn-"] || ![f hasSuffix:@".ips"]) continue;
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:[dir stringByAppendingPathComponent:f] error:nil];
        double t = [attrs.fileModificationDate timeIntervalSince1970];
        if (t > newestTime) { newestTime = t; newest = f; }
    }
    if (!newest) return nil;
    NSDictionary *parsed = [SaturnReporter parseCrashFileAtPath:[dir stringByAppendingPathComponent:newest]];
    if (!parsed) { [d setDouble:newestTime forKey:kCrashBaselineKey]; return nil; }   // not ours: skip it for good
    NSMutableDictionary *crash = [parsed mutableCopy];
    crash[@"mtime"] = @(newestTime);
    return crash;
}

- (void)markCrashHandled:(NSDictionary *)crash {
    double t = [crash[@"mtime"] doubleValue];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setDouble:MAX(t, [d doubleForKey:kCrashBaselineKey]) forKey:kCrashBaselineKey];
}

@end
