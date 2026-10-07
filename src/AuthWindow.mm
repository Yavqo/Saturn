#import "YavqoTheme.h"
#import "AuthWindow.h"
#import "Supabase/SupabaseClient.h"
#import <QuartzCore/QuartzCore.h>

// Account window: sign in, create an account, and the signed-in profile. Yavqo look: white canvas, one blue, pills,
// 24px cards, flat.

static const CGFloat kW = 440, kH = 640, kSide = 40;

#pragma mark Flipped canvas (so layout reads top-down)

@interface AuthCanvas : NSView
@end
@implementation AuthCanvas
- (BOOL)isFlipped { return YES; }
@end

#pragma mark Text field that reports focus

@interface AuthTextField : NSTextField
@property (nonatomic, copy) void (^onFocus)(BOOL focused);
@end
@implementation AuthTextField
- (BOOL)becomeFirstResponder {
    BOOL ok = [super becomeFirstResponder];
    if (ok && self.onFocus) self.onFocus(YES);
    return ok;
}
@end
@interface AuthSecureField : NSSecureTextField
@property (nonatomic, copy) void (^onFocus)(BOOL focused);
@end
@implementation AuthSecureField
- (BOOL)becomeFirstResponder {
    BOOL ok = [super becomeFirstResponder];
    if (ok && self.onFocus) self.onFocus(YES);
    return ok;
}
@end

#pragma mark Labelled field: a rounded box with a small label above the value

@interface AuthFieldBox : NSView
@property (nonatomic, strong) NSTextField *label;
@property (nonatomic, strong) NSTextField *field;          // plain (or the visible one)
@property (nonatomic, strong) AuthSecureField *secure;     // password only
@property (nonatomic, strong) NSButton *eye;
@property (nonatomic, assign) BOOL focused, errored;
- (instancetype)initWithFrame:(NSRect)f label:(NSString *)label placeholder:(NSString *)ph password:(BOOL)pw;
- (NSString *)text;
- (void)setText:(NSString *)t;
- (void)focus;
@end

@implementation AuthFieldBox
- (BOOL)isFlipped { return YES; }

- (instancetype)initWithFrame:(NSRect)f label:(NSString *)label placeholder:(NSString *)ph password:(BOOL)pw {
    self = [super initWithFrame:f];
    if (!self) return nil;
    self.wantsLayer = YES;
    self.layer.cornerRadius = 14;
    self.layer.borderWidth = 1;
    self.layer.backgroundColor = [NSColor whiteColor].CGColor;

    _label = [NSTextField labelWithString:label];
    _label.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    _label.textColor = Y_muted();
    _label.frame = NSMakeRect(16, 9, f.size.width - 32, 14);
    [self addSubview:_label];

    CGFloat right = pw ? 44 : 16;
    __weak typeof(self) weak = self;
    void (^focusBlock)(BOOL) = ^(BOOL on) { weak.focused = on; };

    AuthTextField *tf = [[AuthTextField alloc] initWithFrame:NSMakeRect(16, 25, f.size.width - 16 - right, 24)];
    tf.onFocus = focusBlock;
    _field = tf;
    if (pw) {
        _secure = [[AuthSecureField alloc] initWithFrame:tf.frame];
        _secure.onFocus = focusBlock;
    }
    for (NSTextField *t in (pw ? @[_field, _secure] : @[_field])) {
        t.bordered = NO; t.bezeled = NO; t.drawsBackground = NO;
        t.focusRingType = NSFocusRingTypeNone;
        t.font = [NSFont systemFontOfSize:15];
        t.textColor = Y_ink();
        t.placeholderAttributedString = [[NSAttributedString alloc] initWithString:ph attributes:@{NSForegroundColorAttributeName: Y_muted2(), NSFontAttributeName: [NSFont systemFontOfSize:15]}];
        t.lineBreakMode = NSLineBreakByClipping;
        [t.cell setScrollable:YES];
        [self addSubview:t];
    }
    if (pw) {
        _field.hidden = YES;
        _eye = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"eye" accessibilityDescription:@"Show password"] target:self action:@selector(toggleEye:)];
        _eye.bordered = NO;
        _eye.contentTintColor = Y_muted();
        _eye.frame = NSMakeRect(f.size.width - 40, (f.size.height - 28) / 2, 28, 28);
        _eye.toolTip = @"Show password";
        [self addSubview:_eye];
    }
    [self refreshBorder];
    return self;
}

- (NSTextField *)active { return _secure && !_secure.hidden ? _secure : _field; }
- (NSString *)text { return [self active].stringValue; }
- (void)setText:(NSString *)t { _field.stringValue = t; _secure.stringValue = t; }
- (void)focus { [self.window makeFirstResponder:[self active]]; }

- (void)toggleEye:(id)sender {
    (void)sender;
    BOOL show = _field.hidden;                       // currently masked → reveal
    NSString *v = [self active].stringValue;
    _field.stringValue = v; _secure.stringValue = v;
    _field.hidden = !show; _secure.hidden = show;
    _eye.image = [NSImage imageWithSystemSymbolName:show ? @"eye.slash" : @"eye" accessibilityDescription:nil];
    _eye.toolTip = show ? @"Hide password" : @"Show password";
    [self focus];
}

- (void)setFocused:(BOOL)f { _focused = f; [self refreshBorder]; }
- (void)setErrored:(BOOL)e { _errored = e; [self refreshBorder]; }

- (void)refreshBorder {
    NSColor *c = _errored ? Y_negative() : (_focused ? YT_rgb(0x01, 0x43, 0xB5, 1) : Y_border());
    self.layer.borderColor = c.CGColor;
    self.layer.borderWidth = (_focused || _errored) ? 2 : 1;
    _label.textColor = _errored ? Y_negative() : (_focused ? Y_blue() : Y_muted());
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (!self.window) return;
    // Focus ends when editing ends or the window loses key
    [[NSNotificationCenter defaultCenter] addObserverForName:NSControlTextDidEndEditingNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        if (n.object == self->_field || n.object == self->_secure) self.focused = NO;
    }];
}
@end

#pragma mark Sliding Sign in / Create account toggle

@interface AuthToggle : NSView
@property (nonatomic, assign) NSInteger index;
@property (nonatomic, copy) void (^onChange)(NSInteger index);
- (void)setIndex:(NSInteger)i animated:(BOOL)animated;
@end
@implementation AuthToggle {
    NSView *_thumb;
    NSArray<NSTextField *> *_labels;
}
- (BOOL)isFlipped { return YES; }
- (instancetype)initWithFrame:(NSRect)f titles:(NSArray<NSString *> *)titles {
    self = [super initWithFrame:f];
    if (!self) return nil;
    self.wantsLayer = YES;
    self.layer.cornerRadius = f.size.height / 2;
    self.layer.backgroundColor = Y_soft().CGColor;
    CGFloat w = (f.size.width - 8) / 2;
    _thumb = [[NSView alloc] initWithFrame:NSMakeRect(4, 4, w, f.size.height - 8)];
    _thumb.wantsLayer = YES;
    _thumb.layer.cornerRadius = (f.size.height - 8) / 2;
    _thumb.layer.backgroundColor = [NSColor whiteColor].CGColor;
    [self addSubview:_thumb];
    NSMutableArray *ls = [NSMutableArray array];
    for (NSInteger i = 0; i < 2; i++) {
        NSTextField *l = [NSTextField labelWithString:titles[i]];
        l.alignment = NSTextAlignmentCenter;
        l.frame = NSMakeRect(4 + i * w, (f.size.height - 18) / 2, w, 18);
        [self addSubview:l];
        [ls addObject:l];
    }
    _labels = ls;
    [self restyle];
    return self;
}
- (void)restyle {
    for (NSInteger i = 0; i < 2; i++) {
        _labels[i].font = [NSFont systemFontOfSize:14 weight:i == _index ? NSFontWeightBold : NSFontWeightMedium];
        _labels[i].textColor = i == _index ? Y_ink() : Y_muted();
    }
}
- (void)setIndex:(NSInteger)i { [self setIndex:i animated:NO]; }
- (void)setIndex:(NSInteger)i animated:(BOOL)animated {
    _index = i;
    CGFloat w = (self.bounds.size.width - 8) / 2;
    NSRect target = NSMakeRect(4 + i * w, 4, w, self.bounds.size.height - 8);
    if (animated) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
            ctx.duration = 0.22;
            ctx.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.12 :0.8 :0.32 :1];
            self->_thumb.animator.frame = target;
        }];
    } else _thumb.frame = target;
    [self restyle];
}
- (void)mouseDown:(NSEvent *)e {
    NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
    NSInteger i = p.x < self.bounds.size.width / 2 ? 0 : 1;
    if (i == _index) return;
    [self setIndex:i animated:YES];
    if (_onChange) _onChange(i);
}
@end

#pragma mark Window

@interface AuthWindow () <NSTextFieldDelegate>
@property (nonatomic, strong) AuthCanvas *root;
// Signed out
@property (nonatomic, strong) NSView *outView;
@property (nonatomic, strong) NSTextField *headline, *subline, *errorLabel, *footnote;
@property (nonatomic, strong) AuthToggle *toggle;
@property (nonatomic, strong) AuthFieldBox *emailBox, *passBox;
@property (nonatomic, strong) NSButton *primaryBtn, *closeLink;
@property (nonatomic, strong) NSProgressIndicator *spinner;
@property (nonatomic, assign) BOOL registering, busy;
// Signed in
@property (nonatomic, strong) NSView *inView;
@property (nonatomic, strong) NSView *avatarHolder;
@property (nonatomic, strong) NSImageView *avatarImage;
@property (nonatomic, strong) NSTextField *avatarInitial, *inName, *inEmail, *cardValue;
@property (nonatomic, strong) NSButton *signOutBtn, *doneBtn;
@end

@implementation AuthWindow

+ (instancetype)shared {
    static AuthWindow *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[AuthWindow alloc] initWithAuthUI]; });
    return s;
}

- (instancetype)initWithAuthUI {
    self = [super initWithContentRect:NSMakeRect(0, 0, kW, kH) styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskFullSizeContentView) backing:NSBackingStoreBuffered defer:NO];
    if (self) {
        self.title = @"Saturn account";
        self.titlebarAppearsTransparent = YES;
        self.titleVisibility = NSWindowTitleHidden;
        self.releasedWhenClosed = NO;
        self.backgroundColor = [NSColor whiteColor];
        self.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
        self.delegate = self;
        [self buildUI];
        [self refreshState];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshState) name:@"SupabaseSessionChanged" object:nil];
    }
    return self;
}

#pragma mark Build

static NSTextField *Label(NSString *s, CGFloat size, NSFontWeight w, NSColor *c, NSTextAlignment a) {
    NSTextField *l = [NSTextField labelWithString:s];
    l.font = [NSFont systemFontOfSize:size weight:w];
    l.textColor = c;
    l.alignment = a;
    return l;
}

- (void)buildUI {
    _root = [[AuthCanvas alloc] initWithFrame:NSMakeRect(0, 0, kW, kH)];
    _root.wantsLayer = YES;
    _root.layer.backgroundColor = [NSColor whiteColor].CGColor;
    self.contentView = _root;
    const CGFloat cw = kW - 2 * kSide;

    // Brand mark
    NSString *logoPath = [[NSBundle mainBundle] pathForResource:@"saturn-logo" ofType:@"png"];
    if (logoPath) {
        NSImageView *mark = [[NSImageView alloc] initWithFrame:NSMakeRect((kW - 56) / 2, 52, 56, 56)];
        mark.image = [[NSImage alloc] initWithContentsOfFile:logoPath];
        mark.imageScaling = NSImageScaleProportionallyUpOrDown;
        [_root addSubview:mark];
    }

    // ---- Signed out
    _outView = [[AuthCanvas alloc] initWithFrame:NSMakeRect(0, 0, kW, kH)];
    [_root addSubview:_outView];
    _headline = Label(@"Welcome back", 28, NSFontWeightMedium, Y_ink(), NSTextAlignmentCenter);
    _headline.frame = NSMakeRect(kSide, 126, cw, 36);
    _subline = Label(@"Sign in to sync your profile picture.", 14, NSFontWeightRegular, Y_muted(), NSTextAlignmentCenter);
    _subline.frame = NSMakeRect(kSide, 166, cw, 20);
    [_outView addSubview:_headline];
    [_outView addSubview:_subline];

    _toggle = [[AuthToggle alloc] initWithFrame:NSMakeRect(kSide, 210, cw, 44) titles:@[@"Sign in", @"Create account"]];
    __weak typeof(self) weak = self;
    _toggle.onChange = ^(NSInteger i) { [weak setRegistering:i == 1 animated:YES]; };
    [_outView addSubview:_toggle];

    _emailBox = [[AuthFieldBox alloc] initWithFrame:NSMakeRect(kSide, 276, cw, 58) label:@"Email" placeholder:@"you@example.com" password:NO];
    _passBox = [[AuthFieldBox alloc] initWithFrame:NSMakeRect(kSide, 346, cw, 58) label:@"Password" placeholder:@"Your password" password:YES];
    _emailBox.field.delegate = self;
    _passBox.field.delegate = self;
    _passBox.secure.delegate = self;
    [_outView addSubview:_emailBox];
    [_outView addSubview:_passBox];

    _errorLabel = Label(@"", 13, NSFontWeightRegular, Y_negative(), NSTextAlignmentLeft);
    _errorLabel.frame = NSMakeRect(kSide + 4, 414, cw - 8, 36);
    _errorLabel.lineBreakMode = NSLineBreakByWordWrapping;
    _errorLabel.maximumNumberOfLines = 2;
    _errorLabel.cell.wraps = YES;
    _errorLabel.alphaValue = 0;
    [_outView addSubview:_errorLabel];

    _primaryBtn = [NSButton buttonWithTitle:@"Sign in" target:self action:@selector(submit:)];
    _primaryBtn.bezelStyle = NSBezelStyleRounded;
    _primaryBtn.frame = NSMakeRect(kSide, 460, cw, 52);
    [self styleButton:_primaryBtn title:@"Sign in" primary:YES];
    _primaryBtn.keyEquivalent = @"\r";
    [_outView addSubview:_primaryBtn];

    _spinner = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(kSide + cw / 2 - 74, 460 + 18, 16, 16)];
    _spinner.style = NSProgressIndicatorStyleSpinning;
    _spinner.controlSize = NSControlSizeSmall;
    _spinner.displayedWhenStopped = NO;
    _spinner.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];   // white on the blue pill
    [_outView addSubview:_spinner];

    _footnote = Label(@"", 12, NSFontWeightRegular, Y_muted(), NSTextAlignmentCenter);
    _footnote.frame = NSMakeRect(kSide, 524, cw, 16);
    [_outView addSubview:_footnote];

    _closeLink = [NSButton buttonWithTitle:@"Not now" target:self action:@selector(closeAuth:)];
    _closeLink.bordered = NO;
    _closeLink.frame = NSMakeRect((kW - 120) / 2, 566, 120, 28);
    _closeLink.attributedTitle = [[NSAttributedString alloc] initWithString:@"Not now" attributes:@{NSForegroundColorAttributeName: Y_muted(), NSFontAttributeName: [NSFont systemFontOfSize:14 weight:NSFontWeightMedium]}];
    _closeLink.keyEquivalent = @"\e";
    [_outView addSubview:_closeLink];

    // ---- Signed in
    _inView = [[AuthCanvas alloc] initWithFrame:NSMakeRect(0, 0, kW, kH)];
    _inView.hidden = YES;
    [_root addSubview:_inView];

    _avatarHolder = [[AuthCanvas alloc] initWithFrame:NSMakeRect((kW - 112) / 2, 130, 112, 112)];
    _avatarHolder.wantsLayer = YES;
    _avatarHolder.layer.cornerRadius = 56;
    _avatarHolder.layer.masksToBounds = YES;
    _avatarHolder.layer.backgroundColor = Y_blue().CGColor;
    _avatarInitial = Label(@"S", 46, NSFontWeightMedium, [NSColor whiteColor], NSTextAlignmentCenter);
    _avatarInitial.frame = NSMakeRect(0, 28, 112, 56);
    _avatarImage = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 112, 112)];
    _avatarImage.imageScaling = NSImageScaleAxesIndependently;
    _avatarImage.hidden = YES;
    [_avatarHolder addSubview:_avatarInitial];
    [_avatarHolder addSubview:_avatarImage];
    [_inView addSubview:_avatarHolder];

    _inName = Label(@"", 26, NSFontWeightMedium, Y_ink(), NSTextAlignmentCenter);
    _inName.frame = NSMakeRect(kSide, 260, cw, 34);
    _inName.lineBreakMode = NSLineBreakByTruncatingTail;
    [_inView addSubview:_inName];

    // Status chip
    NSView *chip = [[AuthCanvas alloc] initWithFrame:NSMakeRect((kW - 112) / 2, 304, 112, 30)];
    chip.wantsLayer = YES;
    chip.layer.cornerRadius = 15;
    chip.layer.backgroundColor = Y_soft().CGColor;
    NSView *dot = [[NSView alloc] initWithFrame:NSMakeRect(14, 11, 8, 8)];
    dot.wantsLayer = YES; dot.layer.cornerRadius = 4; dot.layer.backgroundColor = Y_positive().CGColor;
    NSTextField *chipText = Label(@"Signed in", 13, NSFontWeightMedium, Y_ink(), NSTextAlignmentLeft);
    chipText.frame = NSMakeRect(30, 6, 78, 18);
    [chip addSubview:dot]; [chip addSubview:chipText];
    [_inView addSubview:chip];

    // Email card
    NSView *card = [[AuthCanvas alloc] initWithFrame:NSMakeRect(kSide, 366, cw, 84)];
    card.wantsLayer = YES;
    card.layer.cornerRadius = 24;
    card.layer.backgroundColor = Y_soft().CGColor;
    NSTextField *cl = Label(@"Email", 12, NSFontWeightMedium, Y_muted(), NSTextAlignmentLeft);
    cl.frame = NSMakeRect(24, 20, cw - 48, 16);
    _cardValue = Label(@"", 16, NSFontWeightMedium, Y_ink(), NSTextAlignmentLeft);
    _cardValue.frame = NSMakeRect(24, 40, cw - 48, 22);
    _cardValue.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [card addSubview:cl]; [card addSubview:_cardValue];
    [_inView addSubview:card];

    _doneBtn = [NSButton buttonWithTitle:@"Done" target:self action:@selector(closeAuth:)];
    _doneBtn.bezelStyle = NSBezelStyleRounded;
    _doneBtn.frame = NSMakeRect(kSide, 478, cw, 52);
    [self styleButton:_doneBtn title:@"Done" primary:YES];
    _doneBtn.keyEquivalent = @"\r";
    [_inView addSubview:_doneBtn];

    _signOutBtn = [NSButton buttonWithTitle:@"Sign out" target:self action:@selector(doSignOut:)];
    _signOutBtn.bezelStyle = NSBezelStyleRounded;
    _signOutBtn.frame = NSMakeRect(kSide, 540, cw, 52);
    [self styleButton:_signOutBtn title:@"Sign out" primary:NO];
    [_inView addSubview:_signOutBtn];

    [self setRegistering:NO animated:NO];
}

// 52px pill; primary = blue, otherwise soft grey.
- (void)styleButton:(NSButton *)b title:(NSString *)title primary:(BOOL)primary {
    b.title = title;
    b.bordered = NO;
    b.wantsLayer = YES;
    b.layer.cornerRadius = b.frame.size.height / 2;
    b.layer.backgroundColor = (primary ? Y_blue() : Y_soft()).CGColor;
    NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
    ps.alignment = NSTextAlignmentCenter;
    b.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{
        NSForegroundColorAttributeName: primary ? [NSColor whiteColor] : Y_ink(),
        NSFontAttributeName: [NSFont systemFontOfSize:15 weight:NSFontWeightBold],
        NSParagraphStyleAttributeName: ps }];
}

#pragma mark Mode

- (void)setRegistering:(BOOL)reg animated:(BOOL)animated {
    _registering = reg;
    if (_toggle.index != (reg ? 1 : 0)) [_toggle setIndex:reg ? 1 : 0 animated:animated];
    void (^apply)(void) = ^{
        self.headline.stringValue = reg ? @"Create your account" : @"Welcome back";
        self.subline.stringValue = reg ? @"One account for your profile picture and settings." : @"Sign in to sync your profile picture.";
        self.footnote.stringValue = reg ? @"Use at least 6 characters for your password." : @"";
        self.passBox.label.stringValue = reg ? @"Password (6+ characters)" : @"Password";
        [self styleButton:self.primaryBtn title:reg ? @"Create account" : @"Sign in" primary:YES];
        [self clearError];
    };
    if (!animated) { apply(); return; }
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
        ctx.duration = 0.1;
        self.headline.animator.alphaValue = 0; self.subline.animator.alphaValue = 0;
    } completionHandler:^{
        apply();
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
            ctx.duration = 0.2;
            self.headline.animator.alphaValue = 1; self.subline.animator.alphaValue = 1;
        }];
    }];
}

#pragma mark Errors and busy state

- (void)showMessage:(NSString *)text positive:(BOOL)positive {
    _errorLabel.stringValue = text;
    _errorLabel.textColor = positive ? Y_positive() : Y_negative();
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) { ctx.duration = 0.2; self->_errorLabel.animator.alphaValue = 1; }];
}

- (void)clearError {
    _emailBox.errored = NO; _passBox.errored = NO;
    _errorLabel.animator.alphaValue = 0;
}

- (void)failWithMessage:(NSString *)text email:(BOOL)emailBad password:(BOOL)passBad {
    _emailBox.errored = emailBad; _passBox.errored = passBad;
    [self showMessage:text positive:NO];
    // Shake the form
    CAKeyframeAnimation *shake = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
    shake.values = @[@0, @-9, @9, @-6, @6, @-3, @3, @0];
    shake.duration = 0.38;
    for (NSView *v in @[_emailBox, _passBox]) [v.layer addAnimation:shake forKey:@"shake"];
}

- (void)setBusy:(BOOL)busy {
    _busy = busy;
    _emailBox.alphaValue = _passBox.alphaValue = busy ? 0.6 : 1;
    _primaryBtn.enabled = !busy;
    _signOutBtn.enabled = !busy;
    _toggle.alphaValue = busy ? 0.6 : 1;
    if (busy) [_spinner startAnimation:nil]; else [_spinner stopAnimation:nil];
    [self styleButton:_primaryBtn title:busy ? (_registering ? @"Creating account…" : @"Signing in…") : (_registering ? @"Create account" : @"Sign in") primary:YES];
    _primaryBtn.layer.backgroundColor = (busy ? YT_rgb(0x04, 0x57, 0xCB, 1) : Y_blue()).CGColor;
}

static BOOL ValidEmail(NSString *s) {
    NSRange at = [s rangeOfString:@"@"];
    if (at.location == NSNotFound || at.location == 0) return NO;
    NSString *domain = [s substringFromIndex:at.location + 1];
    return [domain rangeOfString:@"."].location != NSNotFound && ![domain hasSuffix:@"."] && ![s containsString:@" "];
}

// Turns Supabase's blunt messages into plain ones.
static NSString *Friendly(NSError *err, BOOL registering) {
    NSString *m = err.localizedDescription ?: @"";
    NSString *l = m.lowercaseString;
    if ([l containsString:@"invalid login"] || [l containsString:@"invalid_grant"] || [l containsString:@"invalid credentials"]) return @"That email and password don’t match. Check them and try again.";
    if ([l containsString:@"already registered"] || [l containsString:@"already been registered"] || [l containsString:@"already exists"]) return @"There’s already an account with this email. Try signing in instead.";
    if ([l containsString:@"email not confirmed"]) return @"Confirm your email first. We sent you a link.";
    if ([l containsString:@"rate limit"] || [l containsString:@"too many"]) return @"Too many attempts. Wait a minute and try again.";
    if ([l containsString:@"weak"] || [l containsString:@"password should"]) return @"Choose a stronger password with at least 6 characters.";
    if ([err.domain isEqualToString:NSURLErrorDomain]) return @"Can’t reach the server. Check your connection and try again.";
    if ([l containsString:@"not configured"]) return @"Accounts aren’t set up in this build.";
    return m.length ? m : (registering ? @"Couldn’t create the account. Try again." : @"Couldn’t sign in. Try again.");
}

#pragma mark Actions

- (void)submit:(id)sender {
    (void)sender;
    if (_busy) return;
    NSString *email = [_emailBox.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *pass = _passBox.text;
    [self clearError];
    if (!email.length) { [self failWithMessage:@"Enter your email address." email:YES password:NO]; [_emailBox focus]; return; }
    if (!ValidEmail(email)) { [self failWithMessage:@"That email address doesn’t look right." email:YES password:NO]; [_emailBox focus]; return; }
    if (!pass.length) { [self failWithMessage:@"Enter your password." email:NO password:YES]; [_passBox focus]; return; }
    if (_registering && pass.length < 6) { [self failWithMessage:@"Your password needs at least 6 characters." email:NO password:YES]; [_passBox focus]; return; }

    [self setBusy:YES];
    BOOL reg = _registering;
    void (^done)(NSDictionary *, NSError *) = ^(NSDictionary *data, NSError *err) {
        (void)data;
        [self setBusy:NO];
        if (err) {
            NSString *friendly = Friendly(err, reg);
            BOOL passBad = [friendly hasPrefix:@"That email and password"] || [friendly hasPrefix:@"Choose a stronger"];
            [self failWithMessage:friendly email:!passBad && ![friendly hasPrefix:@"Too many"] password:passBad];
            return;
        }
        if (![SupabaseClient shared].isSignedIn) {
            if (reg) {      // email confirmation is switched on
                [self setRegistering:NO animated:YES];
                [self showMessage:@"Account created. Check your email to confirm it, then sign in." positive:YES];
            } else {
                [self failWithMessage:@"Couldn’t sign in. Check your email and password." email:YES password:YES];
            }
            return;
        }
        [self.passBox setText:@""];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"SupabaseSessionChanged" object:nil];
        [self refreshState];
    };
    if (reg) [[SupabaseClient shared] signUpWithEmail:email password:pass completion:done];
    else [[SupabaseClient shared] signInWithEmail:email password:pass completion:done];
}

- (IBAction)doSignOut:(id)sender {
    (void)sender;
    _signOutBtn.enabled = NO;
    [[SupabaseClient shared] signOutWithCompletion:^(NSError *err) {
        (void)err;
        self.signOutBtn.enabled = YES;
        [[NSNotificationCenter defaultCenter] postNotificationName:@"SupabaseSessionChanged" object:nil];
        [self refreshState];
        [self setRegistering:NO animated:NO];
    }];
}

// Return in the email field moves to the password; in the password field it submits (the default button does that).
- (BOOL)control:(NSControl *)control textView:(NSTextView *)tv doCommandBySelector:(SEL)sel {
    (void)tv;
    if (sel == @selector(insertNewline:)) {
        if (control == _emailBox.field) { [_passBox focus]; return YES; }
        [self submit:nil];
        return YES;
    }
    return NO;
}
- (void)controlTextDidChange:(NSNotification *)n {
    (void)n;
    if (_errorLabel.alphaValue > 0 || _emailBox.errored || _passBox.errored) [self clearError];
}

#pragma mark State

- (void)refreshState {
    BOOL signedIn = [[SupabaseClient shared] isSignedIn];
    _outView.hidden = signedIn;
    _inView.hidden = !signedIn;
    if (!signedIn) return;
    NSString *email = [SupabaseClient shared].currentUserEmail ?: @"";
    NSString *local = [email componentsSeparatedByString:@"@"].firstObject ?: @"";
    _inName.stringValue = local.length ? [local.capitalizedString stringByReplacingOccurrencesOfString:@"." withString:@" "] : @"Your account";
    _cardValue.stringValue = email;
    NSString *initial = local.length ? [[local substringToIndex:1] uppercaseString] : @"S";
    _avatarInitial.stringValue = initial;
    _avatarImage.hidden = YES;
    _avatarInitial.hidden = NO;
    NSString *uid = [SupabaseClient shared].currentUserId;
    if (!uid) return;
    [[SupabaseClient shared] fetchProfileForUserId:uid completion:^(NSDictionary *profile, NSError *err) {
        (void)err;
        NSString *url = profile[@"avatar_url"];
        if ([url isKindOfClass:[NSString class]] && url.length) {
            [self loadAvatar:url];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"SaturnProfileUpdated" object:nil userInfo:profile];
        } else {
            [[NSNotificationCenter defaultCenter] postNotificationName:@"SaturnProfileUpdated" object:nil userInfo:@{@"avatar_url": @""}];
        }
    }];
}

- (void)loadAvatar:(NSString *)raw {
    NSString *s = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSURL *url = nil;
    if ([s hasPrefix:@"http://"] || [s hasPrefix:@"https://"]) url = [NSURL URLWithString:s];
    else {
        NSString *base = [SupabaseClient shared].supabaseURL;
        if (base.length) {
            NSString *path = [s hasPrefix:@"/"] ? [s substringFromIndex:1] : s;
            if (![path hasPrefix:@"avatars/"] && ![path containsString:@"/"]) path = [@"avatars/" stringByAppendingString:path];
            url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/storage/v1/object/public/%@", [base stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]], path]];
        }
    }
    if (!url) return;
    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        NSImage *img = (d && !e && [(NSHTTPURLResponse *)r statusCode] < 400) ? [[NSImage alloc] initWithData:d] : nil;
        if (!img) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.avatarImage.image = img;
            self.avatarImage.hidden = NO;
            self.avatarInitial.hidden = YES;
        });
    }] resume];
}

#pragma mark Showing

- (void)prepareToShow {
    [self refreshState];
    [self clearError];
    _errorLabel.alphaValue = 0;
    [self setBusy:NO];
}

- (void)showForWindow:(NSWindow *)parent {
    [self prepareToShow];
    if (parent) [parent beginSheet:self completionHandler:nil];
    else { [self center]; [self makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES]; }
    if (!_outView.hidden) dispatch_async(dispatch_get_main_queue(), ^{ [self.emailBox focus]; });
}

- (void)showStandalone {
    [self prepareToShow];
    [self center];
    [self makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    if (!_outView.hidden) dispatch_async(dispatch_get_main_queue(), ^{ [self.emailBox focus]; });
}

- (IBAction)closeAuth:(id)sender {
    (void)sender;
    if (self.sheetParent) [self.sheetParent endSheet:self];
    else [self orderOut:nil];
}
- (void)cancelOperation:(id)sender { [self closeAuth:sender]; }
- (BOOL)windowShouldClose:(id)sender { [self closeAuth:sender]; return NO; }
- (void)performClose:(id)sender { [self closeAuth:sender]; }

@end
