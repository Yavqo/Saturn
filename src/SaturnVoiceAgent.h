#pragma once
#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>
#import <Speech/Speech.h>

typedef NS_ENUM(NSInteger, SaturnVoiceAgentState) {
    SaturnVoiceAgentStateIdle,
    SaturnVoiceAgentStateListening,
    SaturnVoiceAgentStateProcessing,
    SaturnVoiceAgentStateSpeaking
};

@protocol SaturnVoiceAgentDelegate <NSObject>
@optional
- (void)voiceAgentDidChangeState:(SaturnVoiceAgentState)state statusMessage:(NSString *)status;
- (void)voiceAgentDidUpdateLiveTranscript:(NSString *)transcript;
- (void)voiceAgentDidUpdateAudioLevel:(CGFloat)level; // 0.0 to 1.0
- (void)voiceAgentDidFinishWithUserText:(NSString *)userText replyText:(NSString *)replyText;
- (void)voiceAgentDidFailWithError:(NSError *)error;
@end

@interface SaturnVoiceAgent : NSObject

+ (instancetype)shared;

@property (nonatomic, weak) id<SaturnVoiceAgentDelegate> delegate;
@property (nonatomic, readonly) SaturnVoiceAgentState state;
@property (nonatomic, readonly) BOOL isListening;
@property (nonatomic, readonly) BOOL isSpeaking;
@property (nonatomic, copy) NSString *openRouterApiKey;
@property (nonatomic, copy) NSString *modelName; // defaults to "z-ai/glm-5.3-flash-free"
@property (nonatomic, copy) NSString *voiceId; // defaults to "5233336f5f44460ea0902b0802375451"

- (void)startListeningWithBrowserContext:(NSString *)context;
- (void)stopListeningAndSend;
- (void)cancel;
- (void)speakText:(NSString *)text completion:(void(^)(void))completion;
- (void)stopSpeaking;

@end
