#import "YavqoTheme.h"
#import "SetupWindow.h"
#import "Settings.h"
#import "Supabase/SupabaseClient.h"
#import <QuartzCore/QuartzCore.h>

// Yavqo first-run setup: four steps (welcome, search engine, features, done).
// Motion follows the design language: slow fade with a 16px rise, quick hover feedback, one spring for selection.

static const CGFloat kSetupW = 760;
static const CGFloat kSetupH = 600;
static const CGFloat kPageY = 124;     // page area sits above the footer
static const CGFloat kPageH = 440;
static const NSInteger kStepCount = 4;

static NSFont *SU_font(CGFloat size, NSFontWeight weight) { return [NSFont systemFontOfSize:size weight:weight]; }

static NSTextField *SU_label(NSString *text, NSFont *font, NSColor *color, NSRect frame, NSTextAlignment align, BOOL wrap) {
    NSTextField *l = wrap ? [NSTextField wrappingLabelWithString:text] : [NSTextField labelWithString:text];
    l.font = font;
    l.textColor = color;
    l.alignment = align;
    l.frame = frame;
    return l;
}

static CAMediaTimingFunction *SU_easeStrong(void) { return [CAMediaTimingFunction functionWithControlPoints:.12 :.8 :.32 :1]; }

// Fade in over 0.8s while rising 16px.
static void SU_fadeRise(NSView *v, CFTimeInterval delay) {
    v.wantsLayer = YES;
    CALayer *l = v.layer;
    CFTimeInterval t0 = CACurrentMediaTime() + delay;

    CABasicAnimation *o = [CABasicAnimation animationWithKeyPath:@"opacity"];
    o.fromValue = @0; o.toValue = @1;
    o.duration = 0.8; o.beginTime = t0;
    o.fillMode = kCAFillModeBackwards;
    o.timingFunction = SU_easeStrong();
    [l addAnimation:o forKey:@"su.fade"];

    CABasicAnimation *r = [CABasicAnimation animationWithKeyPath:@"transform.translation.y"];
    r.fromValue = @(-16); r.toValue = @0;
    r.duration = 0.8; r.beginTime = t0;
    r.fillMode = kCAFillModeBackwards;
    r.timingFunction = SU_easeStrong();
    [l addAnimation:r forKey:@"su.rise"];
}

static CGPathRef SU_checkPath(CGFloat s) {
    CGMutablePathRef p = CGPathCreateMutable();
    CGPathMoveToPoint(p, NULL, s * 0.30, s * 0.52);
    CGPathAddLineToPoint(p, NULL, s * 0.45, s * 0.37);
    CGPathAddLineToPoint(p, NULL, s * 0.71, s * 0.66);
    return p;
}

#pragma mark - Saturn mark (drawn, animated)

@interface SetupMarkView : NSView
@end

@implementation SetupMarkView

- (instancetype)initWithFrame:(NSRect)f {
    self = [super initWithFrame:f];
    if (!self) return nil;
    self.wantsLayer = YES;
    self.layer.masksToBounds = NO;

    CALayer *root = [CALayer layer];
    root.frame = self.bounds;
    [self.layer addSublayer:root];

    // The Saturn logo (resources/saturn-logo.png)
    NSString *path = [[NSBundle mainBundle] pathForResource:@"saturn-logo" ofType:@"png"];
    NSImage *logo = path ? [[NSImage alloc] initWithContentsOfFile:path] : nil;
    CALayer *planet = [CALayer layer];
    planet.frame = self.bounds;
    if (logo) { planet.contents = logo; planet.contentsGravity = kCAGravityResizeAspect; }
    else { planet.backgroundColor = Y_blue().CGColor; planet.cornerRadius = f.size.width * 0.3; planet.frame = CGRectInset(self.bounds, f.size.width * 0.2, f.size.width * 0.2); }
    [root addSublayer:planet];

    // Entrance: spring scale + fade
    CASpringAnimation *pop = [CASpringAnimation animationWithKeyPath:@"transform.scale"];
    pop.fromValue = @0.6; pop.toValue = @1;
    pop.mass = 1; pop.stiffness = 110; pop.damping = 13; pop.initialVelocity = 0;
    pop.duration = pop.settlingDuration;
    [root addAnimation:pop forKey:@"su.pop"];
    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = @0; fade.toValue = @1; fade.duration = 0.6;
    [root addAnimation:fade forKey:@"su.fade"];

    // Idle: slow float, planet breathes
    CABasicAnimation *bob = [CABasicAnimation animationWithKeyPath:@"position.y"];
    bob.fromValue = @(root.position.y - 5); bob.toValue = @(root.position.y + 5);
    bob.duration = 3.2; bob.autoreverses = YES; bob.repeatCount = HUGE_VALF;
    bob.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [root addAnimation:bob forKey:@"su.bob"];

    CABasicAnimation *breathe = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    breathe.fromValue = @1; breathe.toValue = @1.035;
    breathe.duration = 4; breathe.autoreverses = YES; breathe.repeatCount = HUGE_VALF;
    breathe.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [planet addAnimation:breathe forKey:@"su.breathe"];
    return self;
}
@end

#pragma mark - Completion check (drawn stroke)

@interface SetupCheckView : NSView
@end

@implementation SetupCheckView
- (instancetype)initWithFrame:(NSRect)f {
    self = [super initWithFrame:f];
    if (!self) return nil;
    self.wantsLayer = YES;
    self.layer.masksToBounds = NO;
    CGFloat S = f.size.width;
    CGRect circle = CGRectMake(S * 0.1, S * 0.1, S * 0.8, S * 0.8);

    CAShapeLayer *pulse = [CAShapeLayer layer];
    pulse.frame = self.bounds;
    CGPathRef cp = CGPathCreateWithEllipseInRect(circle, NULL);
    pulse.path = cp;
    pulse.fillColor = NULL;
    pulse.strokeColor = Y_blue().CGColor;
    pulse.lineWidth = 3;
    pulse.opacity = 0;
    [self.layer addSublayer:pulse];

    CAShapeLayer *disc = [CAShapeLayer layer];
    disc.frame = self.bounds;
    disc.path = cp; CGPathRelease(cp);
    disc.fillColor = Y_blue().CGColor;
    [self.layer addSublayer:disc];

    CAShapeLayer *check = [CAShapeLayer layer];
    check.frame = self.bounds;
    CGPathRef kp = SU_checkPath(S);
    check.path = kp; CGPathRelease(kp);
    check.fillColor = NULL;
    check.strokeColor = [NSColor whiteColor].CGColor;
    check.lineWidth = S * 0.065;
    check.lineCap = kCALineCapRound;
    check.lineJoin = kCALineJoinRound;
    [self.layer addSublayer:check];

    CASpringAnimation *pop = [CASpringAnimation animationWithKeyPath:@"transform.scale"];
    pop.fromValue = @0; pop.toValue = @1;
    pop.mass = 1; pop.stiffness = 140; pop.damping = 12;
    pop.duration = pop.settlingDuration;
    [disc addAnimation:pop forKey:@"su.pop"];

    CABasicAnimation *draw = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
    draw.fromValue = @0; draw.toValue = @1;
    draw.duration = 0.45; draw.beginTime = CACurrentMediaTime() + 0.35;
    draw.fillMode = kCAFillModeBackwards;
    draw.timingFunction = SU_easeStrong();
    [check addAnimation:draw forKey:@"su.draw"];

    CABasicAnimation *ringScale = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    ringScale.fromValue = @1; ringScale.toValue = @1.45;
    CABasicAnimation *ringFade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    ringFade.fromValue = @0.55; ringFade.toValue = @0;
    CAAnimationGroup *g = [CAAnimationGroup animation];
    g.animations = @[ringScale, ringFade];
    g.duration = 1.1; g.beginTime = CACurrentMediaTime() + 0.55;
    g.fillMode = kCAFillModeBackwards;
    g.timingFunction = SU_easeStrong();
    [pulse addAnimation:g forKey:@"su.pulse"];
    return self;
}
@end

#pragma mark - Pill button with hover

@interface SetupPill : NSButton
@property (nonatomic, assign) BOOL primary;
@property (nonatomic, strong) NSTrackingArea *hoverArea;
- (instancetype)initWithLabel:(NSString *)text primary:(BOOL)primary target:(id)target action:(SEL)action;
- (void)setLabel:(NSString *)text;
@end

@implementation SetupPill
- (instancetype)initWithLabel:(NSString *)text primary:(BOOL)primary target:(id)target action:(SEL)action {
    self = [super initWithFrame:NSMakeRect(0, 0, 200, 52)];
    if (!self) return nil;
    _primary = primary;
    self.bordered = NO;
    self.target = target;
    self.action = action;
    self.wantsLayer = YES;
    self.layer.cornerRadius = 26;
    [self setLabel:text];
    [self applyColor:NO];
    return self;
}
- (void)setLabel:(NSString *)text {
    NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
    ps.alignment = NSTextAlignmentCenter;
    self.attributedTitle = [[NSAttributedString alloc] initWithString:text attributes:@{
        NSForegroundColorAttributeName: _primary ? [NSColor whiteColor] : Y_ink(),
        NSFontAttributeName: SU_font(15, NSFontWeightBold),
        NSParagraphStyleAttributeName: ps }];
}
- (void)applyColor:(BOOL)hover {
    NSColor *base = _primary ? (hover ? Y_blueHover() : Y_blue()) : (hover ? YT_rgb(0xE4, 0xE9, 0xEE, 1) : Y_soft());
    [CATransaction begin];
    [CATransaction setAnimationDuration:0.2];
    self.layer.backgroundColor = base.CGColor;
    [CATransaction commit];
}
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (self.hoverArea) [self removeTrackingArea:self.hoverArea];
    self.hoverArea = [[NSTrackingArea alloc] initWithRect:self.bounds options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways owner:self userInfo:nil];
    [self addTrackingArea:self.hoverArea];
}
- (void)mouseEntered:(NSEvent *)e { (void)e; [self applyColor:YES]; }
- (void)mouseExited:(NSEvent *)e { (void)e; [self applyColor:NO]; }
@end

#pragma mark - Search engine card

@interface SetupEngineCard : NSControl
@property (nonatomic, assign) SaturnSearchEngine engine;
@property (nonatomic, assign) BOOL isSelected;
@property (nonatomic, copy) void (^onSelect)(SaturnSearchEngine engine);
- (instancetype)initWithEngine:(SaturnSearchEngine)engine name:(NSString *)name subtitle:(NSString *)subtitle
                         color:(NSColor *)color symbol:(NSString *)symbol letter:(NSString *)letter;
- (void)setSelectedAnimated:(BOOL)selected;
@end

@implementation SetupEngineCard {
    CALayer *_card;
    CALayer *_check;
    BOOL _hovered;
    NSTrackingArea *_area;
}

- (instancetype)initWithEngine:(SaturnSearchEngine)engine name:(NSString *)name subtitle:(NSString *)subtitle
                         color:(NSColor *)color symbol:(NSString *)symbol letter:(NSString *)letter {
    self = [super initWithFrame:NSMakeRect(0, 0, 300, 72)];
    if (!self) return nil;
    _engine = engine;
    self.wantsLayer = YES;

    _card = [CALayer layer];
    _card.frame = self.bounds;
    _card.cornerRadius = 24;
    _card.borderWidth = 2;
    [self.layer addSublayer:_card];

    NSView *badge = [[NSView alloc] initWithFrame:NSMakeRect(16, 14, 44, 44)];
    badge.wantsLayer = YES;
    badge.layer.cornerRadius = 22;
    badge.layer.backgroundColor = color.CGColor;
    [self addSubview:badge];
    if (letter.length) {
        NSTextField *l = SU_label(letter, SU_font(21, NSFontWeightBold), [NSColor whiteColor], NSMakeRect(0, 9, 44, 26), NSTextAlignmentCenter, NO);
        [badge addSubview:l];
    } else if (symbol.length) {
        NSImageView *iv = [[NSImageView alloc] initWithFrame:NSMakeRect(11, 11, 22, 22)];
        iv.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil];
        iv.contentTintColor = [NSColor whiteColor];
        [badge addSubview:iv];
    }

    [self addSubview:SU_label(name, SU_font(16, NSFontWeightMedium), Y_ink(), NSMakeRect(74, 38, 160, 20), NSTextAlignmentLeft, NO)];
    [self addSubview:SU_label(subtitle, SU_font(13, NSFontWeightRegular), Y_muted(), NSMakeRect(74, 17, 170, 16), NSTextAlignmentLeft, NO)];

    // Check badge (plain CALayer so it scales from its centre)
    _check = [CALayer layer];
    _check.frame = CGRectMake(300 - 16 - 26, 23, 26, 26);
    _check.cornerRadius = 13;
    _check.backgroundColor = Y_blue().CGColor;
    CAShapeLayer *tick = [CAShapeLayer layer];
    tick.frame = CGRectMake(0, 0, 26, 26);
    CGPathRef kp = SU_checkPath(26);
    tick.path = kp; CGPathRelease(kp);
    tick.fillColor = NULL;
    tick.strokeColor = [NSColor whiteColor].CGColor;
    tick.lineWidth = 2.2;
    tick.lineCap = kCALineCapRound;
    tick.lineJoin = kCALineJoinRound;
    [_check addSublayer:tick];
    [self.layer addSublayer:_check];

    [self applyStateAnimated:NO];
    return self;
}

- (void)applyStateAnimated:(BOOL)animated {
    [CATransaction begin];
    [CATransaction setDisableActions:!animated];
    [CATransaction setAnimationDuration:0.2];
    if (_isSelected) {
        _card.backgroundColor = [NSColor whiteColor].CGColor;
        _card.borderColor = Y_blue().CGColor;
    } else {
        _card.backgroundColor = (_hovered ? YT_rgb(0xE8, 0xEC, 0xF1, 1) : Y_soft()).CGColor;
        _card.borderColor = [NSColor clearColor].CGColor;
    }
    _check.transform = _isSelected ? CATransform3DIdentity : CATransform3DMakeScale(0.001, 0.001, 1);
    _check.opacity = _isSelected ? 1 : 0;
    [CATransaction commit];
}

- (void)setIsSelected:(BOOL)isSelected {
    _isSelected = isSelected;
    [self applyStateAnimated:NO];
}

- (void)setSelectedAnimated:(BOOL)selected {
    if (_isSelected == selected) return;
    _isSelected = selected;
    [self applyStateAnimated:YES];
    if (selected) {
        CASpringAnimation *pop = [CASpringAnimation animationWithKeyPath:@"transform.scale"];
        pop.fromValue = @0.2; pop.toValue = @1;
        pop.mass = 1; pop.stiffness = 220; pop.damping = 14;
        pop.duration = pop.settlingDuration;
        [_check addAnimation:pop forKey:@"su.pop"];
    }
}

- (NSView *)hitTest:(NSPoint)p { return NSPointInRect(p, self.frame) ? self : nil; }
- (BOOL)acceptsFirstMouse:(NSEvent *)e { (void)e; return YES; }
- (void)mouseDown:(NSEvent *)e { (void)e; if (self.onSelect) self.onSelect(_engine); }
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_area) [self removeTrackingArea:_area];
    _area = [[NSTrackingArea alloc] initWithRect:self.bounds options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways owner:self userInfo:nil];
    [self addTrackingArea:_area];
}
- (void)mouseEntered:(NSEvent *)e { (void)e; _hovered = YES; [self applyStateAnimated:YES]; }
- (void)mouseExited:(NSEvent *)e { (void)e; _hovered = NO; [self applyStateAnimated:YES]; }
@end

#pragma mark - Setup window controller

@implementation SetupWindow {
    SaturnSearchEngine _selectedEngine;
    NSMutableArray<SetupEngineCard *> *_cards;
    void (^_completion)(SaturnSearchEngine);
    NSInteger _step;
    BOOL _busy;
    NSView *_root;
    NSView *_page;
    NSMutableArray<NSView *> *_dots;
    SetupPill *_primary;
    SetupPill *_back;
}

+ (instancetype)shared {
    static SetupWindow *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[SetupWindow alloc] init]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _selectedEngine = SaturnSettings.shared.defaultEngine;
        _cards = [NSMutableArray array];
        _dots = [NSMutableArray array];
    }
    return self;
}

- (void)showSetupWithCompletion:(void(^)(SaturnSearchEngine selectedEngine))completion {
    _completion = [completion copy];
    _step = 0;
    _busy = NO;
    _selectedEngine = SaturnSettings.shared.defaultEngine;

    NSRect screen = [NSScreen mainScreen].visibleFrame;
    NSRect rect = NSMakeRect(NSMidX(screen) - kSetupW / 2, NSMidY(screen) - kSetupH / 2, kSetupW, kSetupH);
    NSWindow *win = [[NSWindow alloc] initWithContentRect:rect
                                                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskFullSizeContentView
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    win.titlebarAppearsTransparent = YES;
    win.titleVisibility = NSWindowTitleHidden;
    win.movableByWindowBackground = YES;
    win.releasedWhenClosed = NO;
    win.backgroundColor = [NSColor whiteColor];
    win.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    win.alphaValue = 0;

    _root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kSetupW, kSetupH)];
    _root.wantsLayer = YES;
    _root.layer.backgroundColor = [NSColor whiteColor].CGColor;
    win.contentView = _root;

    // Progress dots
    [_dots removeAllObjects];
    for (NSInteger i = 0; i < kStepCount; i++) {
        NSView *d = [[NSView alloc] initWithFrame:NSMakeRect(0, 100, 8, 8)];
        d.wantsLayer = YES;
        d.layer.cornerRadius = 4;
        [_root addSubview:d];
        [_dots addObject:d];
    }

    // Footer buttons
    _back = [[SetupPill alloc] initWithLabel:@"Back" primary:NO target:self action:@selector(backAction:)];
    _primary = [[SetupPill alloc] initWithLabel:@"Get started" primary:YES target:self action:@selector(primaryAction:)];
    _primary.keyEquivalent = @"\r";
    [_root addSubview:_back];
    [_root addSubview:_primary];
    [self updateChromeAnimated:NO];

    [self installPage];

    self.window = win;
    [win makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
        ctx.duration = 0.4;
        win.animator.alphaValue = 1;
    }];
}

#pragma mark Chrome (dots + buttons)

- (void)updateChromeAnimated:(BOOL)animated {
    // Dots: the active one stretches into a pill
    CGFloat gap = 8, activeW = 24, dotW = 8;
    CGFloat total = activeW + (kStepCount - 1) * dotW + (kStepCount - 1) * gap;
    CGFloat x = (kSetupW - total) / 2;
    NSMutableArray<NSValue *> *frames = [NSMutableArray array];
    for (NSInteger i = 0; i < kStepCount; i++) {
        CGFloat w = (i == _step) ? activeW : dotW;
        [frames addObject:[NSValue valueWithRect:NSMakeRect(x, 100, w, 8)]];
        x += w + gap;
    }

    BOOL showBack = (_step > 0 && _step < kStepCount - 1);
    CGFloat primaryW = showBack ? 220 : 260;
    CGFloat backW = 130, between = 12;
    CGFloat rowW = showBack ? backW + between + primaryW : primaryW;
    CGFloat startX = (kSetupW - rowW) / 2;
    NSRect backFrame = NSMakeRect(startX, 40, backW, 52);
    NSRect primaryFrame = NSMakeRect(showBack ? startX + backW + between : startX, 40, primaryW, 52);

    NSString *label = _step == 0 ? @"Get started" : (_step == kStepCount - 1 ? @"Launch Saturn" : @"Continue");
    [_primary setLabel:label];

    void (^apply)(BOOL) = ^(BOOL anim) {
        for (NSInteger i = 0; i < kStepCount; i++) {
            NSView *d = self->_dots[i];
            NSView *target = anim ? d.animator : d;
            target.frame = [frames[i] rectValue];
            d.layer.backgroundColor = ((i == self->_step) ? Y_blue() : Y_border()).CGColor;
        }
        NSView *pf = anim ? self->_primary.animator : self->_primary;
        pf.frame = primaryFrame;
        NSView *bf = anim ? self->_back.animator : self->_back;
        bf.frame = backFrame;
        (anim ? self->_back.animator : self->_back).alphaValue = showBack ? 1 : 0;
    };
    _back.enabled = showBack;
    if (animated) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
            ctx.duration = 0.35;
            ctx.timingFunction = SU_easeStrong();
            apply(YES);
        }];
    } else {
        apply(NO);
    }
}

#pragma mark Pages

- (void)installPage {
    NSView *pv = [[NSView alloc] initWithFrame:NSMakeRect(0, kPageY, kSetupW, kPageH)];
    pv.wantsLayer = YES;
    switch (_step) {
        case 0: [self buildWelcome:pv]; break;
        case 1: [self buildSearch:pv]; break;
        case 2: [self buildFeatures:pv]; break;
        default: [self buildDone:pv]; break;
    }
    [_root addSubview:pv positioned:NSWindowBelow relativeTo:_primary];
    _page = pv;

    NSInteger i = 0;
    for (NSView *v in pv.subviews) {
        if ([v isKindOfClass:[SetupMarkView class]] || [v isKindOfClass:[SetupCheckView class]]) continue;  // animate themselves
        SU_fadeRise(v, 0.05 + 0.07 * i++);
    }
}

- (void)buildWelcome:(NSView *)pv {
    CGFloat mark = 150;
    SetupMarkView *m = [[SetupMarkView alloc] initWithFrame:NSMakeRect((kSetupW - mark) / 2, kPageH - 40 - mark, mark, mark)];
    [pv addSubview:m];
    [pv addSubview:SU_label(@"Welcome to Saturn", SU_font(44, NSFontWeightMedium), Y_ink(), NSMakeRect(0, 168, kSetupW, 54), NSTextAlignmentCenter, NO)];
    [pv addSubview:SU_label(@"A calmer way to browse, with Zarah built in.\nSetup takes less than a minute.", SU_font(18, NSFontWeightRegular), Y_muted(), NSMakeRect(130, 100, kSetupW - 260, 56), NSTextAlignmentCenter, YES)];
}

- (void)buildSearch:(NSView *)pv {
    [pv addSubview:SU_label(@"Choose your search", SU_font(34, NSFontWeightMedium), Y_ink(), NSMakeRect(0, 376, kSetupW, 42), NSTextAlignmentCenter, NO)];
    [pv addSubview:SU_label(@"Pick a default. You can change it any time in Settings.", SU_font(16, NSFontWeightRegular), Y_muted(), NSMakeRect(0, 346, kSetupW, 22), NSTextAlignmentCenter, NO)];

    NSArray *engines = @[
        @{@"e": @(SaturnSearchEngineGoogle),     @"n": @"Google",       @"s": @"Fast web search",    @"c": YT_rgb(66, 133, 244, 1), @"i": @"",                      @"l": @"G"},
        @{@"e": @(SaturnSearchEngineDuckDuckGo), @"n": @"DuckDuckGo",   @"s": @"Private by default", @"c": YT_rgb(222, 88, 51, 1),  @"i": @"shield.lefthalf.filled", @"l": @""},
        @{@"e": @(SaturnSearchEngineBrave),      @"n": @"Brave Search", @"s": @"Independent index",  @"c": YT_rgb(251, 84, 43, 1),  @"i": @"flame.fill",            @"l": @""},
        @{@"e": @(SaturnSearchEngineBing),       @"n": @"Bing",         @"s": @"Microsoft search",    @"c": YT_rgb(0, 120, 212, 1),   @"i": @"magnifyingglass",      @"l": @""},
        @{@"e": @(SaturnSearchEngineEcosia),     @"n": @"Ecosia",       @"s": @"Plants trees",        @"c": YT_rgb(51, 168, 84, 1),   @"i": @"leaf.fill",             @"l": @""},
        @{@"e": @(SaturnSearchEngineYahoo),      @"n": @"Yahoo",        @"s": @"Classic search",      @"c": YT_rgb(95, 1, 209, 1),    @"i": @"",                      @"l": @"Y"},
    ];
    CGFloat cw = 300, ch = 72, gx = 16, gy = 14;
    CGFloat x0 = (kSetupW - (cw * 2 + gx)) / 2;
    CGFloat topRowY = 262;
    [_cards removeAllObjects];
    for (NSInteger i = 0; i < (NSInteger)engines.count; i++) {
        NSDictionary *d = engines[i];
        SaturnSearchEngine eng = (SaturnSearchEngine)[d[@"e"] integerValue];
        SetupEngineCard *card = [[SetupEngineCard alloc] initWithEngine:eng name:d[@"n"] subtitle:d[@"s"] color:d[@"c"] symbol:d[@"i"] letter:d[@"l"]];
        card.frame = NSMakeRect(x0 + (i % 2) * (cw + gx), topRowY - (i / 2) * (ch + gy), cw, ch);
        card.isSelected = (eng == _selectedEngine);
        __weak typeof(self) weak = self;
        card.onSelect = ^(SaturnSearchEngine e) { [weak selectEngine:e]; };
        [_cards addObject:card];
        [pv addSubview:card];
    }
}

- (void)buildFeatures:(NSView *)pv {
    [pv addSubview:SU_label(@"Built in, not bolted on", SU_font(34, NSFontWeightMedium), Y_ink(), NSMakeRect(0, 376, kSetupW, 42), NSTextAlignmentCenter, NO)];
    [pv addSubview:SU_label(@"Everything works out of the box.", SU_font(16, NSFontWeightRegular), Y_muted(), NSMakeRect(0, 346, kSetupW, 22), NSTextAlignmentCenter, NO)];

    NSArray *rows = @[
        @[@"sparkles", @"Zarah, your AI companion", @"Ask about any page or your open tabs. Press ⌘I to open her."],
        @[@"shield.lefthalf.filled", @"Saturn Shield", @"Blocks ads and trackers on every site, with a one-click pause."],
        @[@"mic.fill", @"Talk to your browser", @"Use your voice to ask Zarah things hands-free."],
    ];
    CGFloat rw = 580, rh = 88, gap = 14;
    CGFloat x = (kSetupW - rw) / 2;
    CGFloat y = 246;
    for (NSArray *r in rows) {
        NSView *row = [[NSView alloc] initWithFrame:NSMakeRect(x, y, rw, rh)];
        row.wantsLayer = YES;
        row.layer.cornerRadius = 24;
        row.layer.backgroundColor = Y_soft().CGColor;

        NSView *icon = [[NSView alloc] initWithFrame:NSMakeRect(22, 22, 44, 44)];
        icon.wantsLayer = YES;
        icon.layer.cornerRadius = 22;
        icon.layer.backgroundColor = [NSColor whiteColor].CGColor;
        NSImageView *iv = [[NSImageView alloc] initWithFrame:NSMakeRect(11, 11, 22, 22)];
        iv.image = [NSImage imageWithSystemSymbolName:r[0] accessibilityDescription:nil];
        iv.contentTintColor = Y_blue();
        [icon addSubview:iv];
        [row addSubview:icon];

        [row addSubview:SU_label(r[1], SU_font(17, NSFontWeightMedium), Y_ink(), NSMakeRect(86, 49, rw - 110, 22), NSTextAlignmentLeft, NO)];
        [row addSubview:SU_label(r[2], SU_font(14, NSFontWeightRegular), Y_muted(), NSMakeRect(86, 16, rw - 110, 30), NSTextAlignmentLeft, YES)];
        [pv addSubview:row];
        y -= rh + gap;
    }
}

- (void)buildDone:(NSView *)pv {
    CGFloat s = 130;
    SetupCheckView *check = [[SetupCheckView alloc] initWithFrame:NSMakeRect((kSetupW - s) / 2, kPageH - 50 - s, s, s)];
    [pv addSubview:check];
    [pv addSubview:SU_label(@"You're all set", SU_font(44, NSFontWeightMedium), Y_ink(), NSMakeRect(0, 160, kSetupW, 54), NSTextAlignmentCenter, NO)];
    NSString *engine = [SaturnSearchEngineInfo infoForEngine:_selectedEngine].name ?: @"your default engine";
    NSString *sub = [NSString stringWithFormat:@"Searching with %@. Press ⌘I any time to ask Zarah.", engine];
    [pv addSubview:SU_label(sub, SU_font(18, NSFontWeightRegular), Y_muted(), NSMakeRect(130, 100, kSetupW - 260, 56), NSTextAlignmentCenter, YES)];
}

#pragma mark Actions

- (void)selectEngine:(SaturnSearchEngine)engine {
    _selectedEngine = engine;
    for (SetupEngineCard *c in _cards) [c setSelectedAnimated:(c.engine == engine)];
}

- (void)goToStep:(NSInteger)n {
    if (_busy || n < 0 || n >= kStepCount || n == _step) return;
    _busy = YES;
    _step = n;
    [self updateChromeAnimated:YES];
    NSView *old = _page;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
        ctx.duration = 0.18;
        old.animator.alphaValue = 0;
    } completionHandler:^{
        [old removeFromSuperview];
        [self installPage];
        self->_busy = NO;
    }];
}

- (void)primaryAction:(id)sender {
    (void)sender;
    if (_step < kStepCount - 1) [self goToStep:_step + 1];
    else [self finishSetupAction:nil];
}

- (void)backAction:(id)sender {
    (void)sender;
    [self goToStep:_step - 1];
}

- (void)finishSetupAction:(id)sender {
    (void)sender;
    if (_busy) return;
    _busy = YES;
    SaturnSettings.shared.defaultEngine = _selectedEngine;
    SaturnSettings.shared.hasCompletedSetup = YES;
    [SaturnSettings.shared save];

    void (^comp)(SaturnSearchEngine) = _completion;
    _completion = nil;
    SaturnSearchEngine chosen = _selectedEngine;
    NSWindow *win = self.window;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
        ctx.duration = 0.25;
        win.animator.alphaValue = 0;
    } completionHandler:^{
        [win close];
        self.window = nil;
        if (comp) comp(chosen);
    }];
}

- (void)closeSetup {
    [self.window close];
    self.window = nil;
}

@end
