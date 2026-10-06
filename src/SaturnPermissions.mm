#import "SaturnPermissions.h"

static NSString *const kPermKey = @"saturn.sitePermissions.v1";

@implementation SaturnPermissions

+ (NSMutableDictionary<NSString *, NSMutableDictionary *> *)sessionStore {
    static NSMutableDictionary *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [NSMutableDictionary dictionary]; });
    return s;
}

+ (NSString *)originKeyForProtocol:(NSString *)protocol host:(NSString *)host port:(NSInteger)port {
    NSString *p = protocol.lowercaseString ?: @"https";
    BOOL defaultPort = port == 0 || (port == 443 && [p isEqualToString:@"https"]) || (port == 80 && [p isEqualToString:@"http"]);
    return defaultPort ? [NSString stringWithFormat:@"%@://%@", p, host.lowercaseString]
                       : [NSString stringWithFormat:@"%@://%@:%ld", p, host.lowercaseString, (long)port];
}

+ (NSString *)decisionForOrigin:(NSString *)origin kind:(NSString *)kind privateMode:(BOOL)privateMode {
    NSDictionary *all = privateMode ? [self sessionStore] : [[NSUserDefaults standardUserDefaults] dictionaryForKey:kPermKey];
    NSString *d = all[origin][kind];
    return [d isKindOfClass:[NSString class]] ? d : nil;
}

+ (void)setDecision:(NSString *)decision forOrigin:(NSString *)origin kinds:(NSArray<NSString *> *)kinds privateMode:(BOOL)privateMode {
    if (privateMode) {
        NSMutableDictionary *site = [self sessionStore][origin] ?: [NSMutableDictionary dictionary];
        for (NSString *k in kinds) site[k] = decision;
        [self sessionStore][origin] = site;
        return;
    }
    NSMutableDictionary *all = [[[NSUserDefaults standardUserDefaults] dictionaryForKey:kPermKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableDictionary *site = [all[origin] mutableCopy] ?: [NSMutableDictionary dictionary];
    for (NSString *k in kinds) site[k] = decision;
    all[origin] = site;
    [[NSUserDefaults standardUserDefaults] setObject:all forKey:kPermKey];
}

+ (void)resetAll {
    [[self sessionStore] removeAllObjects];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kPermKey];
}
@end
