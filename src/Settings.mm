#import "Settings.h"
#import "Supabase/SupabaseClient.h"

@implementation SaturnSearchEngineInfo
+ (NSArray<SaturnSearchEngineInfo*>*)allEngines {
    static NSArray *arr;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SaturnSearchEngineInfo *g = [SaturnSearchEngineInfo new];
        g.engine = SaturnSearchEngineGoogle; g.name = @"Google"; g.shortName = @"Google"; g.templateURL = @"https://www.google.com/search?q=%s&hl=en&source=hp&ie=UTF-8&oe=UTF-8"; g.homeURL = @"https://www.google.com"; g.iconSymbol = @"magnifyingglass";

        SaturnSearchEngineInfo *b = [SaturnSearchEngineInfo new];
        b.engine = SaturnSearchEngineBing; b.name = @"Bing"; b.shortName = @"Bing"; b.templateURL = @"https://www.bing.com/search?q=%s"; b.homeURL = @"https://www.bing.com"; b.iconSymbol = @"magnifyingglass";

        SaturnSearchEngineInfo *d = [SaturnSearchEngineInfo new];
        d.engine = SaturnSearchEngineDuckDuckGo; d.name = @"DuckDuckGo"; d.shortName = @"DuckDuckGo"; d.templateURL = @"https://duckduckgo.com/?q=%s"; d.homeURL = @"https://duckduckgo.com"; d.iconSymbol = @"shield.lefthalf.filled";

        SaturnSearchEngineInfo *br = [SaturnSearchEngineInfo new];
        br.engine = SaturnSearchEngineBrave; br.name = @"Brave Search"; br.shortName = @"Brave"; br.templateURL = @"https://search.brave.com/search?q=%s"; br.homeURL = @"https://search.brave.com"; br.iconSymbol = @"flame";

        SaturnSearchEngineInfo *y = [SaturnSearchEngineInfo new];
        y.engine = SaturnSearchEngineYahoo; y.name = @"Yahoo"; y.shortName = @"Yahoo"; y.templateURL = @"https://search.yahoo.com/search?p=%s"; y.homeURL = @"https://search.yahoo.com"; y.iconSymbol = @"magnifyingglass";

        SaturnSearchEngineInfo *e = [SaturnSearchEngineInfo new];
        e.engine = SaturnSearchEngineEcosia; e.name = @"Ecosia"; e.shortName = @"Ecosia"; e.templateURL = @"https://www.ecosia.org/search?q=%s"; e.homeURL = @"https://www.ecosia.org"; e.iconSymbol = @"leaf";

        SaturnSearchEngineInfo *c = [SaturnSearchEngineInfo new];
        c.engine = SaturnSearchEngineCustom; c.name = @"Custom"; c.shortName = @"Custom"; c.templateURL = @""; c.homeURL = @""; c.iconSymbol = @"gearshape";

        arr = @[g,b,d,br,y,e,c];
    });
    return arr;
}
+ (SaturnSearchEngineInfo*)infoForEngine:(SaturnSearchEngine)engine {
    for (SaturnSearchEngineInfo *i in self.allEngines) if (i.engine == engine) return i;
    return self.allEngines.firstObject;
}
+ (SaturnSearchEngineInfo*)infoForName:(NSString*)name {
    for (SaturnSearchEngineInfo *i in self.allEngines) if ([i.name isEqualToString:name]) return i;
    return nil;
}
@end

@implementation SaturnSettings

+ (instancetype)shared {
    static SaturnSettings *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[SaturnSettings alloc] init]; [s load]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _hasCompletedSetup = NO;
        _defaultEngine = SaturnSearchEngineGoogle;
        _customTemplate = @"";
    }
    return self;
}

- (SaturnSearchEngineInfo *)currentEngineInfo {
    if (self.defaultEngine == SaturnSearchEngineCustom && self.customTemplate.length) {
        SaturnSearchEngineInfo *c = [SaturnSearchEngineInfo new];
        c.engine = SaturnSearchEngineCustom; c.name = @"Custom"; c.shortName = @"Custom"; c.templateURL = self.customTemplate; c.homeURL = @""; c.iconSymbol = @"gearshape";
        return c;
    }
    return [SaturnSearchEngineInfo infoForEngine:self.defaultEngine];
}

- (NSString *)searchURLForQuery:(NSString *)query {
    NSString *q = [query stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]] ?: @"";
    NSString *tmpl = self.currentEngineInfo.templateURL;
    if (!tmpl.length) tmpl = @"https://www.google.com/search?q=%s&hl=en&source=hp&ie=UTF-8&oe=UTF-8";
    if ([tmpl containsString:@"%s"]) {
        return [tmpl stringByReplacingOccurrencesOfString:@"%s" withString:q];
    } else if ([tmpl containsString:@"%q"]) {
        return [tmpl stringByReplacingOccurrencesOfString:@"%q" withString:q];
    } else {
        // No placeholder — append
        return [tmpl stringByAppendingString:q];
    }
}

- (void)save {
    [[NSUserDefaults standardUserDefaults] setBool:self.hasCompletedSetup forKey:@"saturn.hasCompletedSetup"];
    [[NSUserDefaults standardUserDefaults] setInteger:self.defaultEngine forKey:@"saturn.defaultSearchEngine"];
    if (self.customTemplate) [[NSUserDefaults standardUserDefaults] setObject:self.customTemplate forKey:@"saturn.customSearchTemplate"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SaturnSearchEngineChanged" object:nil];
    NSLog(@"[settings] saved setup=%d engine=%ld template=%@", self.hasCompletedSetup, (long)self.defaultEngine, self.customTemplate);

    // Sync to Supabase saturn_settings table
    [self syncToSupabaseWithCompletion:nil];
}

- (void)load {
    if ([[NSUserDefaults standardUserDefaults] objectForKey:@"saturn.hasCompletedSetup"] != nil) {
        self.hasCompletedSetup = [[NSUserDefaults standardUserDefaults] boolForKey:@"saturn.hasCompletedSetup"];
    } else {
        self.hasCompletedSetup = NO;
    }

    NSInteger v = [[NSUserDefaults standardUserDefaults] integerForKey:@"saturn.defaultSearchEngine"];
    // Distinguish not set (0) vs Google (0): check if key exists
    if ([[NSUserDefaults standardUserDefaults] objectForKey:@"saturn.defaultSearchEngine"] != nil) {
        self.defaultEngine = (SaturnSearchEngine)v;
    } else {
        self.defaultEngine = SaturnSearchEngineGoogle;
    }
    NSString *ct = [[NSUserDefaults standardUserDefaults] stringForKey:@"saturn.customSearchTemplate"];
    if (ct) self.customTemplate = ct;
}

- (void)syncToSupabaseWithCompletion:(void(^)(BOOL success, NSError *err))completion {
    if (![SupabaseClient shared].isConfigured) {
        if (completion) completion(NO, nil);
        return;
    }
    NSString *engineName = self.currentEngineInfo.name ?: @"Google";
    NSDictionary *payload = @{
        @"default_search_engine": engineName,
        @"custom_search_template": self.customTemplate ?: @"",
        @"setup_completed": @(self.hasCompletedSetup),
        @"theme": @"dark_glass"
    };
    [[SupabaseClient shared] saveSaturnSettings:payload completion:^(BOOL success, NSError *err){
        if (completion) completion(success, err);
    }];
}

- (void)syncFromSupabaseWithCompletion:(void(^)(BOOL success, NSError *err))completion {
    if (![SupabaseClient shared].isConfigured) {
        if (completion) completion(NO, nil);
        return;
    }
    [[SupabaseClient shared] fetchSaturnSettingsWithCompletion:^(NSDictionary *settings, NSError *err){
        if (settings && !err) {
            NSString *engName = settings[@"default_search_engine"];
            if (engName.length) {
                SaturnSearchEngineInfo *info = [SaturnSearchEngineInfo infoForName:engName];
                if (info) self.defaultEngine = info.engine;
            }
            if (settings[@"custom_search_template"]) {
                self.customTemplate = settings[@"custom_search_template"];
            }
            if (settings[@"setup_completed"] != nil) {
                self.hasCompletedSetup = [settings[@"setup_completed"] boolValue];
            }
            // Save loaded values to NSUserDefaults
            [[NSUserDefaults standardUserDefaults] setBool:self.hasCompletedSetup forKey:@"saturn.hasCompletedSetup"];
            [[NSUserDefaults standardUserDefaults] setInteger:self.defaultEngine forKey:@"saturn.defaultSearchEngine"];
            if (self.customTemplate) [[NSUserDefaults standardUserDefaults] setObject:self.customTemplate forKey:@"saturn.customSearchTemplate"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"SaturnSearchEngineChanged" object:nil];
            if (completion) completion(YES, nil);
        } else {
            if (completion) completion(NO, err);
        }
    }];
}

@end
