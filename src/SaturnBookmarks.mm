#import "SaturnBookmarks.h"

NSNotificationName const SaturnBookmarksChangedNotification = @"SaturnBookmarksChanged";

static NSString *const kBookmarksKey = @"saturn.bookmarks.v1";
static NSString *const kSeededKey = @"saturn.bookmarks.seeded";

@implementation SaturnBookmarks {
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *_items;
}

+ (instancetype)shared {
    static SaturnBookmarks *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[SaturnBookmarks alloc] init]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSArray *saved = [d arrayForKey:kBookmarksKey];
    _items = [NSMutableArray array];
    for (id e in saved) {
        if ([e isKindOfClass:[NSDictionary class]] && [e[@"url"] length]) [_items addObject:e];
    }
    [self seedIfNeeded];
    return self;
}

- (void)seedIfNeeded {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    // First launch: start the favorites bar with a few common sites
    if (![d boolForKey:kSeededKey]) {
        [d setBool:YES forKey:kSeededKey];
        if (_items.count == 0) {
            NSArray *seed = @[@[@"Apple", @"https://apple.com"], @[@"Gmail", @"https://mail.google.com"], @[@"YouTube", @"https://youtube.com"],
                              @[@"GitHub", @"https://github.com"], @[@"Wikipedia", @"https://wikipedia.org"]];
            for (NSArray *p in seed) [_items addObject:@{@"title": p[0], @"url": p[1]}];
            [self save];
        }
    }
}

// Factory reset: back to the starter bookmarks.
- (void)resetToDefaults {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [_items removeAllObjects];
    [d removeObjectForKey:kBookmarksKey];
    [d setBool:NO forKey:kSeededKey];
    [self seedIfNeeded];
    [self changed];
}

- (NSArray<NSDictionary<NSString *, NSString *> *> *)items { return [_items copy]; }

+ (BOOL)canBookmarkURL:(NSURL *)url {
    NSString *scheme = url.scheme.lowercaseString;
    return url.host.length && ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]);
}

+ (NSString *)keyForURL:(NSURL *)url {
    if (!url) return @"";
    NSURLComponents *c = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    c.fragment = nil;
    NSString *s = c.string ?: url.absoluteString;
    if ([c.path isEqualToString:@"/"] && !c.query.length && [s hasSuffix:@"/"]) s = [s substringToIndex:s.length - 1];
    return s;
}

- (NSInteger)indexOfKey:(NSString *)key {
    for (NSInteger i = 0; i < (NSInteger)_items.count; i++) {
        NSURL *u = [NSURL URLWithString:_items[i][@"url"]];
        if ([[SaturnBookmarks keyForURL:u] isEqualToString:key]) return i;
    }
    return NSNotFound;
}

- (BOOL)containsURL:(NSURL *)url {
    if (![SaturnBookmarks canBookmarkURL:url]) return NO;
    return [self indexOfKey:[SaturnBookmarks keyForURL:url]] != NSNotFound;
}

- (void)save {
    [[NSUserDefaults standardUserDefaults] setObject:_items forKey:kBookmarksKey];
}

- (void)changed {
    [self save];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SaturnBookmarksChangedNotification object:self];
    });
}

- (void)addURL:(NSURL *)url title:(NSString *)title {
    if (![SaturnBookmarks canBookmarkURL:url] || [self containsURL:url]) return;
    NSString *t = [title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!t.length) t = url.host;
    [_items addObject:@{@"title": t, @"url": [SaturnBookmarks keyForURL:url]}];
    [self changed];
}

- (void)removeURLString:(NSString *)urlString {
    NSInteger i = [self indexOfKey:[SaturnBookmarks keyForURL:[NSURL URLWithString:urlString]]];
    if (i == NSNotFound) return;
    [_items removeObjectAtIndex:i];
    [self changed];
}

- (BOOL)toggleURL:(NSURL *)url title:(NSString *)title {
    if (![SaturnBookmarks canBookmarkURL:url]) return NO;
    if ([self containsURL:url]) { [self removeURLString:url.absoluteString]; return NO; }
    [self addURL:url title:title];
    return YES;
}
@end
