#import "SaturnImporter.h"
#import "SaturnBookmarks.h"
#import "SaturnHistory.h"
#import <AppKit/AppKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <sqlite3.h>

@implementation SaturnImportSource
@end

static const NSUInteger kMaxImportedHistory = 5000;
static const NSUInteger kMaxImportedBookmarks = 3000;

static BOOL IsWebURL(NSString *s) {
    return [s hasPrefix:@"http://"] || [s hasPrefix:@"https://"];
}

#pragma mark SQLite helpers

// Browsers keep their database locked while running, so read a private copy (with its write-ahead log).
static NSString *CopyDatabase(NSString *path) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm isReadableFileAtPath:path]) return nil;
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *copy = [dir stringByAppendingPathComponent:@"db.sqlite"];
    if (![fm copyItemAtPath:path toPath:copy error:nil]) return nil;
    for (NSString *suffix in @[@"-wal", @"-shm"]) {
        NSString *side = [path stringByAppendingString:suffix];
        if ([fm fileExistsAtPath:side]) [fm copyItemAtPath:side toPath:[copy stringByAppendingString:suffix] error:nil];
    }
    return copy;
}

// Calls `row` with up to three text/number columns. Returns NO if the database could not be opened or queried.
static BOOL QueryDatabase(NSString *path, const char *sql, void (^row)(NSString *a, NSString *b, double c)) {
    NSString *copy = CopyDatabase(path);
    if (!copy) return NO;
    sqlite3 *db = NULL;
    BOOL ok = NO;
    if (sqlite3_open_v2(copy.fileSystemRepresentation, &db, SQLITE_OPEN_READONLY, NULL) == SQLITE_OK) {
        sqlite3_stmt *st = NULL;
        if (sqlite3_prepare_v2(db, sql, -1, &st, NULL) == SQLITE_OK) {
            ok = YES;
            while (sqlite3_step(st) == SQLITE_ROW) {
                const unsigned char *a = sqlite3_column_text(st, 0), *b = sqlite3_column_text(st, 1);
                row(a ? @((const char *)a) : @"", b ? @((const char *)b) : @"", sqlite3_column_double(st, 2));
            }
        }
        sqlite3_finalize(st);
    }
    if (db) sqlite3_close(db);
    [[NSFileManager defaultManager] removeItemAtPath:[copy stringByDeletingLastPathComponent] error:nil];
    return ok;
}

#pragma mark Readers  (each returns bookmarks as {title,url} and history as {u,t,d})

static void CollectChromiumNode(NSDictionary *node, NSMutableArray *out) {
    if ([node[@"type"] isEqualToString:@"url"] && IsWebURL(node[@"url"])) {
        [out addObject:@{@"title": node[@"name"] ?: @"", @"url": node[@"url"]}];
    }
    for (NSDictionary *c in node[@"children"]) if ([c isKindOfClass:[NSDictionary class]]) CollectChromiumNode(c, out);
}

static NSArray *ChromiumBookmarks(NSString *dir) {
    NSData *data = [NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"Bookmarks"]];
    if (!data) return nil;
    NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![root isKindOfClass:[NSDictionary class]]) return nil;
    NSMutableArray *out = [NSMutableArray array];
    NSDictionary *roots = root[@"roots"];
    for (NSString *k in @[@"bookmark_bar", @"other", @"synced"]) if ([roots[k] isKindOfClass:[NSDictionary class]]) CollectChromiumNode(roots[k], out);
    return out;
}

static NSArray *ChromiumHistory(NSString *dir) {
    NSMutableArray *out = [NSMutableArray array];
    BOOL ok = QueryDatabase([dir stringByAppendingPathComponent:@"History"],
        "SELECT url, title, last_visit_time FROM urls WHERE hidden = 0 ORDER BY last_visit_time DESC LIMIT 5000",
        ^(NSString *u, NSString *t, double webkit) {
            if (!IsWebURL(u) || webkit <= 0) return;
            [out addObject:@{@"u": u, @"t": t, @"d": @(webkit / 1e6 - 11644473600.0)}];   // WebKit epoch is 1601
        });
    return ok ? out : nil;
}

static NSString *FirefoxDB(NSString *dir) { return [dir stringByAppendingPathComponent:@"places.sqlite"]; }

static NSArray *FirefoxBookmarks(NSString *dir) {
    NSMutableArray *out = [NSMutableArray array];
    BOOL ok = QueryDatabase(FirefoxDB(dir),
        "SELECT p.url, b.title, 0 FROM moz_bookmarks b JOIN moz_places p ON b.fk = p.id WHERE b.type = 1 AND p.url LIKE 'http%' LIMIT 3000",
        ^(NSString *u, NSString *t, double c) { (void)c; if (IsWebURL(u)) [out addObject:@{@"title": t, @"url": u}]; });
    return ok ? out : nil;
}

static NSArray *FirefoxHistory(NSString *dir) {
    NSMutableArray *out = [NSMutableArray array];
    BOOL ok = QueryDatabase(FirefoxDB(dir),
        "SELECT url, title, last_visit_date FROM moz_places WHERE last_visit_date IS NOT NULL AND url LIKE 'http%' ORDER BY last_visit_date DESC LIMIT 5000",
        ^(NSString *u, NSString *t, double micro) { if (IsWebURL(u)) [out addObject:@{@"u": u, @"t": t, @"d": @(micro / 1e6)}]; });
    return ok ? out : nil;
}

static void CollectSafariNode(NSDictionary *node, NSMutableArray *out) {
    if ([node[@"WebBookmarkType"] isEqualToString:@"WebBookmarkTypeLeaf"] && IsWebURL(node[@"URLString"])) {
        NSString *t = node[@"URIDictionary"][@"title"] ?: @"";
        [out addObject:@{@"title": t, @"url": node[@"URLString"]}];
    }
    for (NSDictionary *c in node[@"Children"]) if ([c isKindOfClass:[NSDictionary class]]) CollectSafariNode(c, out);
}

static NSArray *SafariBookmarks(NSString *dir) {
    NSDictionary *root = [NSDictionary dictionaryWithContentsOfFile:[dir stringByAppendingPathComponent:@"Bookmarks.plist"]];
    if (!root) return nil;
    NSMutableArray *out = [NSMutableArray array];
    CollectSafariNode(root, out);
    return out;
}

static NSArray *SafariHistory(NSString *dir) {
    NSMutableArray *out = [NSMutableArray array];
    BOOL ok = QueryDatabase([dir stringByAppendingPathComponent:@"History.db"],
        "SELECT i.url, v.title, v.visit_time FROM history_visits v JOIN history_items i ON i.id = v.history_item ORDER BY v.visit_time DESC LIMIT 5000",
        ^(NSString *u, NSString *t, double cocoa) { if (IsWebURL(u)) [out addObject:@{@"u": u, @"t": t, @"d": @(cocoa + 978307200.0)}]; });   // Cocoa epoch is 2001
    return ok ? out : nil;
}

// Netscape bookmark files: <A HREF="https://…">Title</A>
static NSArray *HTMLBookmarks(NSString *path) {
    NSString *html = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!html) html = [NSString stringWithContentsOfFile:path encoding:NSISOLatin1StringEncoding error:nil];
    if (!html) return nil;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"<A\\s[^>]*?HREF=\"([^\"]+)\"[^>]*>(.*?)</A>"
                                                                        options:NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators error:nil];
    NSMutableArray *out = [NSMutableArray array];
    [re enumerateMatchesInString:html options:0 range:NSMakeRange(0, html.length) usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *stop) {
        (void)f;
        NSString *u = [html substringWithRange:[m rangeAtIndex:1]];
        u = [u stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
        NSString *t = [html substringWithRange:[m rangeAtIndex:2]];
        t = [t stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
        t = [t stringByReplacingOccurrencesOfString:@"&#39;" withString:@"'"];
        t = [t stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""];
        if (IsWebURL(u)) [out addObject:@{@"title": t, @"url": u}];
        if (out.count >= kMaxImportedBookmarks) *stop = YES;
    }];
    return out;
}

#pragma mark Discovery

@implementation SaturnImporter

+ (NSArray<SaturnImportSource *> *)availableSources {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    NSMutableArray<SaturnImportSource *> *out = [NSMutableArray array];
    void (^add)(NSString *, NSString *, NSString *) = ^(NSString *name, NSString *kind, NSString *path) {
        SaturnImportSource *s = [[SaturnImportSource alloc] init];
        s.name = name; s.kind = kind; s.path = path;
        [out addObject:s];
    };

    // name, folder under Application Support
    NSArray *chromium = @[@[@"Google Chrome", @"Google/Chrome"], @[@"Brave", @"BraveSoftware/Brave-Browser"],
                          @[@"Microsoft Edge", @"Microsoft Edge"], @[@"Arc", @"Arc/User Data"], @[@"Vivaldi", @"Vivaldi"],
                          @[@"Opera", @"com.operasoftware.Opera"], @[@"Chromium", @"Chromium"]];
    for (NSArray *b in chromium) {
        NSString *base = [support stringByAppendingPathComponent:b[1]];
        if (![fm fileExistsAtPath:base]) continue;
        NSDictionary *local = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[base stringByAppendingPathComponent:@"Local State"]] ?: [NSData data] options:0 error:nil];
        NSDictionary *names = [local isKindOfClass:[NSDictionary class]] ? local[@"profile"][@"info_cache"] : nil;
        NSMutableArray *profiles = [NSMutableArray array];
        for (NSString *f in [fm contentsOfDirectoryAtPath:base error:nil]) {
            if (![f isEqualToString:@"Default"] && ![f hasPrefix:@"Profile "]) continue;
            NSString *dir = [base stringByAppendingPathComponent:f];
            if ([fm fileExistsAtPath:[dir stringByAppendingPathComponent:@"Bookmarks"]] || [fm fileExistsAtPath:[dir stringByAppendingPathComponent:@"History"]]) [profiles addObject:f];
        }
        if (!profiles.count && [fm fileExistsAtPath:[base stringByAppendingPathComponent:@"Bookmarks"]]) { add(b[0], @"chromium", base); continue; }   // Opera keeps files in the root
        [profiles sortUsingSelector:@selector(localizedStandardCompare:)];
        for (NSString *f in profiles) {
            NSString *label = b[0];
            if (profiles.count > 1) label = [NSString stringWithFormat:@"%@ – %@", b[0], names[f][@"name"] ?: f];
            add(label, @"chromium", [base stringByAppendingPathComponent:f]);
        }
    }

    NSString *ffBase = [support stringByAppendingPathComponent:@"Firefox/Profiles"];
    NSMutableArray *ff = [NSMutableArray array];
    for (NSString *f in [fm contentsOfDirectoryAtPath:ffBase error:nil]) {
        if ([fm fileExistsAtPath:FirefoxDB([ffBase stringByAppendingPathComponent:f])]) [ff addObject:f];
    }
    for (NSString *f in ff) {
        // Folder names look like "x8f3k.default-release"
        NSString *label = ff.count > 1 ? [NSString stringWithFormat:@"Firefox – %@", [f pathExtension].length ? [f pathExtension] : f] : @"Firefox";
        add(label, @"firefox", [ffBase stringByAppendingPathComponent:f]);
    }

    NSString *safari = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Safari"];
    if ([fm fileExistsAtPath:@"/Applications/Safari.app"] || [fm fileExistsAtPath:@"/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app"]) add(@"Safari", @"safari", safari);
    return out;
}

#pragma mark Merging (main thread)

+ (NSUInteger)mergeBookmarks:(NSArray *)items {
    SaturnBookmarks *store = [SaturnBookmarks shared];
    NSUInteger before = store.items.count, seen = 0;
    for (NSDictionary *b in items) {
        if (++seen > kMaxImportedBookmarks) break;
        NSURL *u = [NSURL URLWithString:b[@"url"]];
        if (u) [store addURL:u title:b[@"title"]];
    }
    return store.items.count - before;
}

+ (NSUInteger)mergeHistory:(NSArray *)items {
    if (!items.count) return 0;
    NSArray *slice = items.count > kMaxImportedHistory ? [items subarrayWithRange:NSMakeRange(0, kMaxImportedHistory)] : items;
    return [[SaturnHistory shared] importEntries:slice];
}

+ (void)importFromSource:(SaturnImportSource *)source bookmarks:(BOOL)wantBookmarks history:(BOOL)wantHistory
              completion:(void (^)(NSUInteger, NSUInteger, NSString *))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray *bm = nil, *hist = nil;
        BOOL bmFailed = NO, histFailed = NO;
        NSString *dir = source.path;
        if (wantBookmarks) {
            bm = [source.kind isEqualToString:@"chromium"] ? ChromiumBookmarks(dir) : [source.kind isEqualToString:@"firefox"] ? FirefoxBookmarks(dir) : SafariBookmarks(dir);
            bmFailed = (bm == nil);
        }
        if (wantHistory) {
            hist = [source.kind isEqualToString:@"chromium"] ? ChromiumHistory(dir) : [source.kind isEqualToString:@"firefox"] ? FirefoxHistory(dir) : SafariHistory(dir);
            histFailed = (hist == nil);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            NSUInteger b = bm ? [self mergeBookmarks:bm] : 0, h = hist ? [self mergeHistory:hist] : 0;
            NSString *note = nil;
            if (bmFailed || histFailed) {
                if ([source.kind isEqualToString:@"safari"]) note = @"Safari keeps its data protected. To import it, give Saturn Full Disk Access in System Settings ▸ Privacy & Security, or export bookmarks from Safari (File ▸ Export ▸ Bookmarks) and choose that file instead.";
                else note = [NSString stringWithFormat:@"Some of %@'s data could not be read.", source.name];
            }
            completion(b, h, note);
        });
    });
}

+ (void)importBookmarksHTMLAtPath:(NSString *)path completion:(void (^)(NSUInteger, NSString *))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray *bm = HTMLBookmarks(path);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!bm) { completion(0, @"That file could not be read."); return; }
            completion([self mergeBookmarks:bm], bm.count ? nil : @"No bookmarks were found in that file.");
        });
    });
}

#pragma mark Dialog

+ (void)presentImportDialogFromWindow:(NSWindow *)window {
    NSArray<SaturnImportSource *> *sources = [self availableSources];
    NSAlert *al = [[NSAlert alloc] init];
    al.messageText = @"Import from another browser";
    al.informativeText = @"Bring your bookmarks and history into Saturn. Passwords and cookies aren’t imported.";
    [al addButtonWithTitle:@"Import"];
    [al addButtonWithTitle:@"Cancel"];

    NSView *box = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 92)];
    NSPopUpButton *pop = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 62, 300, 26) pullsDown:NO];
    for (SaturnImportSource *s in sources) [pop addItemWithTitle:s.name];
    if (sources.count) [[pop menu] addItem:[NSMenuItem separatorItem]];
    [pop addItemWithTitle:@"Bookmarks file (.html)…"];
    NSButton *bm = [NSButton checkboxWithTitle:@"Bookmarks" target:nil action:nil];
    NSButton *hist = [NSButton checkboxWithTitle:@"History" target:nil action:nil];
    bm.state = hist.state = NSControlStateValueOn;
    bm.frame = NSMakeRect(2, 32, 200, 20);
    hist.frame = NSMakeRect(2, 8, 200, 20);
    for (NSView *v in @[pop, bm, hist]) [box addSubview:v];
    al.accessoryView = box;

    void (^finish)(NSModalResponse) = ^(NSModalResponse r) {
        if (r != NSAlertFirstButtonReturn) return;
        NSInteger idx = pop.indexOfSelectedItem;
        void (^report)(NSString *) = ^(NSString *text) {
            NSAlert *done = [[NSAlert alloc] init];
            done.messageText = @"Import finished";
            done.informativeText = text;
            [done addButtonWithTitle:@"OK"];
            [done runModal];
        };
        if (idx >= (NSInteger)sources.count) {      // file
            NSOpenPanel *p = [NSOpenPanel openPanel];
            p.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"html"]];
            p.message = @"Choose a bookmarks file exported from your other browser";
            if ([p runModal] != NSModalResponseOK) return;
            [self importBookmarksHTMLAtPath:p.URL.path completion:^(NSUInteger added, NSString *note) {
                report(note ? note : [NSString stringWithFormat:@"%lu bookmark%@ added.", (unsigned long)added, added == 1 ? @"" : @"s"]);
            }];
            return;
        }
        if (bm.state != NSControlStateValueOn && hist.state != NSControlStateValueOn) return;
        [self importFromSource:sources[idx] bookmarks:bm.state == NSControlStateValueOn history:hist.state == NSControlStateValueOn
                    completion:^(NSUInteger b, NSUInteger h, NSString *note) {
            NSMutableArray *parts = [NSMutableArray array];
            if (bm.state == NSControlStateValueOn) [parts addObject:[NSString stringWithFormat:@"%lu new bookmark%@", (unsigned long)b, b == 1 ? @"" : @"s"]];
            if (hist.state == NSControlStateValueOn) [parts addObject:[NSString stringWithFormat:@"%lu history entr%@", (unsigned long)h, h == 1 ? @"y" : @"ies"]];
            NSString *text = [[parts componentsJoinedByString:@" and "] stringByAppendingString:@" imported."];
            if (note) text = [text stringByAppendingFormat:@"\n\n%@", note];
            report(text);
        }];
    };
    if (!sources.count) al.informativeText = @"No other browsers were found, but you can import a bookmarks file exported from one.";
    finish([al runModal]);
}
@end
