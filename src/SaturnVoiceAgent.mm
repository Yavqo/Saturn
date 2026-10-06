#import "SaturnVoiceAgent.h"
#import "HannaClient.h"
#import <Accelerate/Accelerate.h>

@interface SaturnVoiceAgent () <SFSpeechRecognizerDelegate, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate>
@end

@implementation SaturnVoiceAgent {
    SFSpeechRecognizer *_speechRecognizer;
    SFSpeechAudioBufferRecognitionRequest *_recognitionRequest;
    SFSpeechRecognitionTask *_recognitionTask;
    AVAudioEngine *_audioEngine;
    AVSpeechSynthesizer *_speechSynthesizer;
    AVAudioPlayer *_audioPlayer;
    
    NSString *_currentBrowserContext;
    NSMutableString *_latestTranscription;
    NSTimer *_silenceTimer;
    SaturnVoiceAgentState _state;
}

+ (instancetype)shared {
    static SaturnVoiceAgent *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[SaturnVoiceAgent alloc] init]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _state = SaturnVoiceAgentStateIdle;
        _modelName = @"z-ai/glm-5.3-flash-free";
        _voiceId = @"5233336f5f44460ea0902b0802375451";
        _latestTranscription = [NSMutableString string];
        _speechSynthesizer = [[AVSpeechSynthesizer alloc] init];
        _speechSynthesizer.delegate = self;
        
        NSLocale *locale = [NSLocale localeWithLocaleIdentifier:@"en-US"];
        _speechRecognizer = [[SFSpeechRecognizer alloc] initWithLocale:locale];
        _speechRecognizer.delegate = self;
        
        [self loadApiKey];
    }
    return self;
}

- (void)loadApiKey {
    // 1. Env (Orcarouter first, then legacy fallbacks)
    NSString *k = [[[NSProcessInfo processInfo] environment] objectForKey:@"ORCAROUTER_API_KEY"];
    if (!k.length) k = [[[NSProcessInfo processInfo] environment] objectForKey:@"OPENROUTER_API_KEY"];
    NSString *vid = [[[NSProcessInfo processInfo] environment] objectForKey:@"FISH_AUDIO_VOICE_ID"];
    // 2. .env
    if (!k.length || !vid.length) {
        NSString *content = [NSString stringWithContentsOfFile:@"/Users/nacrosoft/Documents/YavqoSaturn/.env" encoding:NSUTF8StringEncoding error:nil];
        for (NSString *line in [content componentsSeparatedByString:@"\n"]) {
            NSString *t = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if ([t hasPrefix:@"ORCAROUTER_API_KEY="] && !k.length) {
                NSString *v = [[t substringFromIndex:[@"ORCAROUTER_API_KEY=" length]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                v = [v stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\"'"]];
                if (v.length) k = v;
            }
            if ([t hasPrefix:@"OPENROUTER_API_KEY="] && !k.length) {
                NSString *v = [[t substringFromIndex:[@"OPENROUTER_API_KEY=" length]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                v = [v stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\"'"]];
                if (v.length) k = v;
            }
            if (([t hasPrefix:@"FISH_AUDIO_VOICE_ID="] || [t hasPrefix:@"VOICE_ID="]) && !vid.length) {
                NSString *prefix = [t hasPrefix:@"FISH_AUDIO_VOICE_ID="] ? @"FISH_AUDIO_VOICE_ID=" : @"VOICE_ID=";
                NSString *v = [[t substringFromIndex:prefix.length] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                v = [v stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\"'"]];
                if (v.length) vid = v;
            }
        }
    }
    // 3. UserDefaults
    if (!k.length) {
        k = [[NSUserDefaults standardUserDefaults] stringForKey:@"saturn.orcarouter_api_key"];
    }
    if (!k.length) {
        k = [[NSUserDefaults standardUserDefaults] stringForKey:@"saturn.openrouter_api_key"];
    }
    // 4. Fallback to OpenCode/Zen API key if available
    if (!k.length) {
        k = [[[NSProcessInfo processInfo] environment] objectForKey:@"OPENCODE_API_KEY"];
    }
    _openRouterApiKey = [k copy];
    if (vid.length) _voiceId = [vid copy];
}

- (SaturnVoiceAgentState)state {
    return _state;
}

- (BOOL)isListening {
    return _state == SaturnVoiceAgentStateListening;
}

- (BOOL)isSpeaking {
    return _state == SaturnVoiceAgentStateSpeaking;
}

- (void)setState:(SaturnVoiceAgentState)newState statusMessage:(NSString *)status {
    _state = newState;
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(voiceAgentDidChangeState:statusMessage:)]) {
            [self.delegate voiceAgentDidChangeState:newState statusMessage:status];
        }
    });
}

#pragma mark - Voice Input & Speech Recognition

- (void)startListeningWithBrowserContext:(NSString *)context {
    [self cancel]; // clean up any previous session
    _currentBrowserContext = [context copy] ?: @"";
    [_latestTranscription setString:@""];

    [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus authStatus) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (authStatus != SFSpeechRecognizerAuthorizationStatusAuthorized) {
                [self setState:SaturnVoiceAgentStateIdle statusMessage:@"Speech recognition permission denied"];
                if ([self.delegate respondsToSelector:@selector(voiceAgentDidFailWithError:)]) {
                    NSError *err = [NSError errorWithDomain:@"SaturnVoiceAgent" code:403 userInfo:@{NSLocalizedDescriptionKey: @"Speech recognition permission required."}];
                    [self.delegate voiceAgentDidFailWithError:err];
                }
                return;
            }
            [self startAudioEngineAndRecognition];
        });
    }];
}

- (void)startAudioEngineAndRecognition {
    NSError *error = nil;
    _audioEngine = [[AVAudioEngine alloc] init];
    AVAudioInputNode *inputNode = _audioEngine.inputNode;
    if (!inputNode) {
        [self setState:SaturnVoiceAgentStateIdle statusMessage:@"Microphone not found"];
        return;
    }

    _recognitionRequest = [[SFSpeechAudioBufferRecognitionRequest alloc] init];
    _recognitionRequest.shouldReportPartialResults = YES;
    if (@available(macOS 10.15, *)) {
        _recognitionRequest.requiresOnDeviceRecognition = NO;
    }

    __weak typeof(self) weakSelf = self;
    _recognitionTask = [_speechRecognizer recognitionTaskWithRequest:_recognitionRequest resultHandler:^(SFSpeechRecognitionResult * _Nullable result, NSError * _Nullable err) {
        __strong typeof(weakSelf) s = weakSelf;
        if (!s) return;

        if (result) {
            NSString *transcription = result.bestTranscription.formattedString;
            [s->_latestTranscription setString:transcription];
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([s.delegate respondsToSelector:@selector(voiceAgentDidUpdateLiveTranscript:)]) {
                    [s.delegate voiceAgentDidUpdateLiveTranscript:transcription];
                }
            });
            [s resetSilenceTimer];
        }

        if (err || result.isFinal) {
            [s->_audioEngine stop];
            [inputNode removeTapOnBus:0];
            s->_recognitionRequest = nil;
            s->_recognitionTask = nil;
        }
    }];

    AVAudioFormat *recordingFormat = [inputNode outputFormatForBus:0];
    [inputNode installTapOnBus:0 bufferSize:1024 format:recordingFormat block:^(AVAudioPCMBuffer * _Nonnull buffer, AVAudioTime * _Nonnull when) {
        (void)when;
        __strong typeof(weakSelf) s = weakSelf;
        if (!s) return;
        
        [s->_recognitionRequest appendAudioPCMBuffer:buffer];

        // Compute RMS level for visualizer wave
        float rms = 0;
        if (buffer.floatChannelData && buffer.frameLength > 0) {
            float *channelData = buffer.floatChannelData[0];
            float sum = 0;
            for (uint32_t i = 0; i < buffer.frameLength; i++) {
                sum += channelData[i] * channelData[i];
            }
            rms = sqrtf(sum / (float)buffer.frameLength);
        }
        CGFloat normalized = MIN(1.0, MAX(0.0, rms * 15.0));
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([s.delegate respondsToSelector:@selector(voiceAgentDidUpdateAudioLevel:)]) {
                [s.delegate voiceAgentDidUpdateAudioLevel:normalized];
            }
        });
    }];

    [_audioEngine prepare];
    if (![_audioEngine startAndReturnError:&error]) {
        NSLog(@"[voice-agent] Audio engine failed to start: %@", error);
        [self setState:SaturnVoiceAgentStateIdle statusMessage:@"Audio input error"];
        return;
    }

    [self setState:SaturnVoiceAgentStateListening statusMessage:@"Listening..."];
}

- (void)resetSilenceTimer {
    [_silenceTimer invalidate];
    __weak typeof(self) weakSelf = self;
    _silenceTimer = [NSTimer scheduledTimerWithTimeInterval:2.2 repeats:NO block:^(NSTimer * _Nonnull timer) {
        (void)timer;
        __strong typeof(weakSelf) s = weakSelf;
        if (s && s.isListening && s->_latestTranscription.length > 0) {
            [s stopListeningAndSend];
        }
    }];
}

- (void)stopListeningAndSend {
    [_silenceTimer invalidate];
    _silenceTimer = nil;

    if (_audioEngine.isRunning) {
        [_audioEngine stop];
        [_audioEngine.inputNode removeTapOnBus:0];
    }
    [_recognitionRequest endAudio];

    NSString *userText = [_latestTranscription copy];
    if (!userText.length) {
        [self setState:SaturnVoiceAgentStateIdle statusMessage:@"No speech detected"];
        return;
    }

    [self setState:SaturnVoiceAgentStateProcessing statusMessage:@"Thinking (glm-5.3-flash)..."];
    [self queryOpenRouterWithText:userText];
}

- (void)cancel {
    [_silenceTimer invalidate];
    _silenceTimer = nil;

    if (_audioEngine.isRunning) {
        [_audioEngine stop];
        [_audioEngine.inputNode removeTapOnBus:0];
    }
    [_recognitionRequest endAudio];
    [_recognitionTask cancel];
    _recognitionRequest = nil;
    _recognitionTask = nil;

    [self stopSpeaking];
    [self setState:SaturnVoiceAgentStateIdle statusMessage:@"Ready"];
}

#pragma mark - Orcarouter LLM (z-ai/glm-5.3-flash-free)

- (void)queryOpenRouterWithText:(NSString *)userText {
    [self loadApiKey];
    NSString *apiKey = self.openRouterApiKey;
    if (!apiKey.length) apiKey = @"sk-or-v1-free"; // fallback test token

    NSMutableArray *messages = [NSMutableArray array];
    
    NSString *systemPrompt = [NSString stringWithFormat:@"%@\n\nYou are speaking aloud inside the Saturn browser. Keep your responses natural, conversational, concise (1-3 sentences), warm, and direct for speech synthesis. Use no markdown, bullet points or symbols.", [HannaClient personaPrompt]];
    if (_currentBrowserContext.length) {
        systemPrompt = [NSString stringWithFormat:@"%@\n\nBrowser context:\n%@", systemPrompt, _currentBrowserContext];
    }
    
    [messages addObject:@{@"role": @"system", @"content": systemPrompt}];
    [messages addObject:@{@"role": @"user", @"content": userText}];

    NSDictionary *body = @{
        @"model": self.modelName ?: @"z-ai/glm-5.3-flash-free",
        @"messages": messages,
        @"temperature": @0.7,
        @"max_tokens": @400
    };

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    NSURL *url = [NSURL URLWithString:@"https://api.orcarouter.ai/v1/chat/completions"];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    req.timeoutInterval = 30;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:[NSString stringWithFormat:@"Bearer %@", apiKey] forHTTPHeaderField:@"Authorization"];
    [req setValue:@"https://saturn.browser" forHTTPHeaderField:@"HTTP-Referer"];
    [req setValue:@"Saturn Browser" forHTTPHeaderField:@"X-Title"];
    req.HTTPBody = jsonData;

    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        __strong typeof(weakSelf) s = weakSelf;
        if (!s) return;

        if (err) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [s setState:SaturnVoiceAgentStateIdle statusMessage:@"Network error"];
                if ([s.delegate respondsToSelector:@selector(voiceAgentDidFailWithError:)]) {
                    [s.delegate voiceAgentDidFailWithError:err];
                }
            });
            return;
        }

        NSInteger code = [(NSHTTPURLResponse *)resp statusCode];
        NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;

        NSString *reply = nil;
        if (json[@"choices"] && [json[@"choices"] isKindOfClass:[NSArray class]] && [json[@"choices"] count] > 0) {
            NSDictionary *first = json[@"choices"][0];
            reply = first[@"message"][@"content"];
        }

        if (!reply.length) {
            reply = json[@"error"][@"message"] ?: @"I couldn't process your voice request right now.";
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [s handleVoiceResponse:reply forUserText:userText];
        });
    }];
    [task resume];
}

- (void)handleVoiceResponse:(NSString *)reply forUserText:(NSString *)userText {
    if ([self.delegate respondsToSelector:@selector(voiceAgentDidFinishWithUserText:replyText:)]) {
        [self.delegate voiceAgentDidFinishWithUserText:userText replyText:reply];
    }
    [self speakText:reply completion:nil];
}

#pragma mark - Speech Synthesis (Fish Audio Voice 5233336f5f44460ea0902b0802375451 + TTS)

- (void)speakText:(NSString *)text completion:(void(^)(void))completion {
    (void)completion;
    [self stopSpeaking];

    // Strip markdown tags (bold, code, headers) for clean speech
    NSString *clean = [text stringByReplacingOccurrencesOfString:@"**" withString:@""];
    clean = [clean stringByReplacingOccurrencesOfString:@"`" withString:@""];
    clean = [clean stringByReplacingOccurrencesOfString:@"#" withString:@""];
    clean = [clean stringByReplacingOccurrencesOfString:@"\n\n" withString:@". "];
    if (!clean.length) return;

    [self setState:SaturnVoiceAgentStateSpeaking statusMessage:@"Zarah speaking (fish-audio)…"];

    NSString *voiceId = self.voiceId.length ? self.voiceId : @"5233336f5f44460ea0902b0802375451";
    NSString *apiKey = self.openRouterApiKey;

    // Try Fish Audio direct TTS with voiceId
    NSDictionary *body = @{
        @"text": clean,
        @"reference_id": voiceId,
        @"format": @"mp3",
        @"latency": @"normal"
    };
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    NSURL *url = [NSURL URLWithString:@"https://api.fish.audio/v1/tts"];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    req.timeoutInterval = 12;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    if (apiKey.length) {
        [req setValue:[NSString stringWithFormat:@"Bearer %@", apiKey] forHTTPHeaderField:@"Authorization"];
    }
    req.HTTPBody = jsonData;

    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        __strong typeof(weakSelf) s = weakSelf;
        if (!s) return;

        NSInteger code = [(NSHTTPURLResponse *)resp statusCode];
        if (data && data.length > 500 && !err && code == 200) {
            NSError *playErr = nil;
            s->_audioPlayer = [[AVAudioPlayer alloc] initWithData:data error:&playErr];
            if (s->_audioPlayer && !playErr) {
                s->_audioPlayer.delegate = s;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [s->_audioPlayer play];
                });
                return;
            }
        }

        // Fallback to Native macOS Speech Synthesizer
        dispatch_async(dispatch_get_main_queue(), ^{
            AVSpeechUtterance *utterance = [[AVSpeechUtterance alloc] initWithString:clean];
            utterance.voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"en-US"];
            utterance.rate = 0.52;
            utterance.pitchMultiplier = 1.05;
            [s->_speechSynthesizer speakUtterance:utterance];
        });
    }];
    [task resume];
}

- (void)stopSpeaking {
    if (_audioPlayer.isPlaying) {
        [_audioPlayer stop];
        _audioPlayer = nil;
    }
    if (_speechSynthesizer.isSpeaking) {
        [_speechSynthesizer stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    }
}

#pragma mark - AVAudioPlayerDelegate

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    (void)player;
    (void)flag;
    [self setState:SaturnVoiceAgentStateIdle statusMessage:@"Ready"];
}

#pragma mark - AVSpeechSynthesizerDelegate

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didFinishSpeechUtterance:(AVSpeechUtterance *)utterance {
    (void)synthesizer;
    (void)utterance;
    [self setState:SaturnVoiceAgentStateIdle statusMessage:@"Ready"];
}

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didCancelSpeechUtterance:(AVSpeechUtterance *)utterance {
    (void)synthesizer;
    (void)utterance;
    [self setState:SaturnVoiceAgentStateIdle statusMessage:@"Ready"];
}

@end
