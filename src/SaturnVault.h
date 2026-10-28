#pragma once
#import <Foundation/Foundation.h>

// Posted on the main thread when the vault is created, locked, unlocked or its entries change.
extern NSNotificationName const SaturnVaultChangedNotification;

typedef NS_ENUM(NSInteger, SaturnVaultSaveResult) {
    SaturnVaultSaveAdded,
    SaturnVaultSaveUpdated,
    SaturnVaultSaveUnchanged,
    SaturnVaultSaveFailed,       // vault is locked or does not exist
};

// Yavqo Vault: logins encrypted on this Mac. One master password; nothing is sent anywhere.
// File: ~/Library/Application Support/Saturn/vault.json  (AES-256-CBC + HMAC-SHA256, keys from PBKDF2-SHA256).
// Each entry is {id, title, url, username, password, notes, created, modified}.
@interface SaturnVault : NSObject
+ (instancetype)shared;

@property (nonatomic, readonly) BOOL exists;      // a vault file is present
@property (nonatomic, readonly) BOOL unlocked;
@property (nonatomic, readonly) NSArray<NSDictionary *> *entries;   // sorted by title; empty while locked

- (void)createWithMasterPassword:(NSString *)password completion:(void (^)(BOOL ok))completion;
- (void)unlockWithMasterPassword:(NSString *)password completion:(void (^)(BOOL ok))completion;
- (void)lock;

// Entries whose saved site matches the page host (exact host, or the page is a subdomain of the saved site).
- (NSArray<NSDictionary *> *)entriesForHost:(NSString *)host;
- (NSDictionary *)entryWithID:(NSString *)entryID;
- (NSString *)addEntry:(NSDictionary *)entry;                   // returns the new id, nil when locked
- (BOOL)updateEntry:(NSDictionary *)entry;                      // matched by entry[@"id"]
- (BOOL)deleteEntryID:(NSString *)entryID;
- (SaturnVaultSaveResult)saveLoginForURLString:(NSString *)urlString username:(NSString *)username password:(NSString *)password;
- (SaturnVaultSaveResult)resultOfSavingLoginForURLString:(NSString *)urlString username:(NSString *)username password:(NSString *)password;   // dry run
- (NSInteger)importCSVText:(NSString *)csv;                     // Chrome, Safari, 1Password style exports; returns count added, -1 when locked

// Hosts the user chose "Never for this site" for.
- (BOOL)neverSavesHost:(NSString *)host;
- (void)setNeverSaves:(BOOL)never host:(NSString *)host;

// How many other entries use this exact password.
- (NSInteger)reuseCountForPassword:(NSString *)password excludingID:(NSString *)entryID;

+ (NSString *)hostForURLString:(NSString *)urlString;           // lower case, no "www."; nil when it has none
+ (NSString *)generatePasswordWithLength:(NSInteger)length digits:(BOOL)digits symbols:(BOOL)symbols;
// 0 very weak … 4 excellent. label is e.g. "Strong".
+ (NSInteger)strengthOfPassword:(NSString *)password label:(NSString **)label;
// Asks haveibeenpwned.com with a 5-character hash prefix only (k-anonymity); the password never leaves this Mac.
+ (void)checkBreachCountForPassword:(NSString *)password completion:(void (^)(NSInteger count, NSError *error))completion;
// Copies without leaving it in clipboard history (concealed) and clears it after 30 seconds if unchanged.
+ (void)copySecret:(NSString *)text;
@end
