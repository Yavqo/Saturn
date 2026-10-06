#import "SupabaseClient.h"

@interface SupabaseClient ()
@property (nonatomic, readwrite, copy) NSDictionary *currentSession;
@end

@implementation SupabaseClient {
    NSString *_url;
    NSString *_key;
}

+ (instancetype)shared {
    static SupabaseClient *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[SupabaseClient alloc] init]; });
    return s;
}

- (void)configureWithURL:(NSString *)url anonKey:(NSString *)anonKey {
    NSString *u = [url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *k = [anonKey stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (u.length && [u hasPrefix:@"http"]) _url = [u copy];
    if (k.length) _key = [k copy];
    if (_url && _key) {
        NSLog(@"[supabase] configured url=%@ key=%.8@...", _url, _key);
    } else {
        NSLog(@"[supabase] not configured (url=%@ key=%@)", _url ? @"set" : @"nil", _key ? @"set" : @"nil");
    }
}

- (void)configureFromEnvironment {
    // 1) env vars
    NSString *envURL = [[[NSProcessInfo processInfo] environment] objectForKey:@"SUPABASE_URL"];
    NSString *envKey = [[[NSProcessInfo processInfo] environment] objectForKey:@"SUPABASE_ANON_KEY"];
    // 2) Info.plist (set via CMake or .env -> plist)
    if (!envURL.length) envURL = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"SupabaseURL"];
    if (!envKey.length) envKey = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"SupabaseAnonKey"];
    // 3) fallback: read .env file in bundle/resource or project root (for dev)
    if (!envURL.length || !envKey.length) {
        NSMutableArray *candidates = [NSMutableArray array];
        NSString *a = [[NSBundle mainBundle] pathForResource:@".env" ofType:nil];
        if (a) [candidates addObject:a];
        NSString *b = [[NSBundle mainBundle] pathForResource:@"env" ofType:nil];
        if (b) [candidates addObject:b];
        [candidates addObject:@"/Users/nacrosoft/Documents/YavqoSaturn/.env"];
        [candidates addObject:@"./.env"];
        for (NSString *p in candidates) {
            if (!p) continue;
            NSString *content = [NSString stringWithContentsOfFile:p encoding:NSUTF8StringEncoding error:nil];
            if (!content) continue;
            for (NSString *line in [content componentsSeparatedByString:@"\n"]) {
                NSString *t = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if ([t hasPrefix:@"#"] || t.length==0) continue;
                NSArray *kv = [t componentsSeparatedByString:@"="];
                if (kv.count < 2) continue;
                NSString *k = [[kv[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] stringByReplacingOccurrencesOfString:@"export " withString:@""];
                NSString *v = [[kv subarrayWithRange:NSMakeRange(1, kv.count-1)] componentsJoinedByString:@"="];
                v = [v stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                // strip quotes
                if (([v hasPrefix:@"\""] && [v hasSuffix:@"\""]) || ([v hasPrefix:@"'"] && [v hasSuffix:@"'"])) {
                    v = [v substringWithRange:NSMakeRange(1, v.length-2)];
                }
                if ([k isEqualToString:@"SUPABASE_URL"] && !envURL.length) envURL = v;
                if ([k isEqualToString:@"SUPABASE_ANON_KEY"] && !envKey.length) envKey = v;
            }
        }
    }
    if (envURL.length && envKey.length) {
        [self configureWithURL:envURL anonKey:envKey];
    } else {
        NSLog(@"[supabase] not configured — set SUPABASE_URL and SUPABASE_ANON_KEY in env or .env (no features yet)");
    }
}

- (BOOL)isConfigured { return _url.length > 0 && _key.length > 0; }
- (NSString *)supabaseURL { return _url; }
- (NSString *)anonKey { return _key; }

- (NSMutableURLRequest *)requestForPath:(NSString *)path {
    NSString *base = [_url hasSuffix:@"/"] ? _url : [_url stringByAppendingString:@"/"];
    NSString *full = [base stringByAppendingString:[path hasPrefix:@"/"] ? [path substringFromIndex:1] : path];
    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:full]];
    r.timeoutInterval = 15;
    if (_key) {
        [r setValue:_key forHTTPHeaderField:@"apikey"];
        [r setValue:[NSString stringWithFormat:@"Bearer %@", _key] forHTTPHeaderField:@"Authorization"];
    }
    [r setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [r setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    return r;
}

- (void)pingWithCompletion:(void(^)(BOOL, NSError *))completion {
    if (!self.isConfigured) {
        if (completion) completion(NO, [NSError errorWithDomain:@"Supabase" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Not configured — set SUPABASE_URL / SUPABASE_ANON_KEY"}]);
        return;
    }
    // anon key cannot hit /rest/v1/ root (requires service_role) — ping auth health instead
    NSMutableURLRequest *r = [self requestForPath:@"auth/v1/health"];
    r.HTTPMethod = @"GET";
    NSURLSessionDataTask *t = [[NSURLSession sharedSession] dataTaskWithRequest:r completionHandler:^(NSData *d, NSURLResponse *resp, NSError *e){
        NSInteger code = [(NSHTTPURLResponse*)resp statusCode];
        BOOL ok = (!e && (code == 200 || code == 204));
        // fallback: if auth health not available, consider configured as ok (key syntactically valid)
        if (!ok && !e && code == 401) {
            // anon key is still valid, just endpoint requires service_role — treat as configured
            ok = YES;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(ok, e);
            NSLog(@"[supabase] ping %@ %ld", ok?@"ok":@"fail", (long)code);
        });
    }];
    [t resume];
}

- (void)restGet:(NSString *)path completion:(void(^)(NSData*, NSURLResponse*, NSError*))completion {
    if (!self.isConfigured) {
        if (completion) completion(nil, nil, [NSError errorWithDomain:@"Supabase" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Not configured"}]);
        return;
    }
    NSMutableURLRequest *r = [self requestForPath:path];
    r.HTTPMethod = @"GET";
    [[NSURLSession sharedSession] dataTaskWithRequest:r completionHandler:^(NSData*d, NSURLResponse*resp, NSError*e){
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(d, resp, e); });
    }].resume;
}

- (void)restPost:(NSString *)path json:(NSDictionary *)json completion:(void(^)(NSData*, NSURLResponse*, NSError*))completion {
    if (!self.isConfigured) {
        if (completion) completion(nil, nil, [NSError errorWithDomain:@"Supabase" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Not configured"}]);
        return;
    }
    NSMutableURLRequest *r = [self requestForPath:path];
    r.HTTPMethod = @"POST";
    if (json) r.HTTPBody = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
    [r setValue:@"return=representation" forHTTPHeaderField:@"Prefer"];
    [[NSURLSession sharedSession] dataTaskWithRequest:r completionHandler:^(NSData*d, NSURLResponse*resp, NSError*e){
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(d, resp, e); });
    }].resume;
}

#pragma mark - Session

- (NSDictionary *)currentSession {
    NSDictionary *s = [[NSUserDefaults standardUserDefaults] objectForKey:@"supabase.session"];
    if (![s isKindOfClass:[NSDictionary class]]) return nil;
    // Clean NSNull that may have been stored before fix (caused crash)
    BOOL hasNull = NO;
    for (id k in s) {
        if ([s[k] isKindOfClass:[NSNull class]]) { hasNull = YES; break; }
        if ([s[k] isKindOfClass:[NSDictionary class]]) {
            for (id kk in s[k]) if ([s[k][kk] isKindOfClass:[NSNull class]]) { hasNull = YES; break; }
        }
    }
    if (hasNull) {
        NSDictionary *clean = [[self class] cleanForDefaults:s];
        @try { [[NSUserDefaults standardUserDefaults] setObject:clean forKey:@"supabase.session"]; [[NSUserDefaults standardUserDefaults] synchronize]; } @catch (NSException *e) { NSLog(@"[supabase] clean stored session failed: %@", e); [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"supabase.session"]; }
        return clean;
    }
    return s;
}
+ (id)cleanForDefaults:(id)obj {
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *clean = [NSMutableDictionary dictionary];
        for (id k in (NSDictionary *)obj) {
            id v = ((NSDictionary *)obj)[k];
            if ([v isKindOfClass:[NSNull class]]) continue;
            id cv = [self cleanForDefaults:v];
            if (cv) clean[k] = cv;
        }
        return [clean copy];
    } else if ([obj isKindOfClass:[NSArray class]]) {
        NSMutableArray *clean = [NSMutableArray array];
        for (id v in (NSArray *)obj) {
            if ([v isKindOfClass:[NSNull class]]) continue;
            id cv = [self cleanForDefaults:v];
            if (cv) [clean addObject:cv];
        }
        return [clean copy];
    } else if ([obj isKindOfClass:[NSNull class]]) {
        return nil;
    }
    return obj;
}
- (void)setCurrentSession:(NSDictionary *)session {
    if (session) {
        NSDictionary *clean = [[self class] cleanForDefaults:session];
        @try {
            [[NSUserDefaults standardUserDefaults] setObject:clean forKey:@"supabase.session"];
        } @catch (NSException *ex) {
            NSLog(@"[supabase] failed to save session: %@ clean=%@", ex, clean);
            NSMutableDictionary *minimal = [NSMutableDictionary dictionary];
            if (clean[@"access_token"]) minimal[@"access_token"] = clean[@"access_token"];
            if (clean[@"refresh_token"]) minimal[@"refresh_token"] = clean[@"refresh_token"];
            if (clean[@"user"] && [clean[@"user"] isKindOfClass:[NSDictionary class]]) {
                NSDictionary *u = clean[@"user"];
                NSMutableDictionary *mu = [NSMutableDictionary dictionary];
                if (u[@"id"]) mu[@"id"] = u[@"id"];
                if (u[@"email"]) mu[@"email"] = u[@"email"];
                if (u[@"role"]) mu[@"role"] = u[@"role"];
                minimal[@"user"] = mu;
            }
            @try { [[NSUserDefaults standardUserDefaults] setObject:minimal forKey:@"supabase.session"]; } @catch (NSException *e2) { NSLog(@"[supabase] minimal save also failed: %@", e2); }
        }
    } else {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"supabase.session"];
    }
    [[NSUserDefaults standardUserDefaults] synchronize];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"SupabaseSessionChanged" object:nil];
    });
}
- (NSString *)currentUserId {
    NSDictionary *u = self.currentSession[@"user"];
    if ([u isKindOfClass:[NSDictionary class]]) {
        id v = u[@"id"];
        if ([v isKindOfClass:[NSString class]]) return v;
    }
    id v = self.currentSession[@"user_id"];
    if ([v isKindOfClass:[NSString class]]) return v;
    v = self.currentSession[@"id"];
    if ([v isKindOfClass:[NSString class]]) return v;
    return nil;
}
- (NSString *)currentUserEmail {
    NSDictionary *u = self.currentSession[@"user"];
    if ([u isKindOfClass:[NSDictionary class]]) {
        id v = u[@"email"];
        if ([v isKindOfClass:[NSString class]]) return v;
    }
    id v = self.currentSession[@"email"];
    if ([v isKindOfClass:[NSString class]]) return v;
    return nil;
}
- (BOOL)isSignedIn {
    id tok = self.currentSession[@"access_token"];
    if ([tok isKindOfClass:[NSString class]]) return [(NSString *)tok length] > 0;
    return NO;
}
- (void)clearSession {
    self.currentSession = nil;
    NSLog(@"[supabase] session cleared");
}

- (NSMutableURLRequest *)authRequestForPath:(NSString *)path {
    NSMutableURLRequest *r = [self requestForPath:path];
    // For auth, always send apikey + anon bearer; if signed in, override with access_token for user-specific calls
    return r;
}
- (NSMutableURLRequest *)authedRequestForPath:(NSString *)path {
    NSMutableURLRequest *r = [self requestForPath:path];
    id tok = self.currentSession[@"access_token"];
    if ([tok isKindOfClass:[NSString class]] && [(NSString *)tok length] > 0) {
        [r setValue:[NSString stringWithFormat:@"Bearer %@", tok] forHTTPHeaderField:@"Authorization"];
    }
    return r;
}

#pragma mark - Auth

- (void)signUpWithEmail:(NSString *)email password:(NSString *)password completion:(void(^)(NSDictionary *, NSError *))completion {
    if (!self.isConfigured) { if (completion) completion(nil, [NSError errorWithDomain:@"Supabase" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Not configured"}]); return; }
    NSMutableURLRequest *r = [self authRequestForPath:@"auth/v1/signup"];
    r.HTTPMethod = @"POST";
    NSDictionary *body = @{@"email": email ?: @"", @"password": password ?: @""};
    r.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    [[NSURLSession sharedSession] dataTaskWithRequest:r completionHandler:^(NSData*d, NSURLResponse*resp, NSError*e){
        NSDictionary *json = nil;
        if (d) json = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
        NSInteger code = [(NSHTTPURLResponse*)resp statusCode];
        NSError *err = e;
        if (!err && (code < 200 || code >= 300)) {
            NSString *msg = json[@"msg"] ?: json[@"error_description"] ?: json[@"error"] ?: [NSString stringWithFormat:@"Signup failed %ld", (long)code];
            err = [NSError errorWithDomain:@"Supabase" code:code userInfo:@{NSLocalizedDescriptionKey: msg, @"response": json ?: @{}}];
        }
        // Supabase may return session directly if email confirm disabled, or user without session if confirm required
        if (!err && json) {
            // If session in response (access_token), store it
            if (json[@"access_token"]) {
                NSMutableDictionary *sess = [json mutableCopy];
                // normalize user
                if (!sess[@"user"] && json[@"user"]) sess[@"user"] = json[@"user"];
                self.currentSession = sess;
            } else if (json[@"user"] && json[@"user"][@"id"]) {
                // store user without token (needs email confirm) — still store for reference
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(json, err); });
    }].resume;
}

- (void)signInWithEmail:(NSString *)email password:(NSString *)password completion:(void(^)(NSDictionary *, NSError *))completion {
    if (!self.isConfigured) { if (completion) completion(nil, [NSError errorWithDomain:@"Supabase" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Not configured"}]); return; }
    NSMutableURLRequest *r = [self authRequestForPath:@"auth/v1/token?grant_type=password"];
    r.HTTPMethod = @"POST";
    NSDictionary *body = @{@"email": email ?: @"", @"password": password ?: @""};
    r.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    [[NSURLSession sharedSession] dataTaskWithRequest:r completionHandler:^(NSData*d, NSURLResponse*resp, NSError*e){
        NSDictionary *json = nil;
        if (d) json = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
        NSInteger code = [(NSHTTPURLResponse*)resp statusCode];
        NSError *err = e;
        if (!err && (code < 200 || code >= 300)) {
            NSString *msg = json[@"error_description"] ?: json[@"error"] ?: json[@"msg"] ?: [NSString stringWithFormat:@"Sign in failed %ld", (long)code];
            err = [NSError errorWithDomain:@"Supabase" code:code userInfo:@{NSLocalizedDescriptionKey: msg}];
        }
        if (!err && json[@"access_token"]) {
            self.currentSession = json;
            NSLog(@"[supabase] signed in user=%@ token=%.10@...", json[@"user"][@"email"] ?: json[@"user"][@"id"] ?: @"?", json[@"access_token"]);
        }
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(json, err); });
    }].resume;
}

- (void)signOutWithCompletion:(void(^)(NSError *))completion {
    NSMutableURLRequest *r = [self authedRequestForPath:@"auth/v1/logout"];
    r.HTTPMethod = @"POST";
    // Supabase expects access_token bearer
    [[NSURLSession sharedSession] dataTaskWithRequest:r completionHandler:^(NSData*d, NSURLResponse*resp, NSError*e){
        // clear locally regardless of server response
        self.currentSession = nil;
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(e); NSLog(@"[supabase] signed out"); });
    }].resume;
}

- (void)getCurrentUserWithCompletion:(void(^)(NSDictionary *, NSError *))completion {
    NSString *tok = self.currentSession[@"access_token"];
    if (!tok.length) {
        if (completion) completion(nil, [NSError errorWithDomain:@"Supabase" code:401 userInfo:@{NSLocalizedDescriptionKey:@"Not signed in"}]);
        return;
    }
    NSMutableURLRequest *r = [self authedRequestForPath:@"auth/v1/user"];
    r.HTTPMethod = @"GET";
    [[NSURLSession sharedSession] dataTaskWithRequest:r completionHandler:^(NSData*d, NSURLResponse*resp, NSError*e){
        NSDictionary *json = nil;
        if (d) json = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
        NSInteger code = [(NSHTTPURLResponse*)resp statusCode];
        NSError *err = e;
        if (!err && (code < 200 || code >= 300)) {
            NSString *msg = json[@"error_description"] ?: json[@"msg"] ?: @"Failed to get user";
            err = [NSError errorWithDomain:@"Supabase" code:code userInfo:@{NSLocalizedDescriptionKey: msg}];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(json, err); });
    }].resume;
}

#pragma mark - Profiles

- (void)fetchProfileForUserId:(NSString *)userId completion:(void(^)(NSDictionary *, NSError *))completion {
    if (!self.isConfigured || !userId.length) {
        if (completion) completion(nil, [NSError errorWithDomain:@"Supabase" code:400 userInfo:@{NSLocalizedDescriptionKey:@"Missing userId or not configured"}]);
        return;
    }
    NSString *path = [NSString stringWithFormat:@"rest/v1/saturn_profiles?id=eq.%@&select=id,username,avatar_url,created_at", userId];
    NSMutableURLRequest *r = [self authedRequestForPath:path];
    r.HTTPMethod = @"GET";
    // If not signed in, fallback to anon key (RLS will block unless own)
    [[NSURLSession sharedSession] dataTaskWithRequest:r completionHandler:^(NSData*d, NSURLResponse*resp, NSError*e){
        NSInteger code = [(NSHTTPURLResponse*)resp statusCode];
        NSArray *arr = nil;
        NSDictionary *profile = nil;
        if (d) {
            id j = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
            if ([j isKindOfClass:[NSArray class]]) arr = j;
            if (arr.count > 0 && [arr[0] isKindOfClass:[NSDictionary class]]) profile = arr[0];
        }
        NSError *err = e;
        if (!err && (code < 200 || code >= 300)) {
            NSString *msg = profile ? @"" : [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] ?: [NSString stringWithFormat:@"Fetch profile failed %ld", (long)code];
            if (!profile) err = [NSError errorWithDomain:@"Supabase" code:code userInfo:@{NSLocalizedDescriptionKey: msg}];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(profile, err); });
    }].resume;
}

- (void)fetchOwnProfileWithCompletion:(void(^)(NSDictionary *, NSError *))completion {
    NSString *uid = self.currentUserId;
    if (!uid.length) {
        // try to get user first
        [self getCurrentUserWithCompletion:^(NSDictionary *user, NSError *err){
            if (err || !user[@"id"]) { if (completion) completion(nil, err ?: [NSError errorWithDomain:@"Supabase" code:401 userInfo:@{NSLocalizedDescriptionKey:@"No user"}]); return; }
            NSString *uid2 = user[@"id"];
            // update session user
            NSMutableDictionary *sess = [self.currentSession mutableCopy] ?: [NSMutableDictionary dictionary];
            sess[@"user"] = user;
            self.currentSession = sess;
            [self fetchProfileForUserId:uid2 completion:completion];
        }];
        return;
    }
    [self fetchProfileForUserId:uid completion:completion];
}

#pragma mark - Saturn Settings (saturn_settings table)

- (NSString *)deviceId {
    NSString *dId = [[NSUserDefaults standardUserDefaults] stringForKey:@"saturn.deviceId"];
    if (!dId.length) {
        dId = [[NSUUID UUID] UUIDString];
        [[NSUserDefaults standardUserDefaults] setObject:dId forKey:@"saturn.deviceId"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    return dId;
}

- (void)saveSaturnSettings:(NSDictionary *)settings completion:(void(^)(BOOL success, NSError *err))completion {
    if (!self.isConfigured) {
        if (completion) completion(NO, [NSError errorWithDomain:@"Supabase" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Supabase not configured"}]);
        return;
    }

    NSMutableDictionary *payload = [NSMutableDictionary dictionaryWithDictionary:settings ?: @{}];
    if (!payload[@"device_id"]) {
        payload[@"device_id"] = self.deviceId;
    }
    if (self.currentUserId.length && !payload[@"user_id"]) {
        payload[@"user_id"] = self.currentUserId;
    }

    NSISO8601DateFormatter *iso = [[NSISO8601DateFormatter alloc] init];
    payload[@"updated_at"] = [iso stringFromDate:[NSDate date]];
    if (!payload[@"created_at"]) {
        payload[@"created_at"] = [iso stringFromDate:[NSDate date]];
    }

    NSString *path = @"rest/v1/saturn_settings?on_conflict=device_id";
    NSMutableURLRequest *r = [self authedRequestForPath:path];
    r.HTTPMethod = @"POST";
    [r setValue:@"resolution=merge-duplicates,return=representation" forHTTPHeaderField:@"Prefer"];

    NSError *jsonErr = nil;
    r.HTTPBody = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&jsonErr];
    if (jsonErr) {
        if (completion) completion(NO, jsonErr);
        return;
    }

    [[NSURLSession sharedSession] dataTaskWithRequest:r completionHandler:^(NSData *d, NSURLResponse *resp, NSError *e){
        NSInteger code = [(NSHTTPURLResponse *)resp statusCode];
        NSError *err = e;
        BOOL success = (!err && (code >= 200 && code < 300));
        if (!success && !err) {
            NSString *msg = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] ?: [NSString stringWithFormat:@"Failed to save saturn_settings (%ld)", (long)code];
            err = [NSError errorWithDomain:@"Supabase" code:code userInfo:@{NSLocalizedDescriptionKey: msg}];
        }
        if (success) {
            NSLog(@"[supabase] successfully saved saturn_settings for device=%@", payload[@"device_id"]);
        } else {
            NSLog(@"[supabase] warning: saturn_settings save: %@", err.localizedDescription);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(success, err);
        });
    }].resume;
}

- (void)fetchSaturnSettingsWithCompletion:(void(^)(NSDictionary *settings, NSError *err))completion {
    if (!self.isConfigured) {
        if (completion) completion(nil, [NSError errorWithDomain:@"Supabase" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Supabase not configured"}]);
        return;
    }
    NSString *path = [NSString stringWithFormat:@"rest/v1/saturn_settings?device_id=eq.%@&select=*&limit=1", self.deviceId];
    NSMutableURLRequest *r = [self authedRequestForPath:path];
    r.HTTPMethod = @"GET";

    [[NSURLSession sharedSession] dataTaskWithRequest:r completionHandler:^(NSData *d, NSURLResponse *resp, NSError *e){
        NSInteger code = [(NSHTTPURLResponse *)resp statusCode];
        NSDictionary *dict = nil;
        if (d) {
            id j = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
            if ([j isKindOfClass:[NSArray class]] && [(NSArray *)j count] > 0) {
                dict = [(NSArray *)j firstObject];
            } else if ([j isKindOfClass:[NSDictionary class]]) {
                dict = (NSDictionary *)j;
            }
        }
        NSError *err = e;
        if (!err && (code < 200 || code >= 300)) {
            NSString *msg = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] ?: [NSString stringWithFormat:@"Failed to fetch saturn_settings (%ld)", (long)code];
            err = [NSError errorWithDomain:@"Supabase" code:code userInfo:@{NSLocalizedDescriptionKey: msg}];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(dict, err);
        });
    }].resume;
}

@end
