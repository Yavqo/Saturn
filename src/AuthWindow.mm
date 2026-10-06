#import "YavqoTheme.h"
#import "AuthWindow.h"
#import "Supabase/SupabaseClient.h"

@interface AuthWindow () <NSTextFieldDelegate>
@property (nonatomic, strong) NSVisualEffectView *glass;
@property (nonatomic, strong) NSTextField *emailField;
@property (nonatomic, strong) NSSecureTextField *passwordField;
@property (nonatomic, strong) NSTextField *errorLabel;
@property (nonatomic, strong) NSButton *signInBtn;
@property (nonatomic, strong) NSButton *signUpBtn;
@property (nonatomic, strong) NSButton *signOutBtn;
@property (nonatomic, strong) NSView *loggedOutView;
@property (nonatomic, strong) NSView *loggedInView;
@property (nonatomic, strong) NSTextField *loggedInEmail;
@property (nonatomic, strong) NSImageView *loggedInAvatar;
@property (nonatomic, strong) NSProgressIndicator *spinner;
@end

@implementation AuthWindow

+ (instancetype)shared {
    static AuthWindow *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[AuthWindow alloc] initWithAuthUI]; });
    return s;
}

- (instancetype)initWithAuthUI {
    NSRect frame = NSMakeRect(0, 0, 380, 420);
    self = [super initWithContentRect:frame styleMask:(NSWindowStyleMaskTitled|NSWindowStyleMaskClosable) backing:NSBackingStoreBuffered defer:NO];
    if (self) {
        self.title = @"Saturn — Account";
        self.releasedWhenClosed = NO;
        self.backgroundColor = [NSColor clearColor];
        self.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
        self.delegate = self;
        [self buildUI];
        [self refreshState];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshState) name:@"SupabaseSessionChanged" object:nil];
    }
    return self;
}

- (void)buildUI {
    NSView *c = self.contentView;
    c.wantsLayer = YES;
    c.layer.backgroundColor = [NSColor whiteColor].CGColor;

    NSVisualEffectView *glass = [[NSVisualEffectView alloc] initWithFrame:c.bounds];
    glass.material = NSVisualEffectMaterialHUDWindow;
    glass.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    glass.state = NSVisualEffectStateActive;
    glass.autoresizingMask = NSViewWidthSizable|NSViewHeightSizable;
    [c addSubview:glass positioned:NSWindowBelow relativeTo:nil];
    glass.hidden = YES;   // flat white canvas, no vibrancy
    self.glass = glass;

    // Logo
    NSTextField *logo = [NSTextField labelWithString:@"Saturn"];
    logo.font = [NSFont systemFontOfSize:22 weight:NSFontWeightBold];
    logo.textColor = Y_ink();
    CGFloat nameW = ceil([logo.stringValue sizeWithAttributes:@{NSFontAttributeName: logo.font}].width);
    CGFloat markW = 32, gap = 8, startX = (380 - (markW + gap + nameW)) / 2;
    logo.frame = NSMakeRect(startX + markW + gap, 370, nameW + 4, 28);
    [c addSubview:logo];
    NSString *logoPath = [[NSBundle mainBundle] pathForResource:@"saturn-logo" ofType:@"png"];
    if (logoPath) {
        NSImageView *mark = [[NSImageView alloc] initWithFrame:NSMakeRect(startX, 368, markW, markW)];
        mark.image = [[NSImage alloc] initWithContentsOfFile:logoPath];
        mark.imageScaling = NSImageScaleProportionallyUpOrDown;
        [c addSubview:mark];
    }

    NSTextField *sub = [NSTextField labelWithString:@"Sign in to sync your profile avatar"];
    sub.font = [NSFont systemFontOfSize:11];
    sub.textColor = Y_muted();
    sub.frame = NSMakeRect(20, 350, 340, 16);
    sub.alignment = NSTextAlignmentCenter;
    [c addSubview:sub];

    // Logged out view
    NSView *out = [[NSView alloc] initWithFrame:NSMakeRect(0, 60, 380, 280)];
    out.autoresizingMask = NSViewWidthSizable;
    self.loggedOutView = out;
    [c addSubview:out];

    // Email
    NSTextField *emailLabel = [NSTextField labelWithString:@"Email"];
    emailLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    emailLabel.textColor = Y_ink();
    emailLabel.frame = NSMakeRect(30, 220, 320, 16);
    [out addSubview:emailLabel];

    self.emailField = [[NSTextField alloc] initWithFrame:NSMakeRect(30, 190, 320, 30)];
    self.emailField.placeholderString = @"you@example.com";
    self.emailField.bezeled = YES;
    self.emailField.bezelStyle = NSTextFieldRoundedBezel;
    self.emailField.focusRingType = NSFocusRingTypeNone;
    self.emailField.font = [NSFont systemFontOfSize:13];
    [out addSubview:self.emailField];

    NSTextField *passLabel = [NSTextField labelWithString:@"Password"];
    passLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    passLabel.textColor = Y_ink();
    passLabel.frame = NSMakeRect(30, 150, 320, 16);
    [out addSubview:passLabel];

    self.passwordField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(30, 120, 320, 30)];
    self.passwordField.placeholderString = @"••••••••";
    self.passwordField.bezeled = YES;
    self.passwordField.bezelStyle = NSTextFieldRoundedBezel;
    self.passwordField.focusRingType = NSFocusRingTypeNone;
    self.passwordField.font = [NSFont systemFontOfSize:13];
    [out addSubview:self.passwordField];

    self.errorLabel = [NSTextField labelWithString:@""];
    self.errorLabel.font = [NSFont systemFontOfSize:11];
    self.errorLabel.textColor = [NSColor systemRedColor];
    self.errorLabel.frame = NSMakeRect(30, 95, 320, 20);
    self.errorLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.errorLabel.usesSingleLineMode = NO;
    [out addSubview:self.errorLabel];

    self.signInBtn = [NSButton buttonWithTitle:@"Sign In" target:self action:@selector(doSignIn:)];
    self.signInBtn.frame = NSMakeRect(30, 55, 155, 32);
    self.signInBtn.bezelStyle = NSBezelStyleRounded;
    YT_pill(self.signInBtn, YES);
    self.signInBtn.keyEquivalent = @"\r";
    [out addSubview:self.signInBtn];

    self.signUpBtn = [NSButton buttonWithTitle:@"Sign Up" target:self action:@selector(doSignUp:)];
    self.signUpBtn.frame = NSMakeRect(195, 55, 155, 32);
    self.signUpBtn.bezelStyle = NSBezelStyleRounded;
    YT_pill(self.signUpBtn, NO);
    [out addSubview:self.signUpBtn];

    NSTextField *hint = [NSTextField labelWithString:@"New here? Sign Up creates your profile row automatically."];
    hint.font = [NSFont systemFontOfSize:10];
    hint.textColor = Y_muted();
    hint.frame = NSMakeRect(30, 30, 320, 16);
    hint.alignment = NSTextAlignmentCenter;
    [out addSubview:hint];

    // Logged in view
    NSView *in = [[NSView alloc] initWithFrame:NSMakeRect(0, 60, 380, 280)];
    in.autoresizingMask = NSViewWidthSizable;
    in.hidden = YES;
    self.loggedInView = in;
    [c addSubview:in];

    self.loggedInAvatar = [[NSImageView alloc] initWithFrame:NSMakeRect(140, 180, 100, 100)];
    self.loggedInAvatar.wantsLayer = YES;
    self.loggedInAvatar.layer.cornerRadius = 50;
    self.loggedInAvatar.layer.masksToBounds = YES;
    self.loggedInAvatar.layer.borderColor = Y_hairline().CGColor;
    self.loggedInAvatar.layer.borderWidth = 1;
    self.loggedInAvatar.imageScaling = NSImageScaleProportionallyUpOrDown;
    [in addSubview:self.loggedInAvatar];

    self.loggedInEmail = [NSTextField labelWithString:@""];
    self.loggedInEmail.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    self.loggedInEmail.textColor = Y_ink();
    self.loggedInEmail.frame = NSMakeRect(20, 140, 340, 20);
    self.loggedInEmail.alignment = NSTextAlignmentCenter;
    [in addSubview:self.loggedInEmail];

    NSTextField *status = [NSTextField labelWithString:@"Signed in — avatar comes from profiles.avatar_url"];
    status.font = [NSFont systemFontOfSize:10];
    status.textColor = Y_muted();
    status.frame = NSMakeRect(20, 115, 340, 16);
    status.alignment = NSTextAlignmentCenter;
    [in addSubview:status];

    self.signOutBtn = [NSButton buttonWithTitle:@"Sign Out" target:self action:@selector(doSignOut:)];
    self.signOutBtn.frame = NSMakeRect(110, 60, 160, 32);
    self.signOutBtn.bezelStyle = NSBezelStyleRounded;
    YT_pill(self.signOutBtn, YES);
    [in addSubview:self.signOutBtn];

    // Spinner
    self.spinner = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(175, 20, 30, 30)];
    self.spinner.style = NSProgressIndicatorStyleSpinning;
    self.spinner.controlSize = NSControlSizeSmall;
    self.spinner.displayedWhenStopped = NO;
    [c addSubview:self.spinner];

    // Close button — always visible so user can leave (fixes "no way to leave")
    NSButton *closeBtn = [NSButton buttonWithTitle:@"Close" target:self action:@selector(closeAuth:)];
    closeBtn.frame = NSMakeRect(30, 20, 80, 28);
    closeBtn.bezelStyle = NSBezelStyleRounded;
    YT_pill(closeBtn, NO);
    closeBtn.keyEquivalent = @"\e"; // Esc
    [c addSubview:closeBtn];
}

- (void)refreshState {
    BOOL signedIn = [[SupabaseClient shared] isSignedIn];
    self.loggedOutView.hidden = signedIn;
    self.loggedInView.hidden = !signedIn;
    if (signedIn) {
        NSString *email = [SupabaseClient shared].currentUserEmail ?: @"";
        self.loggedInEmail.stringValue = email;
        NSString *uid = [SupabaseClient shared].currentUserId;
        self.loggedInAvatar.image = [NSImage imageWithSystemSymbolName:@"person.crop.circle" accessibilityDescription:nil];
        if (uid) {
            [[SupabaseClient shared] fetchProfileForUserId:uid completion:^(NSDictionary *profile, NSError *err){
                NSString *url = profile[@"avatar_url"];
                if ([url isKindOfClass:[NSString class]] && url.length) {
                    [self loadAvatarFromURL:url into:self.loggedInAvatar];
                    // Notify for toolbar avatar
                    [[NSNotificationCenter defaultCenter] postNotificationName:@"SaturnProfileUpdated" object:nil userInfo:profile];
                } else {
                    // No avatar_url — show placeholder
                    [[NSNotificationCenter defaultCenter] postNotificationName:@"SaturnProfileUpdated" object:nil userInfo:@{@"avatar_url": @""}];
                }
            }];
        }
    }
}

- (void)loadAvatarFromURL:(NSString *)urlString into:(NSImageView *)imageView {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return;
    NSURLSessionDataTask *t = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *d, NSURLResponse *r, NSError *e){
        if (d && !e) {
            NSImage *img = [[NSImage alloc] initWithData:d];
            if (img) {
                dispatch_async(dispatch_get_main_queue(), ^{ imageView.image = img; });
            }
        }
    }];
    [t resume];
}

- (void)showForWindow:(NSWindow *)parent {
    [self refreshState];
    self.errorLabel.stringValue = @"";
    if (parent) {
        [parent beginSheet:self completionHandler:nil];
    } else {
        [self center];
        [self makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
    }
}

- (void)showStandalone {
    [self refreshState];
    [self center];
    [self makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (IBAction)doSignIn:(id)sender {
    NSString *email = [self.emailField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *pass = self.passwordField.stringValue;
    if (!email.length || !pass.length) { self.errorLabel.stringValue = @"Enter email and password"; return; }
    [self setBusy:YES];
    [[SupabaseClient shared] signInWithEmail:email password:pass completion:^(NSDictionary *data, NSError *err){
        [self setBusy:NO];
        if (err) { self.errorLabel.stringValue = err.localizedDescription; return; }
        if (![SupabaseClient shared].isSignedIn) { self.errorLabel.stringValue = @"Sign in failed — check email/password"; return; }
        self.errorLabel.stringValue = @"";
        [[NSNotificationCenter defaultCenter] postNotificationName:@"SupabaseSessionChanged" object:nil];
        [self refreshState];
        // Close sheet after short delay
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 600 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            if (self.sheetParent) [self.sheetParent endSheet:self];
            else [self orderOut:nil];
        });
    }];
}

- (IBAction)doSignUp:(id)sender {
    NSString *email = [self.emailField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *pass = self.passwordField.stringValue;
    if (!email.length || !pass.length) { self.errorLabel.stringValue = @"Enter email and password"; return; }
    if (pass.length < 6) { self.errorLabel.stringValue = @"Password must be at least 6 characters"; return; }
    [self setBusy:YES];
    [[SupabaseClient shared] signUpWithEmail:email password:pass completion:^(NSDictionary *data, NSError *err){
        [self setBusy:NO];
        if (err) { self.errorLabel.stringValue = err.localizedDescription; return; }
        // If email confirm required, Supabase returns user without session — show message
        if (![SupabaseClient shared].isSignedIn) {
            self.errorLabel.stringValue = @"Check your email to confirm, then Sign In";
            self.errorLabel.textColor = [NSColor systemGreenColor];
            return;
        }
        self.errorLabel.stringValue = @"";
        [[NSNotificationCenter defaultCenter] postNotificationName:@"SupabaseSessionChanged" object:nil];
        [self refreshState];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 600 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            if (self.sheetParent) [self.sheetParent endSheet:self];
            else [self orderOut:nil];
        });
    }];
}

- (IBAction)doSignOut:(id)sender {
    [self setBusy:YES];
    [[SupabaseClient shared] signOutWithCompletion:^(NSError *err){
        [self setBusy:NO];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"SupabaseSessionChanged" object:nil];
        [self refreshState];
        if (self.sheetParent) [self.sheetParent endSheet:self];
    }];
}

- (void)setBusy:(BOOL)busy {
    if (busy) [self.spinner startAnimation:nil]; else [self.spinner stopAnimation:nil];
    self.signInBtn.enabled = !busy;
    self.signUpBtn.enabled = !busy;
    self.signOutBtn.enabled = !busy;
}

- (IBAction)closeAuth:(id)sender {
    if (self.sheetParent) {
        [self.sheetParent endSheet:self];
    } else {
        [self orderOut:nil];
    }
}
- (void)cancelOperation:(id)sender {
    [self closeAuth:sender];
}
- (BOOL)windowShouldClose:(id)sender {
    [self closeAuth:sender];
    return NO;
}
- (void)performClose:(id)sender {
    [self closeAuth:sender];
}

@end
