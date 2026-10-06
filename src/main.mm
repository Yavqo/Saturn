#import <Cocoa/Cocoa.h>
#import "SaturnAppDelegate.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // Parse --url arg (if none provided, use user's default search engine)
        NSString *initialURL = nil;
        BOOL startPrivate = NO;
        for (int i = 1; i < argc; ++i) {
            NSString *arg = [NSString stringWithUTF8String:argv[i]];
            if ([arg isEqualToString:@"--url"] && i+1 < argc) {
                initialURL = [NSString stringWithUTF8String:argv[++i]];
            } else if ([arg hasPrefix:@"http://"] || [arg hasPrefix:@"https://"]) {
                initialURL = arg;
            } else if ([arg isEqualToString:@"--private"]) {
                startPrivate = YES;
            } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
                printf("Saturn — Native Browser (C++ / WKWebView)\n");
                printf("Usage: saturn [--private] [--url https://example.com] [url]\n");
                printf("  --url <url>  Initial URL\n");
                printf("  --private    Open a private window\n");
                printf("  --help       Show help\n");
                return 0;
            }
        }

        NSApplication *app = [NSApplication sharedApplication];
        app.activationPolicy = NSApplicationActivationPolicyRegular;

        SaturnAppDelegate *delegate = [[SaturnAppDelegate alloc] init];
        delegate.initialURLString = initialURL;
        delegate.startPrivate = startPrivate;
        app.delegate = delegate;

        [app run];
    }
    return 0;
}
