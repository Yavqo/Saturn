#pragma once
#import <Foundation/Foundation.h>

@interface SupabaseClient : NSObject

+ (instancetype)shared;

- (void)configureWithURL:(NSString *)url anonKey:(NSString *)anonKey;
- (void)configureFromEnvironment;

@property (nonatomic, readonly) BOOL isConfigured;
@property (nonatomic, readonly, copy) NSString *supabaseURL;
@property (nonatomic, readonly, copy) NSString *anonKey;

// Session (stored in NSUserDefaults)
@property (nonatomic, readonly, copy) NSDictionary *currentSession; // { access_token, refresh_token, user: {id,email} }
@property (nonatomic, readonly, copy) NSString *currentUserId;
@property (nonatomic, readonly, copy) NSString *currentUserEmail;
- (BOOL)isSignedIn;
- (void)clearSession;

// Health
- (void)pingWithCompletion:(void(^)(BOOL success, NSError *error))completion;

// REST helpers
- (void)restGet:(NSString *)path completion:(void(^)(NSData *data, NSURLResponse *resp, NSError *err))completion;
- (void)restPost:(NSString *)path json:(NSDictionary *)json completion:(void(^)(NSData *data, NSURLResponse *resp, NSError *err))completion;

// Auth
- (void)signUpWithEmail:(NSString *)email password:(NSString *)password completion:(void(^)(NSDictionary *data, NSError *err))completion;
- (void)signInWithEmail:(NSString *)email password:(NSString *)password completion:(void(^)(NSDictionary *data, NSError *err))completion;
- (void)signOutWithCompletion:(void(^)(NSError *err))completion;
- (void)getCurrentUserWithCompletion:(void(^)(NSDictionary *user, NSError *err))completion;

// Profiles (saturn_profiles)
- (void)fetchProfileForUserId:(NSString *)userId completion:(void(^)(NSDictionary *profile, NSError *err))completion;
- (void)fetchOwnProfileWithCompletion:(void(^)(NSDictionary *profile, NSError *err))completion;

// Saturn Browser Settings & Setup (saturn_settings)
@property (nonatomic, readonly, copy) NSString *deviceId;
- (void)saveSaturnSettings:(NSDictionary *)settings completion:(void(^)(BOOL success, NSError *err))completion;
- (void)fetchSaturnSettingsWithCompletion:(void(^)(NSDictionary *settings, NSError *err))completion;

@end
