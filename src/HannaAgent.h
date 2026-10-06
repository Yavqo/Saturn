#pragma once
#import <Foundation/Foundation.h>

@class SaturnWindow;

// Lets Zarah drive the browser: she reads the page, clicks, types, scrolls and opens tabs through tools,
// one step at a time, until the task is done or the user stops her.
@interface HannaAgent : NSObject
- (instancetype)initWithWindow:(SaturnWindow *)window;
@property (nonatomic, readonly) BOOL running;
- (void)runTask:(NSString *)task;
- (void)stop;
@end
