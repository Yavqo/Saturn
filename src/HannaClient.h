#pragma once
#import <Foundation/Foundation.h>

@interface HannaClient : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) BOOL isConfigured;
// Zarah's identity, voice and company facts. Prepended to every system prompt (chat, Act mode, voice).
+ (NSString *)personaPrompt;
- (void)sendMessage:(NSString *)userText
            history:(NSArray<NSDictionary*> *)history // array of {role, content}
         completion:(void(^)(NSString *reply, NSError *error))completion;
- (void)sendMessage:(NSString *)userText
            history:(NSArray<NSDictionary*> *)history
     browserContext:(NSString *)context // system context with current tabs/page
         completion:(void(^)(NSString *reply, NSError *error))completion;
// One chat-completions round with tools. `message` is the assistant message ({content, tool_calls}) as returned by the gateway.
- (void)chatWithMessages:(NSArray<NSDictionary *> *)messages
                  tools:(NSArray<NSDictionary *> *)tools
             completion:(void(^)(NSDictionary *message, NSError *error))completion;
@end
