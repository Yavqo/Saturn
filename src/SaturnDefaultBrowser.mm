#import "SaturnDefaultBrowser.h"
#import <Cocoa/Cocoa.h>

static NSString *const kOfferCountKey = @"saturn.defaultBrowser.offerCount";

@implementation SaturnDefaultBrowser

+ (NSURL *)currentHandlerURL {
    return [[NSWorkspace sharedWorkspace] URLForApplicationToOpenURL:[NSURL URLWithString:@"https://example.com"]];
}

+ (BOOL)isDefault {
    NSURL *h = [self currentHandlerURL];
    if (!h) return NO;
    NSString *mine = [NSBundle mainBundle].bundleURL.URLByResolvingSymlinksInPath.path;
    return [h.URLByResolvingSymlinksInPath.path isEqualToString:mine];
}

+ (NSString *)currentDefaultName {
    NSURL *h = [self currentHandlerURL];
    if (!h) return nil;
    NSString *n = [[NSFileManager defaultManager] displayNameAtPath:h.path];
    return [n hasSuffix:@".app"] ? [n substringToIndex:n.length - 4] : n;
}

+ (void)makeDefaultWithCompletion:(void (^)(BOOL, NSError *))completion {
    // Setting "https" changes the web-browser role (http too); macOS asks the user to confirm.
    [[NSWorkspace sharedWorkspace] setDefaultApplicationAtURL:[NSBundle mainBundle].bundleURL toOpenURLsWithScheme:@"https" completionHandler:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion([self isDefault], error);
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
