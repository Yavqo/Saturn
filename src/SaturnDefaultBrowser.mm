#import "SaturnDefaultBrowser.h"
#import <Cocoa/Cocoa.h>
#import <CoreServices/CoreServices.h>

static NSString *const kOfferCountKey = @"saturn.defaultBrowser.offerCount";

@implementation SaturnDefaultBrowser

+ (NSURL *)currentHandlerURL {
    return [[NSWorkspace sharedWorkspace] URLForApplicationToOpenURL:[NSURL URLWithString:@"https://example.com"]];
}

+ (BOOL)isDefault {
    NSString *identifier = [NSBundle mainBundle].bundleIdentifier;
    if (!identifier.length) return NO;
    for (NSString *scheme in @[@"http", @"https"]) {
        NSURL *handler = [[NSWorkspace sharedWorkspace] URLForApplicationToOpenURL:[NSURL URLWithString:[scheme stringByAppendingString:@"://example.com"]]];
        if (!handler || ![[NSBundle bundleWithURL:handler].bundleIdentifier isEqualToString:identifier]) return NO;
    }
    return YES;
}

+ (NSString *)currentDefaultName {
    NSURL *h = [self currentHandlerURL];
    if (!h) return nil;
    NSString *n = [[NSFileManager defaultManager] displayNameAtPath:h.path];
    return [n hasSuffix:@".app"] ? [n substringToIndex:n.length - 4] : n;
}

+ (void)makeDefaultWithCompletion:(void (^)(BOOL, NSError *))completion {
    NSURL *application = [NSBundle mainBundle].bundleURL;
    if (![application.pathExtension.lowercaseString isEqualToString:@"app"]) {
        NSError *error = [NSError errorWithDomain:@"SaturnDefaultBrowser" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Open Saturn from the installed Saturn.app in Applications, then try again."}];
        if (completion) completion(NO, error);
        return;
    }
    // Register newly installed or rebuilt app bundles before requesting the browser role.
    OSStatus registration = LSRegisterURL((__bridge CFURLRef)application, true);
    if (registration != noErr) {
        NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:registration userInfo:@{NSLocalizedDescriptionKey: @"macOS could not register Saturn. Move Saturn.app to Applications, open it, and try again."}];
        if (completion) completion(NO, error);
        return;
    }
    [[NSWorkspace sharedWorkspace] setDefaultApplicationAtURL:application toOpenURLsWithScheme:@"https" completionHandler:^(NSError *httpsError) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (httpsError) { if (completion) completion([self isDefault], httpsError); return; }
            [[NSWorkspace sharedWorkspace] setDefaultApplicationAtURL:application toOpenURLsWithScheme:@"http" completionHandler:^(NSError *httpError) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) completion([self isDefault], httpError);
                });
            }];
        });
    }];
}

+ (BOOL)shouldOffer {
    if ([self isDefault]) return NO;
    return [[NSUserDefaults standardUserDefaults] integerForKey:kOfferCountKey] < 2;
}

+ (void)recordOfferShown {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setInteger:[d integerForKey:kOfferCountKey] + 1 forKey:kOfferCountKey];
}

@end
