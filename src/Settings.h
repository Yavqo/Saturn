#pragma once
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SaturnSearchEngine) {
    SaturnSearchEngineGoogle = 0,
    SaturnSearchEngineBing,
    SaturnSearchEngineDuckDuckGo,
    SaturnSearchEngineBrave,
    SaturnSearchEngineYahoo,
    SaturnSearchEngineEcosia,
    SaturnSearchEngineCustom,
};

@interface SaturnSearchEngineInfo : NSObject
@property (nonatomic, assign) SaturnSearchEngine engine;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *shortName; // for placeholder
@property (nonatomic, copy) NSString *templateURL; // contains %s for query
@property (nonatomic, copy) NSString *homeURL;
@property (nonatomic, copy) NSString *iconSymbol; // SF Symbol
+ (NSArray<SaturnSearchEngineInfo*>*)allEngines;
+ (SaturnSearchEngineInfo*)infoForEngine:(SaturnSearchEngine)engine;
+ (SaturnSearchEngineInfo*)infoForName:(NSString*)name;
@end

@interface SaturnSettings : NSObject
+ (instancetype)shared;
@property (nonatomic, assign) BOOL hasCompletedSetup;
@property (nonatomic, assign) SaturnSearchEngine defaultEngine;
@property (nonatomic, copy) NSString *customTemplate; // when engine == Custom
@property (nonatomic, readonly) SaturnSearchEngineInfo *currentEngineInfo;
- (NSString *)searchURLForQuery:(NSString *)query;
- (void)save;
- (void)load;
- (void)syncToSupabaseWithCompletion:(void(^)(BOOL success, NSError *err))completion;
- (void)syncFromSupabaseWithCompletion:(void(^)(BOOL success, NSError *err))completion;
@end
