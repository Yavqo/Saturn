#import "SaturnVault.h"
#import <AppKit/AppKit.h>
#import <CommonCrypto/CommonCrypto.h>
#import <CommonCrypto/CommonKeyDerivation.h>
#import <Security/Security.h>

NSNotificationName const SaturnVaultChangedNotification = @"SaturnVaultChanged";

static const uint32_t kPBKDF2Rounds = 600000;
static const NSTimeInterval kAutoLockSeconds = 5 * 60;
static NSString *const kNeverHostsKey = @"saturn.vault.neverHosts";

static NSString *VaultPath(void) {
    NSString *base = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    NSString *dir = [base stringByAppendingPathComponent:@"Saturn"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0700} error:nil];
    return [dir stringByAppendingPathComponent:@"vault.json"];
}

static NSData *RandomBytes(size_t n) {
    NSMutableData *d = [NSMutableData dataWithLength:n];
    if (SecRandomCopyBytes(kSecRandomDefault, n, d.mutableBytes) != errSecSuccess) arc4random_buf(d.mutableBytes, n);
    return d;
}

static BOOL ConstantTimeEqual(NSData *a, NSData *b) {
    if (a.length != b.length) return NO;
    const uint8_t *x = (const uint8_t *)a.bytes, *y = (const uint8_t *)b.bytes;
    uint8_t diff = 0;
    for (NSUInteger i = 0; i < a.length; i++) diff |= x[i] ^ y[i];
    return diff == 0;
}

static NSData *HMAC256(NSData *key, NSData *iv, NSData *ct) {
    CCHmacContext ctx;
    CCHmacInit(&ctx, kCCHmacAlgSHA256, key.bytes, key.length);
    CCHmacUpdate(&ctx, iv.bytes, iv.length);
    CCHmacUpdate(&ctx, ct.bytes, ct.length);
    NSMutableData *out = [NSMutableData dataWithLength:CC_SHA256_DIGEST_LENGTH];
    CCHmacFinal(&ctx, out.mutableBytes);
    return out;
}

// 64 bytes: first 32 encrypt, last 32 authenticate.
static NSData *DeriveKeys(NSString *password, NSData *salt, uint32_t rounds) {
    NSData *pw = [password dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *out = [NSMutableData dataWithLength:64];
    int rc = CCKeyDerivationPBKDF(kCCPBKDF2, (const char *)pw.bytes, pw.length, (const uint8_t *)salt.bytes, salt.length, kCCPRFHmacAlgSHA256, rounds, (uint8_t *)out.mutableBytes, out.length);
    return rc == kCCSuccess ? out : nil;
}

static NSData *AESCrypt(CCOperation op, NSData *key, NSData *iv, NSData *input) {
    size_t outLen = 0;
    NSMutableData *out = [NSMutableData dataWithLength:input.length + kCCBlockSizeAES128];
    CCCryptorStatus st = CCCrypt(op, kCCAlgorithmAES, kCCOptionPKCS7Padding, key.bytes, key.length, iv.bytes, input.bytes, input.length, out.mutableBytes, out.length, &outLen);
    if (st != kCCSuccess) return nil;
    out.length = outLen;
    return out;
}

static NSString *Trim(NSString *s) { return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @""; }

@implementation SaturnVault {
    NSMutableArray<NSMutableDictionary *> *_entries;
    NSMutableData *_keys;     // 64 bytes while unlocked
    NSData *_salt;
    uint32_t _rounds;
    NSTimer *_lockTimer;
    BOOL _busy;
}

+ (instancetype)shared {
    static SaturnVault *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[SaturnVault alloc] init]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _entries = [NSMutableArray array];
    // Lock when the Mac sleeps or the screen locks.
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(lock) name:NSWorkspaceWillSleepNotification object:nil];
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(lock) name:@"com.apple.screenIsLocked" object:nil];
    return self;
}

- (BOOL)exists { return [[NSFileManager defaultManager] fileExistsAtPath:VaultPath()]; }
- (BOOL)unlocked { return _keys != nil; }

- (NSArray<NSDictionary *> *)entries {
    if (!_keys) return @[];
    [self touch];
    return [_entries sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"title"] localizedCaseInsensitiveCompare:b[@"title"]];
    }];
}

#pragma mark Lock state

- (void)touch {
    [_lockTimer invalidate];
    if (!_keys) return;
    __weak typeof(self) weakSelf = self;
    _lockTimer = [NSTimer scheduledTimerWithTimeInterval:kAutoLockSeconds repeats:NO block:^(NSTimer *t) { (void)t; [weakSelf lock]; }];
}

- (void)lock {
    if (![NSThread isMainThread]) { dispatch_async(dispatch_get_main_queue(), ^{ [self lock]; }); return; }
    if (!_keys) return;
    [_lockTimer invalidate]; _lockTimer = nil;
    [_keys resetBytesInRange:NSMakeRange(0, _keys.length)];
    _keys = nil;
    [_entries removeAllObjects];
    [[NSNotificationCenter defaultCenter] postNotificationName:SaturnVaultChangedNotification object:self];
}

#pragma mark Create and unlock

- (void)createWithMasterPassword:(NSString *)password completion:(void (^)(BOOL))completion {
    if (self.exists || password.length < 8 || _busy) { if (completion) completion(NO); return; }
    _busy = YES;
    NSData *salt = RandomBytes(16);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSData *k = DeriveKeys(password, salt, kPBKDF2Rounds);
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_busy = NO;
            if (!k) { if (completion) completion(NO); return; }
            self->_salt = salt;
            self->_rounds = kPBKDF2Rounds;
            self->_keys = [k mutableCopy];
            [self->_entries removeAllObjects];
            BOOL ok = [self persist];
            if (!ok) { [self->_keys resetBytesInRange:NSMakeRange(0, self->_keys.length)]; self->_keys = nil; }
            else [self touch];
            [[NSNotificationCenter defaultCenter] postNotificationName:SaturnVaultChangedNotification object:self];
            if (completion) completion(ok);
        });
    });
}

- (void)unlockWithMasterPassword:(NSString *)password completion:(void (^)(BOOL))completion {
    if (_keys) { if (completion) completion(YES); return; }
    NSData *file = [NSData dataWithContentsOfFile:VaultPath()];
    NSDictionary *j = file ? [NSJSONSerialization JSONObjectWithData:file options:0 error:nil] : nil;
    NSData *salt = [[NSData alloc] initWithBase64EncodedString:j[@"salt"] ?: @"" options:0];
    NSData *iv = [[NSData alloc] initWithBase64EncodedString:j[@"iv"] ?: @"" options:0];
    NSData *ct = [[NSData alloc] initWithBase64EncodedString:j[@"ct"] ?: @"" options:0];
    NSData *mac = [[NSData alloc] initWithBase64EncodedString:j[@"mac"] ?: @"" options:0];
    uint32_t rounds = (uint32_t)[j[@"rounds"] unsignedIntValue];
    if (!salt.length || !iv.length || !ct.length || !mac.length || rounds < 100000 || _busy) { if (completion) completion(NO); return; }
    _busy = YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSData *k = DeriveKeys(password, salt, rounds);
        NSArray *list = nil;
        if (k) {
            NSData *encKey = [k subdataWithRange:NSMakeRange(0, 32)];
            NSData *macKey = [k subdataWithRange:NSMakeRange(32, 32)];
            if (ConstantTimeEqual(HMAC256(macKey, iv, ct), mac)) {
                NSData *plain = AESCrypt(kCCDecrypt, encKey, iv, ct);
                id parsed = plain ? [NSJSONSerialization JSONObjectWithData:plain options:NSJSONReadingMutableContainers error:nil] : nil;
                if ([parsed isKindOfClass:[NSArray class]]) list = parsed;
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_busy = NO;
            if (!list) { if (completion) completion(NO); return; }
            self->_salt = salt;
            self->_rounds = rounds;
            self->_keys = [k mutableCopy];
            [self->_entries removeAllObjects];
            for (id e in list) if ([e isKindOfClass:[NSMutableDictionary class]]) [self->_entries addObject:e];
            [self touch];
            [[NSNotificationCenter defaultCenter] postNotificationName:SaturnVaultChangedNotification object:self];
            if (completion) completion(YES);
        });
    });
}

- (BOOL)persist {
    if (!_keys) return NO;
    NSData *plain = [NSJSONSerialization dataWithJSONObject:_entries options:0 error:nil];
    if (!plain) return NO;
    NSData *encKey = [_keys subdataWithRange:NSMakeRange(0, 32)];
    NSData *macKey = [_keys subdataWithRange:NSMakeRange(32, 32)];
    NSData *iv = RandomBytes(16);
    NSData *ct = AESCrypt(kCCEncrypt, encKey, iv, plain);
    if (!ct) return NO;
    NSDictionary *file = @{@"v": @1, @"rounds": @(_rounds), @"salt": [_salt base64EncodedStringWithOptions:0],
                           @"iv": [iv base64EncodedStringWithOptions:0], @"ct": [ct base64EncodedStringWithOptions:0],
                           @"mac": [HMAC256(macKey, iv, ct) base64EncodedStringWithOptions:0]};
    NSData *out = [NSJSONSerialization dataWithJSONObject:file options:0 error:nil];
    NSString *path = VaultPath();
    if (![out writeToFile:path options:NSDataWritingAtomic error:nil]) return NO;
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0600} ofItemAtPath:path error:nil];
    return YES;
}

- (void)changed {
    [self persist];
    [self touch];
    [[NSNotificationCenter defaultCenter] postNotificationName:SaturnVaultChangedNotification object:self];
}

#pragma mark Entries

- (NSDictionary *)entryWithID:(NSString *)entryID {
    for (NSDictionary *e in _entries) if ([e[@"id"] isEqualToString:entryID]) return e;
    return nil;
}

- (NSMutableDictionary *)normalized:(NSDictionary *)src {
    NSMutableDictionary *e = [NSMutableDictionary dictionary];
    NSString *url = Trim(src[@"url"] ?: @"");
    NSString *title = Trim(src[@"title"] ?: @"");
    if (!title.length) title = [SaturnVault hostForURLString:url] ?: @"Untitled";
    e[@"title"] = title;
    e[@"url"] = url;
    e[@"username"] = Trim(src[@"username"] ?: @"");
    e[@"password"] = src[@"password"] ?: @"";
    e[@"notes"] = src[@"notes"] ?: @"";
    return e;
}

- (NSString *)addEntry:(NSDictionary *)entry {
    if (!_keys) return nil;
    NSMutableDictionary *e = [self normalized:entry];
    NSNumber *now = @([[NSDate date] timeIntervalSince1970]);
    e[@"id"] = [[NSUUID UUID] UUIDString];
    e[@"created"] = now; e[@"modified"] = now;
    [_entries addObject:e];
    [self changed];
    return e[@"id"];
}

- (BOOL)updateEntry:(NSDictionary *)entry {
    if (!_keys) return NO;
    NSMutableDictionary *old = nil;
    for (NSMutableDictionary *e in _entries) if ([e[@"id"] isEqualToString:entry[@"id"]]) { old = e; break; }
    if (!old) return NO;
    NSMutableDictionary *n = [self normalized:entry];
    n[@"id"] = old[@"id"]; n[@"created"] = old[@"created"] ?: @0;
    n[@"modified"] = @([[NSDate date] timeIntervalSince1970]);
    NSUInteger i = [_entries indexOfObject:old];
    _entries[i] = n;
    [self changed];
    return YES;
}

- (BOOL)deleteEntryID:(NSString *)entryID {
    if (!_keys) return NO;
    NSDictionary *e = [self entryWithID:entryID];
    if (!e) return NO;
    [_entries removeObject:e];
    [self changed];
    return YES;
}

- (NSArray<NSDictionary *> *)entriesForHost:(NSString *)host {
    NSString *h = [SaturnVault hostForURLString:host];
    if (!h.length || !_keys) return @[];
    [self touch];
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *e in _entries) {
        NSString *eh = [SaturnVault hostForURLString:e[@"url"]];
        if (!eh.length) continue;
        if ([h isEqualToString:eh] || [h hasSuffix:[@"." stringByAppendingString:eh]]) [out addObject:e];
    }
    return out;
}

- (NSMutableDictionary *)existingEntryForHost:(NSString *)host username:(NSString *)username {
    for (NSMutableDictionary *e in _entries) {
        NSString *eh = [SaturnVault hostForURLString:e[@"url"]];
        if ([eh isEqualToString:host] && [[e[@"username"] lowercaseString] isEqualToString:[username lowercaseString]]) return e;
    }
    return nil;
}

- (SaturnVaultSaveResult)resultOfSavingLoginForURLString:(NSString *)urlString username:(NSString *)username password:(NSString *)password {
    if (!_keys) return SaturnVaultSaveFailed;
    NSString *host = [SaturnVault hostForURLString:urlString];
    NSMutableDictionary *e = host ? [self existingEntryForHost:host username:Trim(username)] : nil;
    if (!e) return SaturnVaultSaveAdded;
    return [e[@"password"] isEqualToString:password] ? SaturnVaultSaveUnchanged : SaturnVaultSaveUpdated;
}

- (SaturnVaultSaveResult)saveLoginForURLString:(NSString *)urlString username:(NSString *)username password:(NSString *)password {
    SaturnVaultSaveResult r = [self resultOfSavingLoginForURLString:urlString username:username password:password];
    NSString *host = [SaturnVault hostForURLString:urlString];
    if (r == SaturnVaultSaveAdded) {
        NSURL *u = [NSURL URLWithString:urlString];
        NSString *site = u.host ? [NSString stringWithFormat:@"%@://%@", u.scheme ?: @"https", u.host] : urlString;
        [self addEntry:@{@"title": host ?: @"", @"url": site, @"username": username ?: @"", @"password": password}];
    } else if (r == SaturnVaultSaveUpdated) {
        NSMutableDictionary *e = [[self existingEntryForHost:host username:Trim(username)] mutableCopy];
        e[@"password"] = password;
        [self updateEntry:e];
    }
    return r;
}

- (NSInteger)reuseCountForPassword:(NSString *)password excludingID:(NSString *)entryID {
    if (!password.length || !_keys) return 0;
    NSInteger n = 0;
    for (NSDictionary *e in _entries) if (![e[@"id"] isEqualToString:entryID] && [e[@"password"] isEqualToString:password]) n++;
    return n;
}

#pragma mark Never for this site

- (BOOL)neverSavesHost:(NSString *)host {
    NSString *h = [SaturnVault hostForURLString:host];
    return h && [[[NSUserDefaults standardUserDefaults] arrayForKey:kNeverHostsKey] containsObject:h];
}
- (void)setNeverSaves:(BOOL)never host:(NSString *)host {
    NSString *h = [SaturnVault hostForURLString:host];
    if (!h) return;
    NSMutableArray *list = [[[NSUserDefaults standardUserDefaults] arrayForKey:kNeverHostsKey] mutableCopy] ?: [NSMutableArray array];
    if (never && ![list containsObject:h]) [list addObject:h];
    if (!never) [list removeObject:h];
    [[NSUserDefaults standardUserDefaults] setObject:list forKey:kNeverHostsKey];
}

#pragma mark CSV import

static NSArray<NSArray<NSString *> *> *ParseCSV(NSString *text) {
    NSMutableArray *rows = [NSMutableArray array];
    NSMutableArray *row = [NSMutableArray array];
    NSMutableString *field = [NSMutableString string];
    BOOL quoted = NO;
    NSUInteger n = text.length;
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [text characterAtIndex:i];
        if (quoted) {
            if (c == '"') {
                if (i + 1 < n && [text characterAtIndex:i + 1] == '"') { [field appendString:@"\""]; i++; }
                else quoted = NO;
            } else [field appendFormat:@"%C", c];
        } else if (c == '"') quoted = YES;
        else if (c == ',') { [row addObject:[field copy]]; [field setString:@""]; }
        else if (c == '\n' || c == '\r') {
            if (c == '\r' && i + 1 < n && [text characterAtIndex:i + 1] == '\n') i++;
            [row addObject:[field copy]]; [field setString:@""];
            if (row.count > 1 || [row[0] length]) [rows addObject:row];
            row = [NSMutableArray array];
        } else [field appendFormat:@"%C", c];
    }
    if (field.length || row.count) { [row addObject:[field copy]]; [rows addObject:row]; }
    return rows;
}

- (NSInteger)importCSVText:(NSString *)csv {
    if (!_keys) return -1;
    NSArray *rows = ParseCSV(csv);
    if (rows.count < 2) return 0;
    NSArray *head = rows[0];
    NSInteger iTitle = -1, iURL = -1, iUser = -1, iPass = -1, iNotes = -1;
    for (NSUInteger i = 0; i < head.count; i++) {
        NSString *h = [Trim(head[i]) lowercaseString];
        if (iTitle < 0 && ([h isEqualToString:@"name"] || [h isEqualToString:@"title"])) iTitle = i;
        else if (iURL < 0 && ([h isEqualToString:@"url"] || [h isEqualToString:@"website"] || [h isEqualToString:@"login_uri"])) iURL = i;
        else if (iUser < 0 && ([h isEqualToString:@"username"] || [h isEqualToString:@"login_username"] || [h isEqualToString:@"user"])) iUser = i;
        else if (iPass < 0 && ([h isEqualToString:@"password"] || [h isEqualToString:@"login_password"])) iPass = i;
        else if (iNotes < 0 && ([h isEqualToString:@"note"] || [h isEqualToString:@"notes"])) iNotes = i;
    }
    if (iPass < 0 || (iURL < 0 && iTitle < 0)) return 0;
    NSInteger added = 0;
    for (NSUInteger r = 1; r < [rows count]; r++) {
        NSArray *row = rows[r];
        NSString *(^cell)(NSInteger) = ^NSString *(NSInteger i) { return (i >= 0 && i < (NSInteger)row.count) ? row[i] : @""; };
        NSString *pass = cell(iPass);
        if (!pass.length) continue;
        NSString *url = cell(iURL), *user = cell(iUser);
        NSString *host = [SaturnVault hostForURLString:url];
        if (host && [self existingEntryForHost:host username:Trim(user)] && [[self existingEntryForHost:host username:Trim(user)][@"password"] isEqualToString:pass]) continue;
        NSMutableDictionary *e = [self normalized:@{@"title": cell(iTitle), @"url": url, @"username": user, @"password": pass, @"notes": cell(iNotes)}];
        NSNumber *now = @([[NSDate date] timeIntervalSince1970]);
        e[@"id"] = [[NSUUID UUID] UUIDString]; e[@"created"] = now; e[@"modified"] = now;
        [_entries addObject:e];
        added++;
    }
    if (added) [self changed];
    return added;
}

#pragma mark Helpers

+ (NSString *)hostForURLString:(NSString *)urlString {
    NSString *s = Trim(urlString ?: @"");
    if (!s.length) return nil;
    if (![s containsString:@"://"]) s = [@"https://" stringByAppendingString:s];
    NSString *h = [NSURL URLWithString:s].host.lowercaseString;
    if ([h hasPrefix:@"www."]) h = [h substringFromIndex:4];
    return h.length ? h : nil;
}

+ (NSString *)generatePasswordWithLength:(NSInteger)length digits:(BOOL)digits symbols:(BOOL)symbols {
    length = MAX(8, MIN(64, length));
    NSMutableArray<NSString *> *sets = [NSMutableArray arrayWithObjects:@"abcdefghijkmnopqrstuvwxyz", @"ABCDEFGHJKLMNPQRSTUVWXYZ", nil];   // no l, I, O: easy to misread
    if (digits) [sets addObject:@"23456789"];
    if (symbols) [sets addObject:@"!@#$%^&*-_=+?"];
    NSString *all = [sets componentsJoinedByString:@""];
    NSMutableArray<NSString *> *chars = [NSMutableArray array];
    for (NSString *set in sets) [chars addObject:[set substringWithRange:NSMakeRange(arc4random_uniform((uint32_t)set.length), 1)]];   // one of each class
    while ((NSInteger)chars.count < length) [chars addObject:[all substringWithRange:NSMakeRange(arc4random_uniform((uint32_t)all.length), 1)]];
    for (NSInteger i = (NSInteger)chars.count - 1; i > 0; i--) [chars exchangeObjectAtIndex:i withObjectAtIndex:arc4random_uniform((uint32_t)i + 1)];
    return [chars componentsJoinedByString:@""];
}

+ (NSInteger)strengthOfPassword:(NSString *)p label:(NSString **)label {
    static NSArray *common;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ common = @[@"password", @"123456", @"12345678", @"qwerty", @"letmein", @"welcome", @"admin", @"iloveyou", @"abc123", @"111111", @"monkey", @"dragon", @"passw0rd"]; });
    NSString *lower = p.lowercaseString;
    double pool = 0;
    if ([p rangeOfCharacterFromSet:[NSCharacterSet lowercaseLetterCharacterSet]].length) pool += 26;
    if ([p rangeOfCharacterFromSet:[NSCharacterSet uppercaseLetterCharacterSet]].length) pool += 26;
    if ([p rangeOfCharacterFromSet:[NSCharacterSet decimalDigitCharacterSet]].length) pool += 10;
    if ([p rangeOfCharacterFromSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]].length) pool += 33;
    double bits = pool > 0 ? p.length * log2(pool) : 0;
    NSMutableSet *unique = [NSMutableSet set];
    for (NSUInteger i = 0; i < p.length; i++) [unique addObject:@([p characterAtIndex:i])];
    if (p.length && unique.count * 2 < p.length) bits *= 0.6;
    for (NSString *c in common) if ([lower containsString:c]) { bits = MIN(bits, 20); break; }
    NSInteger score = bits < 28 ? 0 : bits < 40 ? 1 : bits < 60 ? 2 : bits < 80 ? 3 : 4;
    if (!p.length) score = 0;
    if (label) *label = @[@"Very weak", @"Weak", @"Okay", @"Strong", @"Excellent"][score];
    return score;
}

+ (void)checkBreachCountForPassword:(NSString *)password completion:(void (^)(NSInteger, NSError *))completion {
    NSData *pw = [password dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(pw.bytes, (CC_LONG)pw.length, digest);
    NSMutableString *hex = [NSMutableString string];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) [hex appendFormat:@"%02X", digest[i]];
    NSString *prefix = [hex substringToIndex:5], *suffix = [hex substringFromIndex:5];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[@"https://api.pwnedpasswords.com/range/" stringByAppendingString:prefix]]];
    req.timeoutInterval = 15;
    [req setValue:@"true" forHTTPHeaderField:@"Add-Padding"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSInteger count = 0;
        NSError *outErr = err;
        NSInteger code = [(NSHTTPURLResponse *)resp statusCode];
        if (!err && (code < 200 || code >= 300 || !data)) outErr = [NSError errorWithDomain:@"YavqoVault" code:code userInfo:@{NSLocalizedDescriptionKey: @"The breach check is not available right now."}];
        if (!outErr) {
            NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            for (NSString *line in [body componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
                NSArray *parts = [line componentsSeparatedByString:@":"];
                if (parts.count == 2 && [[Trim(parts[0]) uppercaseString] isEqualToString:suffix]) { count = [Trim(parts[1]) integerValue]; break; }
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(count, outErr); });
    }] resume];
}

+ (void)copySecret:(NSString *)text {
    if (!text.length) return;
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    NSPasteboardItem *item = [[NSPasteboardItem alloc] init];
    [item setString:text forType:NSPasteboardTypeString];
    [item setData:[NSData data] forType:@"org.nspasteboard.ConcealedType"];
    [pb writeObjects:@[item]];
    NSInteger cc = pb.changeCount;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if ([NSPasteboard generalPasteboard].changeCount == cc) [[NSPasteboard generalPasteboard] clearContents];
    });
}

@end
