#import "SaturnSession.h"
#import "SaturnWindow.h"

static NSString *const kSessionKey = @"saturn.session.v1";

@implementation SaturnSession {
    BOOL _scheduled;
}

+ (instancetype)shared {
    static SaturnSession *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[SaturnSession alloc] init]; });
    return s;
}

- (void)scheduleSave {
    if (_scheduled) return;
    _scheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self->_scheduled = NO;
        [self saveNow];
    });
}

// With no window open (mid-quit, or the last window just closed) the previous snapshot is kept,
// so closing the last window still restores it next launch.
- (void)saveNow {
    NSMutableArray *windows = [NSMutableArray array];
    for (NSWindow *w in NSApp.windows) {
        if (![w isKindOfClass:[SaturnWindow class]] || !w.isVisible || [(SaturnWindow *)w isPrivate]) continue;
        NSDictionary *state = [(SaturnWindow *)w sessionState];
        if (state) [windows addObject:state];
    }
    if (!windows.count) return;
    [[NSUserDefaults standardUserDefaults] setObject:windows forKey:kSessionKey];
}

- (NSArray<NSDictionary *> *)savedWindows {
    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:kSessionKey];
    NSMutableArray *ok = [NSMutableArray array];
    for (id w in saved) {
        if (![w isKindOfClass:[NSDictionary class]]) continue;
        NSArray *tabs = w[@"tabs"];
        if ([tabs isKindOfClass:[NSArray class]] && tabs.count && [tabs.firstObject[@"url"] length]) [ok addObject:w];
    }
    return ok;
}
@end
