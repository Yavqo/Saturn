#import "SaturnWindow.h"
#import "Supabase/SupabaseClient.h"
#import "AuthWindow.h"
#import "Settings.h"
#import "SaturnShield.h"
#import "HannaClient.h"
#import "SaturnDownloads.h"
#import "SaturnBookmarks.h"
#import "SaturnHistory.h"
#import "SaturnSession.h"
#import "SaturnPermissions.h"
#import "HannaAgent.h"
#import "SaturnUpdater.h"
#import "SaturnReporter.h"
#import "SaturnDefaultBrowser.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

#pragma mark - Yavqo palette (whole browser)
static NSColor *Y_blue()     { return [NSColor colorWithSRGBRed:0x00/255.0 green:0x64/255.0 blue:0xE0/255.0 alpha:1]; }
static NSColor *Y_blueHover(){ return [NSColor colorWithSRGBRed:0x04/255.0 green:0x57/255.0 blue:0xCB/255.0 alpha:1]; }
static NSColor *Y_ink()      { return [NSColor colorWithSRGBRed:0x1C/255.0 green:0x2B/255.0 blue:0x33/255.0 alpha:1]; }
static NSColor *Y_muted()    { return [NSColor colorWithSRGBRed:0x5D/255.0 green:0x6C/255.0 blue:0x7B/255.0 alpha:1]; }
static NSColor *Y_muted2()   { return [NSColor colorWithSRGBRed:0x64/255.0 green:0x76/255.0 blue:0x85/255.0 alpha:1]; }
static NSColor *Y_soft()     { return [NSColor colorWithSRGBRed:0xF1/255.0 green:0xF4/255.0 blue:0xF7/255.0 alpha:1]; }
static NSColor *Y_border()   { return [NSColor colorWithSRGBRed:0xDE/255.0 green:0xE3/255.0 blue:0xE9/255.0 alpha:1]; }
static NSColor *Y_hairline() { return [NSColor colorWithSRGBRed:10/255.0 green:19/255.0 blue:23/255.0 alpha:0.12]; }
static NSColor *Y_positive() { return [NSColor colorWithSRGBRed:0x31/255.0 green:0xA2/255.0 blue:0x4C/255.0 alpha:1]; }
static NSColor *Y_negative() { return [NSColor colorWithSRGBRed:0xE4/255.0 green:0x1E/255.0 blue:0x3F/255.0 alpha:1]; }

static NSColor *C_omniboxFocused()  { return Y_blue(); }
static NSColor *C_textPrimary()     { return Y_ink(); }
static NSColor *C_textSecondary()   { return Y_muted(); }
static NSColor *Y_hover()           { return [NSColor colorWithWhite:0 alpha:0.05]; }

@class SaturnFindBar;
@class SaturnSuggestView;
@class SaturnPromptCard;

// Private chrome refs for responsive layout (no header change needed)
@interface SaturnWindow ()
@property (nonatomic, strong) NSVisualEffectView *toolbarView;
@property (nonatomic, strong) NSView *toolbarHairline;
- (void)layoutChrome;
- (void)chromeDidResize:(NSNotification *)n;
- (void)bookmarkChipTapped:(NSButton *)sender;
- (void)showSecretImagePage;
- (CGFloat)currentChromeH;
- (void)toggleFavoritesBar:(id)sender;
// Pinned tabs + tab groups
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary *> *tabGroups;   // gid -> {name, color, collapsed}
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSView *> *groupChips;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSView *> *groupBars;
@property (nonatomic, assign) BOOL animateTabLayout;
- (void)tabDragMoved:(ChromeTabView *)tab;
- (void)tabDragEnded:(ChromeTabView *)tab;
- (NSMenu *)menuForTab:(ChromeTabView *)tab;
- (NSMenu *)menuForGroup:(NSString *)gid;
- (void)toggleGroupCollapse:(NSString *)gid;
- (void)closeGroupWithID:(NSString *)gid;
- (void)groupDragMoved:(NSView *)chip deltaX:(CGFloat)dx;
- (void)groupDragEnded:(NSView *)chip;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *closedTabs;
@property (nonatomic, strong) SaturnSuggestView *suggestView;
@property (nonatomic, strong) HannaAgent *hannaAgent;
@property (nonatomic, strong) NSButton *updateButton;
@property (nonatomic, strong) NSPopover *updatePopover;
@property (nonatomic, strong) NSButton *chatModeButton;
@property (nonatomic, strong) NSButton *actModeButton;
@property (nonatomic, strong) NSTextField *modeHint;
@property (nonatomic, strong) NSView *agentBar;
@property (nonatomic, strong) NSView *agentGlow;
- (void)layoutAgentOverlay;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *promptQueue;
@property (nonatomic, strong) SaturnPromptCard *promptCard;
- (void)layoutPrompt;
@property (nonatomic, assign, readwrite) BOOL isPrivate;
@property (nonatomic, strong) WKWebsiteDataStore *privateStore;
- (void)updateSuggestions;
- (void)hideSuggestions;
- (void)layoutSuggestions;
@property (nonatomic, strong) NSButton *bookmarkButton;
@property (nonatomic, copy) NSString *favoritesSignature;
- (void)rebuildFavoritesBar;
- (void)updateBookmarkButton;
@property (nonatomic, strong) NSButton *downloadsButton;
@property (nonatomic, strong) NSPopover *downloadsPopover;
@property (nonatomic, strong) CAShapeLayer *downloadsRing;
@property (nonatomic, strong) SaturnFindBar *findBar;
@property (nonatomic, assign) NSInteger findIndex;
@property (nonatomic, assign) NSInteger findCount;
- (void)showFindBar:(id)sender;
- (void)hideFindBar;
- (void)findQueryChanged;
- (void)findNextInPage:(id)sender;
- (void)findPreviousInPage:(id)sender;
- (void)layoutFindBar;
- (void)showDownloads:(id)sender;
@property (nonatomic, weak) ChromeTabView *dragTab;
@property (nonatomic, copy) NSArray<ChromeTabView *> *dragPreviewOrder;   // live order while a tab is dragged
@property (nonatomic, copy) NSString *dragPreviewGroup;
@property (nonatomic, copy) NSArray<NSDictionary *> *groupDragItems;      // views + start x while a group is dragged
@end

// Flat Yavqo chrome: white at 80% over a 20px blur, no shadow, no gradient.
static NSVisualEffectView *GlassBar(NSRect frame, NSVisualEffectMaterial material, CGFloat alpha) {
    (void)material; (void)alpha;
    NSVisualEffectView *v = [[NSVisualEffectView alloc] initWithFrame:frame];
    v.material = NSVisualEffectMaterialContentBackground;
    v.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    v.state = NSVisualEffectStateActive;
    v.wantsLayer = YES;
    v.layer.masksToBounds = NO;
    v.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    NSView *wash = [[NSView alloc] initWithFrame:v.bounds];
    wash.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    wash.wantsLayer = YES;
    wash.layer.backgroundColor = [NSColor colorWithWhite:1 alpha:0.92].CGColor;
    [v addSubview:wash];
    return v;
}

static void AddBottomHairline(NSView *parent) {
    NSView *line = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, parent.bounds.size.width, 1)];
    line.autoresizingMask = NSViewWidthSizable;
    line.wantsLayer = YES;
    line.layer.backgroundColor = Y_hairline().CGColor;
    [parent addSubview:line];
}
// Round icon button: transparent, soft fill on hover, darker while pressed.
@interface YIconButton : NSButton
@property (nonatomic, assign) BOOL onDark;   // white hover fill for dark bars
@end
@implementation YIconButton {
    NSTrackingArea *_ta;
    BOOL _inside;
}
- (void)setFrame:(NSRect)f { [super setFrame:f]; self.layer.cornerRadius = f.size.height / 2; }
- (void)setFill:(CGFloat)alpha {
    [CATransaction begin];
    [CATransaction setAnimationDuration:0.1];
    self.layer.backgroundColor = alpha > 0 ? [NSColor colorWithWhite:(self.onDark ? 1 : 0) alpha:(self.onDark ? alpha * 2 : alpha)].CGColor : [NSColor clearColor].CGColor;
    [CATransaction commit];
}
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_ta) [self removeTrackingArea:_ta];
    _ta = [[NSTrackingArea alloc] initWithRect:self.bounds options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect owner:self userInfo:nil];
    [self addTrackingArea:_ta];
}
- (void)mouseEntered:(NSEvent *)e { (void)e; _inside = YES; if (self.enabled) [self setFill:0.06]; }
- (void)mouseExited:(NSEvent *)e { (void)e; _inside = NO; [self setFill:0]; }
- (void)setEnabled:(BOOL)enabled { [super setEnabled:enabled]; if (!enabled) [self setFill:0]; }
- (void)mouseDown:(NSEvent *)e {
    if (self.enabled) [self setFill:0.12];
    [super mouseDown:e];
    [self setFill:(_inside && self.enabled) ? 0.06 : 0];
}
@end

static NSImage *Y_symbol(NSString *name, CGFloat pt, NSFontWeight weight) {
    NSImage *img = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
    if (!img) return nil;
    NSImage *cfg = [img imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:pt weight:weight]];
    return cfg ?: img;
}
static NSButton *SaturnPlainButton(NSString *symbol, SEL sel, id target, NSRect fr, CGFloat iconPt) {
    YIconButton *b = [[YIconButton alloc] initWithFrame:fr];
    b.image = Y_symbol(symbol, iconPt, NSFontWeightMedium);
    b.imagePosition = NSImageOnly;
    b.imageScaling = NSImageScaleNone;
    b.bordered = NO;
    b.wantsLayer = YES;
    b.layer.cornerRadius = fr.size.height / 2;
    b.target = target;
    b.action = sel;
    b.contentTintColor = Y_ink();
    return b;
}
static CGFloat SaturnTabBarH(void) { return 44.0; }
static CGFloat SaturnToolbarH(void) { return 56.0; }
static CGFloat SaturnBookmarksH(void) { return 32.0; }
static CGFloat SaturnProgressH(void) { return 2.0; }
static NSString *SaturnSecretImageURL(void) { return @"https://ikjugnimawkoatkbvpgk.supabase.co/storage/v1/object/public/media/2026-08-26_14.54.46.png"; }
static NSString *SaturnCleanQuery(NSString *text) {
    NSString *clean = [[text ?: @"" lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    for (NSString *p in @[@"'", @"’", @"?", @"!", @".", @"\"", @"“", @"”", @","]) {
        clean = [clean stringByReplacingOccurrencesOfString:p withString:@""];
    }
    return clean;
}
static BOOL SaturnIsSecretImageQuery(NSString *text) {
    NSString *clean = SaturnCleanQuery(text);
    if (!clean.length) return NO;
    NSArray *triggers = @[
        @"whats your favorite image", @"what is your favorite image", @"what your favorite image",
        @"whats ur favorite image", @"what is ur favorite image", @"show your favorite image",
        @"whats your favourite image", @"what is your favourite image",
        @"whats your favorite picture", @"what is your favorite picture",
        @"whats ur fav picture", @"what is ur fav picture", @"whats your fav picture",
        @"show your fav picture", @"show your favorite picture",
        @"whats ur fav image", @"show your fav image", @"favorite image", @"favourite image", @"fav picture"
    ];
    for (NSString *t in triggers) {
        if ([clean containsString:t]) return YES;
    }
    if ([clean isEqualToString:@"favorite image"] || [clean isEqualToString:@"favourite image"] || [clean isEqualToString:@"fav picture"]) return YES;
    return NO;
}

// Zarah's mark: white disc, blue ring, blue sparkles.
static NSView *HannaAvatar(CGFloat size) {
    NSView *av = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, size, size)];
    av.wantsLayer = YES;
    av.layer.cornerRadius = size / 2;
    av.layer.backgroundColor = [NSColor whiteColor].CGColor;
    av.layer.borderColor = Y_blue().CGColor;
    av.layer.borderWidth = MAX(1.5, size / 14);
    CGFloat inset = size * 0.26;
    NSImageView *iv = [[NSImageView alloc] initWithFrame:NSMakeRect(inset, inset, size - 2 * inset, size - 2 * inset)];
    iv.image = [NSImage imageWithSystemSymbolName:@"sparkles" accessibilityDescription:@"Zarah"];
    iv.contentTintColor = Y_blue();
    [av addSubview:iv];
    return av;
}

// Pill suggestion button (icon + label) with hover state. The prompt lives in `identifier`.
@interface HannaPillButton : NSButton
@property (nonatomic, strong) NSTrackingArea *hoverArea;
@end
@implementation HannaPillButton
- (NSView *)hitTest:(NSPoint)p { return NSPointInRect(p, self.frame) ? self : nil; }
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (self.hoverArea) [self removeTrackingArea:self.hoverArea];
    self.hoverArea = [[NSTrackingArea alloc] initWithRect:self.bounds options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways owner:self userInfo:nil];
    [self addTrackingArea:self.hoverArea];
}
- (void)mouseEntered:(NSEvent *)e { (void)e; self.layer.backgroundColor = Y_soft().CGColor; }
- (void)mouseExited:(NSEvent *)e { (void)e; self.layer.backgroundColor = [NSColor whiteColor].CGColor; }
@end

// Empty state shown before the first message. Laid out full width by HannaChatDocView.
@interface HannaEmptyState : NSView
@end
@implementation HannaEmptyState
@end

#pragma mark - Zarah Chat Document View (Flipped for top-to-bottom messages)
@interface HannaChatDocView : NSView
@property (nonatomic, strong) NSMutableArray<NSView *> *messageViews;
- (void)clearAll;
- (void)addMessageView:(NSView *)view;
- (void)removeMessageView:(NSView *)view;
- (void)relayout;
@end

@implementation HannaChatDocView {
    NSMutableArray<NSView *> *_messageViews;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _messageViews = [NSMutableArray array];
        self.wantsLayer = YES;
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (NSMutableArray<NSView *> *)messageViews {
    return _messageViews;
}

- (void)clearAll {
    for (NSView *v in [_messageViews copy]) {
        [v removeFromSuperview];
    }
    [_messageViews removeAllObjects];
    [self relayout];
}

- (void)addMessageView:(NSView *)view {
    [_messageViews addObject:view];
    [self addSubview:view];
    [self relayout];
}

- (void)removeMessageView:(NSView *)view {
    [view removeFromSuperview];
    [_messageViews removeObject:view];
    [self relayout];
}

- (void)relayout {
    CGFloat W = self.enclosingScrollView.contentSize.width > 0 ? self.enclosingScrollView.contentSize.width : self.bounds.size.width;
    CGFloat y = 14;
    CGFloat pad = 6;

    for (NSView *v in _messageViews) {
        NSRect f = v.frame;
        f.origin.y = y;
        if ([v.identifier isEqualToString:@"fullWidth"] || [v isKindOfClass:[HannaEmptyState class]]) {
            f.origin.x = pad;
            f.size.width = W - (pad * 2);
        } else if ([v.identifier isEqualToString:@"userRow"]) {
            f.origin.x = W - f.size.width - pad;
        } else {
            f.origin.x = pad;
        }
        v.frame = f;
        y += f.size.height + 12;
    }

    CGFloat minH = self.enclosingScrollView.contentSize.height;
    CGFloat totalH = MAX(y + 20, minH);
    [self setFrameSize:NSMakeSize(W, totalH)];
}
@end

#pragma mark - Markdown Formatter
static NSAttributedString *AttrForMarkdownColored(NSString *markdown, CGFloat fontSize, NSColor *textColor, BOOL light) {
    if (!markdown.length) return [[NSAttributedString alloc] initWithString:@""];
    NSAttributedString *attr = nil;
    if (@available(macOS 12.0, *)) {
        NSError *err = nil;
        attr = [[NSAttributedString alloc] initWithMarkdownString:markdown options:nil baseURL:nil error:&err];
        if (err || !attr) attr = nil;
    }
    if (!attr) {
        NSData *data = [markdown dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *opts = @{NSDocumentTypeDocumentAttribute: @"net.daringfireball.markdown", NSCharacterEncodingDocumentAttribute: @(NSUTF8StringEncoding)};
        attr = [[NSAttributedString alloc] initWithData:data options:opts documentAttributes:nil error:nil];
    }
    if (!attr) {
        attr = [[NSAttributedString alloc] initWithString:markdown attributes:@{
            NSForegroundColorAttributeName: textColor,
            NSFontAttributeName: [NSFont systemFontOfSize:fontSize]
        }];
    }

    NSMutableAttributedString *out = [[NSMutableAttributedString alloc] initWithAttributedString:attr];
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.lineSpacing = 3.5;
    style.paragraphSpacing = 6.0;
    [out addAttributes:@{
        NSForegroundColorAttributeName: textColor,
        NSFontAttributeName: [NSFont systemFontOfSize:fontSize weight:NSFontWeightRegular],
        NSParagraphStyleAttributeName: style
    } range:NSMakeRange(0, out.length)];

    // Apply monospace font and accent highlight for inline code and code blocks
    [out enumerateAttribute:NSFontAttributeName inRange:NSMakeRange(0, out.length) options:0 usingBlock:^(id value, NSRange range, BOOL *stop){
        (void)stop;
        NSFont *f = value;
        if (f && ([[f familyName] containsString:@"Menlo"] || [[f fontName] containsString:@"Mono"] || [[f fontName] containsString:@"Courier"])) {
            NSFont *mf = [NSFont monospacedSystemFontOfSize:fontSize - 1 weight:NSFontWeightMedium];
            [out addAttribute:NSFontAttributeName value:mf range:range];
            [out addAttribute:NSBackgroundColorAttributeName value:(light ? [NSColor colorWithRed:0.945 green:0.957 blue:0.969 alpha:1] : [NSColor colorWithWhite:1 alpha:0.08]) range:range];
            [out addAttribute:NSForegroundColorAttributeName value:(light ? textColor : [NSColor colorWithRed:0.75 green:0.85 blue:1.0 alpha:1.0]) range:range];
        }
    }];
    return out;
}

static NSAttributedString *AttrForMarkdown(NSString *markdown, CGFloat fontSize) {
    return AttrForMarkdownColored(markdown, fontSize, [NSColor colorWithWhite:0.95 alpha:1.0], NO);
}

#pragma mark - Zarah Explain Bubble Controller (Floating explanation popup)
@interface HannaExplainBubbleController : NSViewController
@property (nonatomic, copy) NSString *selectedText;
@property (nonatomic, copy) NSString *explanation;
@property (nonatomic, copy) void (^onClose)(void);
- (instancetype)initWithSelectedText:(NSString *)text;
- (void)showExplanation:(NSString *)explanation isError:(BOOL)isError;
- (void)showSecretImageURL:(NSString *)imageURL caption:(NSString *)caption;
@end

@implementation HannaExplainBubbleController {
    NSVisualEffectView *_rootEffectView;
    NSTextField *_quoteLabel;
    NSView *_loadingView;
    NSProgressIndicator *_spinner;
    NSTextField *_loadingLabel;
    NSScrollView *_scrollView;
    NSTextView *_textView;
    NSImageView *_secretImageView;
    NSButton *_copyBtn;
    NSButton *_closeBtn;
}

- (instancetype)initWithSelectedText:(NSString *)text {
    self = [super init];
    if (self) {
        _selectedText = [text copy];
    }
    return self;
}

- (void)loadView {
    NSRect frame = NSMakeRect(0, 0, 390, 260);
    _rootEffectView = [[NSVisualEffectView alloc] initWithFrame:frame];
    _rootEffectView.material = NSVisualEffectMaterialPopover;
    _rootEffectView.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    _rootEffectView.state = NSVisualEffectStateActive;
    _rootEffectView.wantsLayer = YES;
    _rootEffectView.layer.cornerRadius = 24;
    _rootEffectView.layer.masksToBounds = YES;
    _rootEffectView.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];

    // White surface
    NSView *tint = [[NSView alloc] initWithFrame:_rootEffectView.bounds];
    tint.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    tint.wantsLayer = YES;
    tint.layer.backgroundColor = [NSColor whiteColor].CGColor;
    [_rootEffectView addSubview:tint positioned:NSWindowBelow relativeTo:nil];

    CGFloat W = frame.size.width;
    CGFloat H = frame.size.height;

    // 1. Header (y = H - 34, height 34)
    NSTextField *iconLabel = [NSTextField labelWithString:@"✦"];
    iconLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightBold];
    iconLabel.textColor = Y_blue();
    iconLabel.frame = NSMakeRect(14, H - 30, 18, 20);
    [_rootEffectView addSubview:iconLabel];

    NSTextField *titleLabel = [NSTextField labelWithString:@"Zarah Explains"];
    titleLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    titleLabel.textColor = Y_ink();
    titleLabel.frame = NSMakeRect(34, H - 30, 200, 20);
    [_rootEffectView addSubview:titleLabel];

    _closeBtn = [NSButton buttonWithTitle:@"×" target:self action:@selector(closeAction:)];
    _closeBtn.frame = NSMakeRect(W - 32, H - 28, 20, 20);
    _closeBtn.bezelStyle = NSBezelStyleCircular;
    _closeBtn.bordered = NO;
    _closeBtn.font = [NSFont systemFontOfSize:14];
    _closeBtn.wantsLayer = YES;
    _closeBtn.layer.backgroundColor = Y_soft().CGColor;
    _closeBtn.layer.cornerRadius = 10;
    _closeBtn.contentTintColor = Y_ink();
    [_rootEffectView addSubview:_closeBtn];

    // 2. Quote Pill (y = H - 66, height 28)
    NSView *quoteBox = [[NSView alloc] initWithFrame:NSMakeRect(14, H - 66, W - 28, 28)];
    quoteBox.wantsLayer = YES;
    quoteBox.layer.cornerRadius = 12;
    quoteBox.layer.backgroundColor = Y_soft().CGColor;

    NSString *displayQuote = self.selectedText ?: @"";
    if (displayQuote.length > 90) {
        displayQuote = [NSString stringWithFormat:@"%@…", [displayQuote substringToIndex:88]];
    }
    displayQuote = [displayQuote stringByReplacingOccurrencesOfString:@"\n" withString:@" "];

    _quoteLabel = [NSTextField labelWithString:[NSString stringWithFormat:@"“%@”", displayQuote]];
    _quoteLabel.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightRegular];
    _quoteLabel.textColor = Y_muted();
    _quoteLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _quoteLabel.frame = NSMakeRect(8, 5, quoteBox.bounds.size.width - 16, 18);
    [quoteBox addSubview:_quoteLabel];
    [_rootEffectView addSubview:quoteBox];

    // 3. Loading Container (y = 44, height = H - 66 - 44 - 6 = 144)
    CGFloat contentY = 44;
    CGFloat contentH = H - 66 - contentY - 6;
    _loadingView = [[NSView alloc] initWithFrame:NSMakeRect(14, contentY, W - 28, contentH)];

    _spinner = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect((W - 28)/2 - 12, contentH/2 - 2, 24, 24)];
    _spinner.style = NSProgressIndicatorStyleSpinning;
    _spinner.controlSize = NSControlSizeSmall;
    _spinner.displayedWhenStopped = NO;
    [_spinner startAnimation:nil];
    [_loadingView addSubview:_spinner];

    _loadingLabel = [NSTextField labelWithString:@"Explaining with Zarah…"];
    _loadingLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    _loadingLabel.textColor = Y_muted();
    _loadingLabel.alignment = NSTextAlignmentCenter;
    _loadingLabel.frame = NSMakeRect(0, contentH/2 - 26, W - 28, 18);
    [_loadingView addSubview:_loadingLabel];

    [_rootEffectView addSubview:_loadingView];

    // 4. Scrollable Text Area
    _scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(14, contentY, W - 28, contentH)];
    _scrollView.hasVerticalScroller = YES;
    _scrollView.hasHorizontalScroller = NO;
    _scrollView.autohidesScrollers = YES;
    _scrollView.borderType = NSNoBorder;
    _scrollView.drawsBackground = NO;
    _scrollView.backgroundColor = [NSColor clearColor];
    _scrollView.hidden = YES;

    _textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, _scrollView.contentSize.width, _scrollView.contentSize.height)];
    _textView.editable = NO;
    _textView.selectable = YES;
    _textView.drawsBackground = NO;
    _textView.backgroundColor = [NSColor clearColor];
    _textView.textContainerInset = NSMakeSize(0, 2);
    _textView.verticallyResizable = YES;
    _textView.horizontallyResizable = NO;
    _textView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_textView.textContainer setWidthTracksTextView:YES];
    [_textView.textContainer setContainerSize:NSMakeSize(_scrollView.contentSize.width, CGFLOAT_MAX)];
    _textView.textContainer.lineFragmentPadding = 0;
    _scrollView.documentView = _textView;
    [_rootEffectView addSubview:_scrollView];

    // 5. Secret Image View (hidden by default)
    _secretImageView = [[NSImageView alloc] initWithFrame:NSMakeRect(14, 44, W - 28, 180)];
    _secretImageView.wantsLayer = YES;
    _secretImageView.layer.cornerRadius = 10;
    _secretImageView.layer.masksToBounds = YES;
    _secretImageView.layer.borderColor = Y_hairline().CGColor;
    _secretImageView.layer.borderWidth = 0.5;
    _secretImageView.imageScaling = NSImageScaleProportionallyUpOrDown;
    _secretImageView.hidden = YES;
    [_rootEffectView addSubview:_secretImageView];

    // 6. Footer (y = 8, height = 30)
    _copyBtn = [NSButton buttonWithTitle:@"Copy Explanation" target:self action:@selector(copyAction:)];
    _copyBtn.frame = NSMakeRect(14, 8, W - 28, 28);
    _copyBtn.bezelStyle = NSBezelStyleRounded;
    _copyBtn.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightMedium];
    _copyBtn.wantsLayer = YES;
    _copyBtn.layer.backgroundColor = Y_blue().CGColor;
    _copyBtn.layer.cornerRadius = 14;
    _copyBtn.contentTintColor = [NSColor whiteColor];
    [_rootEffectView addSubview:_copyBtn];

    self.view = _rootEffectView;
}

- (void)showExplanation:(NSString *)explanation isError:(BOOL)isError {
    _explanation = [explanation copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_spinner stopAnimation:nil];
        self->_loadingView.hidden = YES;
        self->_scrollView.hidden = NO;
        self->_secretImageView.hidden = YES;

        NSAttributedString *attr = nil;
        if (isError) {
            attr = [[NSAttributedString alloc] initWithString:explanation ?: @"" attributes:@{
                NSForegroundColorAttributeName: Y_negative(),
                NSFontAttributeName: [NSFont systemFontOfSize:12.5 weight:NSFontWeightMedium]
            }];
        } else {
            attr = AttrForMarkdownColored(explanation, 13, Y_ink(), YES);
        }
        self->_textView.textStorage.attributedString = attr;
    });
}

- (void)showSecretImageURL:(NSString *)imageURL caption:(NSString *)caption {
    _explanation = [caption copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_spinner stopAnimation:nil];
        self->_loadingView.hidden = YES;

        // Resize popover view to 390x350 for gorgeous photo presentation
        NSRect r = self.view.frame;
        r.size.height = 350;
        self.view.frame = r;
        self.preferredContentSize = r.size;

        CGFloat W = r.size.width;
        CGFloat H = r.size.height;

        // Reposition header & quote box for taller height
        for (NSView *v in self.view.subviews) {
            if ([v isKindOfClass:[NSTextField class]] && [(NSTextField *)v stringValue] && [[(NSTextField *)v stringValue] isEqualToString:@"✦"]) {
                v.frame = NSMakeRect(14, H - 30, 18, 20);
            } else if ([v isKindOfClass:[NSTextField class]] && [(NSTextField *)v stringValue] && [[(NSTextField *)v stringValue] isEqualToString:@"Zarah Explains"]) {
                v.frame = NSMakeRect(34, H - 30, 200, 20);
            }
        }
        self->_closeBtn.frame = NSMakeRect(W - 32, H - 28, 20, 20);

        // Quote Box
        for (NSView *v in self.view.subviews) {
            if (v.layer.cornerRadius == 12 && ![v isKindOfClass:[NSVisualEffectView class]]) {
                v.frame = NSMakeRect(14, H - 64, W - 28, 26);
            }
        }

        // Caption above image
        self->_scrollView.hidden = NO;
        self->_scrollView.frame = NSMakeRect(14, H - 96, W - 28, 26);
        self->_textView.textStorage.attributedString = AttrForMarkdownColored(caption ?: @"✨ Here is my favorite image! 🪐", 13, Y_ink(), YES);

        // Image View
        self->_secretImageView.hidden = NO;
        self->_secretImageView.frame = NSMakeRect(14, 46, W - 28, H - 96 - 46 - 8);

        // Load image asynchronously
        NSURL *url = [NSURL URLWithString:imageURL];
        if (url) {
            [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
                (void)resp; (void)err;
                if (data) {
                    NSImage *img = [[NSImage alloc] initWithData:data];
                    if (img) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            self->_secretImageView.image = img;
                        });
                    }
                }
            }].resume;
        }

        self->_copyBtn.title = @"Copy Image Link";
    });
}

- (void)copyAction:(id)sender {
    if (_explanation.length) {
        [[NSPasteboard generalPasteboard] clearContents];
        [[NSPasteboard generalPasteboard] setString:_explanation forType:NSPasteboardTypeString];
        _copyBtn.title = @"✓ Copied!";
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            self->_copyBtn.title = @"Copy Explanation";
        });
    }
}

- (void)closeAction:(id)sender {
    if (self.onClose) {
        self.onClose();
    }
}
@end

#pragma mark - SaturnWebView (Subclass of WKWebView to intercept right-clicks)
@interface SaturnWebView : WKWebView
@property (nonatomic, weak) SaturnWindow *saturnWindow;
- (NSMenu *)customContextMenuForEvent:(NSEvent *)event;
@end

static NSMenu * (*orig_WKContentView_menuForEvent)(id, SEL, NSEvent *) = NULL;

static NSMenu * Saturn_WKContentView_menuForEvent(id self, SEL _cmd, NSEvent *event) {
    NSView *v = (NSView *)self;
    while (v && ![v isKindOfClass:[SaturnWebView class]]) {
        v = v.superview;
    }
    if ([v isKindOfClass:[SaturnWebView class]]) {
        SaturnWebView *swv = (SaturnWebView *)v;
        NSMenu *m = [swv customContextMenuForEvent:event];
        if (m) return m;
    }
    if (orig_WKContentView_menuForEvent) {
        return orig_WKContentView_menuForEvent(self, _cmd, event);
    }
    return nil;
}

static void EnsureWKContentViewSwizzled(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"WKContentView");
        if (cls) {
            Method m = class_getInstanceMethod(cls, @selector(menuForEvent:));
            if (m) {
                orig_WKContentView_menuForEvent = (NSMenu *(*)(id, SEL, NSEvent *))method_getImplementation(m);
                method_setImplementation(m, (IMP)Saturn_WKContentView_menuForEvent);
            }
        }
    });
}

@implementation SaturnWebView
- (NSMenu *)customContextMenuForEvent:(NSEvent *)event {
    if ([self.saturnWindow respondsToSelector:@selector(buildCustomContextMenuForEvent:webView:)]) {
        return [self.saturnWindow buildCustomContextMenuForEvent:event webView:self];
    }
    return nil;
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
    NSMenu *m = [self customContextMenuForEvent:event];
    if (m) return m;
    return [super menuForEvent:event];
}

- (void)rightMouseDown:(NSEvent *)event {
    NSMenu *m = [self customContextMenuForEvent:event];
    if (m) {
        [NSMenu popUpContextMenu:m withEvent:event forView:self];
        return;
    }
    [super rightMouseDown:event];
}
@end

#pragma mark - ChromeTabView (flat pill tabs)
@implementation ChromeTabView {
    NSTextField *_titleLabel;
    NSImageView *_faviconView;
    YIconButton *_closeBtn;
    CAShapeLayer *_spinner;
    NSTrackingArea *_trackArea;
    NSPoint _downPoint;
    CGFloat _downX;
    BOOL _dragging;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    CGFloat h = frame.size.height;
    self.wantsLayer = YES;
    self.layer.cornerRadius = h / 2;
    self.layer.masksToBounds = YES;
    _active = YES;
    _tabIndex = NSNotFound;

    _faviconView = [[NSImageView alloc] initWithFrame:NSMakeRect(14, (h - 18) / 2, 18, 18)];
    _faviconView.imageScaling = NSImageScaleProportionallyUpOrDown;
    _faviconView.contentTintColor = Y_muted2();
    _faviconView.wantsLayer = YES;
    _faviconView.layer.cornerRadius = 5;
    _faviconView.layer.masksToBounds = YES;
    [self addSubview:_faviconView];

    // Loading ring drawn around the favicon
    _spinner = [CAShapeLayer layer];
    _spinner.frame = CGRectMake(11, (h - 24) / 2, 24, 24);
    CGMutablePathRef arc = CGPathCreateMutable();
    CGPathAddArc(arc, NULL, 12, 12, 10, 0, 1.5 * M_PI, NO);
    _spinner.path = arc; CGPathRelease(arc);
    _spinner.fillColor = NULL;
    _spinner.strokeColor = Y_blue().CGColor;
    _spinner.lineWidth = 2;
    _spinner.lineCap = kCALineCapRound;
    _spinner.hidden = YES;
    [self.layer addSublayer:_spinner];

    _titleLabel = [NSTextField labelWithString:@"New Tab"];
    _titleLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightRegular];
    _titleLabel.textColor = Y_ink();
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self addSubview:_titleLabel];

    _closeBtn = [[YIconButton alloc] initWithFrame:NSMakeRect(0, 0, 22, 22)];
    _closeBtn.image = Y_symbol(@"xmark", 9, NSFontWeightBold);
    _closeBtn.imagePosition = NSImageOnly;
    _closeBtn.imageScaling = NSImageScaleNone;
    _closeBtn.bordered = NO;
    _closeBtn.wantsLayer = YES;
    _closeBtn.layer.cornerRadius = 11;
    _closeBtn.target = self;
    _closeBtn.action = @selector(closeTab:);
    _closeBtn.contentTintColor = Y_muted();
    _closeBtn.toolTip = @"Close tab";
    [self addSubview:_closeBtn];

    _trackArea = [[NSTrackingArea alloc] initWithRect:self.bounds options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect owner:self userInfo:nil];
    [self addTrackingArea:_trackArea];
    [self layoutContents];
    [self updateAppearance];
    return self;
}

- (void)setFrameSize:(NSSize)s { [super setFrameSize:s]; [self layoutContents]; }

- (void)layoutContents {
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    if (_pinned) {
        _faviconView.frame = NSMakeRect((w - 18) / 2, (h - 18) / 2, 18, 18);
        _spinner.frame = CGRectMake((w - 24) / 2, (h - 24) / 2, 24, 24);
        _titleLabel.hidden = YES;
        _closeBtn.hidden = YES;
        return;
    }
    _faviconView.frame = NSMakeRect(14, (h - 18) / 2, 18, 18);
    _spinner.frame = CGRectMake(11, (h - 24) / 2, 24, 24);
    _titleLabel.hidden = NO;
    _titleLabel.frame = NSMakeRect(42, (h - 18) / 2, MAX(10, w - 42 - 36), 18);
    _closeBtn.frame = NSMakeRect(w - 30, (h - 22) / 2, 22, 22);
}

- (void)setPinned:(BOOL)pinned {
    _pinned = pinned;
    [self layoutContents];
    [self updateAppearance];
}

- (void)setDropTarget:(BOOL)dropTarget {
    if (_dropTarget == dropTarget) return;
    _dropTarget = dropTarget;
    [self updateAppearance];
}

- (void)setLoading:(BOOL)loading {
    if (_loading == loading) return;
    _loading = loading;
    _spinner.hidden = !loading;
    _faviconView.alphaValue = loading ? 0.35 : 1;
    if (loading) {
        CABasicAnimation *spin = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
        spin.fromValue = @0; spin.toValue = @(-2 * M_PI);
        spin.duration = 0.9; spin.repeatCount = HUGE_VALF;
        [_spinner addAnimation:spin forKey:@"spin"];
    } else {
        [_spinner removeAnimationForKey:@"spin"];
    }
}

- (void)playAppear {
    CABasicAnimation *o = [CABasicAnimation animationWithKeyPath:@"opacity"];
    o.fromValue = @0; o.toValue = @1; o.duration = 0.25;
    [self.layer addAnimation:o forKey:@"appear.fade"];
    CABasicAnimation *r = [CABasicAnimation animationWithKeyPath:@"transform.translation.y"];
    r.fromValue = @(-8); r.toValue = @0; r.duration = 0.25;
    r.timingFunction = [CAMediaTimingFunction functionWithControlPoints:.12 :.8 :.32 :1];
    [self.layer addAnimation:r forKey:@"appear.rise"];
}

- (void)updateTitle:(NSString *)title favicon:(NSImage *)icon active:(BOOL)active {
    _titleLabel.stringValue = title.length ? title : @"New Tab";
    if (title) { _title = [title copy]; self.toolTip = title; }
    if (icon) {
        _favicon = icon;
        _faviconView.image = icon;
    }
    _active = active;
    [self updateAppearance];
}

- (void)setPrivateMode:(BOOL)privateMode {
    _privateMode = privateMode;
    _faviconView.contentTintColor = privateMode ? [NSColor colorWithWhite:1 alpha:0.7] : Y_muted2();
    _closeBtn.onDark = privateMode;
    [self updateAppearance];
}

- (void)updateAppearance {
    [CATransaction begin];
    [CATransaction setAnimationDuration:0.15];
    if (_privateMode) {
        // Private windows: dark tab bar, light text
        if (_active) {
            self.layer.backgroundColor = [NSColor colorWithWhite:1 alpha:0.16].CGColor;
            _titleLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
            _titleLabel.textColor = [NSColor whiteColor];
            _closeBtn.hidden = NO;
        } else {
            self.layer.backgroundColor = [NSColor colorWithWhite:1 alpha:_hovered ? 0.09 : 0].CGColor;
            _titleLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightRegular];
            _titleLabel.textColor = [NSColor colorWithWhite:1 alpha:0.65];
            _closeBtn.hidden = !_hovered;
        }
        self.layer.borderColor = [NSColor clearColor].CGColor;
        self.layer.borderWidth = 1;
        _closeBtn.contentTintColor = [NSColor colorWithWhite:1 alpha:0.7];
        if (_pinned) _closeBtn.hidden = YES;
        if (_dropTarget) { self.layer.borderColor = Y_blue().CGColor; self.layer.borderWidth = 2; }
        [CATransaction commit];
        return;
    }
    if (_active) {
        self.layer.backgroundColor = [NSColor whiteColor].CGColor;
        self.layer.borderColor = Y_hairline().CGColor;
        self.layer.borderWidth = 1;
        _titleLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
        _titleLabel.textColor = Y_ink();
        _closeBtn.hidden = NO;
    } else {
        self.layer.backgroundColor = (_hovered ? Y_hover() : [NSColor clearColor]).CGColor;
        self.layer.borderColor = [NSColor clearColor].CGColor;
        self.layer.borderWidth = 1;
        _titleLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightRegular];
        _titleLabel.textColor = Y_muted();
        _closeBtn.hidden = !_hovered;
    }
    if (_pinned) _closeBtn.hidden = YES;
    if (_dropTarget) {
        self.layer.borderColor = Y_blue().CGColor;
        self.layer.borderWidth = 2;
    }
    [CATransaction commit];
}

- (void)mouseEntered:(NSEvent *)event { (void)event; _hovered = YES; [self updateAppearance]; }
- (void)mouseExited:(NSEvent *)event { (void)event; _hovered = NO; [self updateAppearance]; }

- (void)mouseDown:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    if (!_closeBtn.hidden && NSPointInRect(loc, _closeBtn.frame)) { [super mouseDown:event]; return; }
    _downPoint = [self.superview convertPoint:event.locationInWindow fromView:nil];
    _downX = self.frame.origin.x;
    _dragging = NO;
    if (self.hostWindow && self.tabIndex != NSNotFound) {
        [self.hostWindow switchToTabAtIndex:self.tabIndex];
    }
}

- (void)mouseDragged:(NSEvent *)event {
    if (!self.hostWindow) return;
    NSPoint p = [self.superview convertPoint:event.locationInWindow fromView:nil];
    if (!_dragging) {
        if (fabs(p.x - _downPoint.x) < 5) return;
        _dragging = YES;
        [self.superview addSubview:self positioned:NSWindowAbove relativeTo:nil];
        self.alphaValue = 0.92;
    }
    NSRect f = self.frame;
    f.origin.x = MAX(0, _downX + (p.x - _downPoint.x));
    self.frame = f;
    [self.hostWindow tabDragMoved:self];
}

- (void)mouseUp:(NSEvent *)event {
    (void)event;
    if (_dragging) {
        _dragging = NO;
        self.alphaValue = 1;
        [self.hostWindow tabDragEnded:self];
    }
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
    (void)event;
    return [self.hostWindow menuForTab:self];
}

- (void)closeTab:(id)sender {
    (void)sender;
    if (self.hostWindow) [self.hostWindow closeTabView:self];
    else [self.window close];
}
@end

#pragma mark - Tab groups

static NSArray<NSColor *> *YGroupColors(void) {
    return @[Y_blue(), Y_negative(), Y_positive(),
             [NSColor colorWithSRGBRed:0xF7/255.0 green:0xB9/255.0 blue:0x28/255.0 alpha:1],
             [NSColor colorWithSRGBRed:0x7B/255.0 green:0x61/255.0 blue:0xFF/255.0 alpha:1],
             Y_muted()];
}
static NSArray<NSString *> *YGroupColorNames(void) { return @[@"Blue", @"Red", @"Green", @"Yellow", @"Purple", @"Grey"]; }

@interface GroupChipView : NSView
@property (nonatomic, copy) NSString *groupID;
@property (nonatomic, weak) SaturnWindow *hostWindow;
- (void)configureWithText:(NSString *)text colorIndex:(NSInteger)idx collapsed:(BOOL)collapsed;
@end

@implementation GroupChipView {
    NSTextField *_label;
    YIconButton *_close;
    NSTrackingArea *_area;
    NSPoint _downPoint;
    BOOL _dragging;
    BOOL _hasText;
    BOOL _collapsed;
}
- (instancetype)initWithFrame:(NSRect)f {
    self = [super initWithFrame:f];
    if (!self) return nil;
    self.wantsLayer = YES;
    self.layer.cornerRadius = 12;
    _label = [NSTextField labelWithString:@""];
    _label.font = [NSFont systemFontOfSize:12 weight:NSFontWeightBold];
    _label.alignment = NSTextAlignmentCenter;
    _label.lineBreakMode = NSLineBreakByTruncatingTail;
    [self addSubview:_label];

    _close = [[YIconButton alloc] initWithFrame:NSMakeRect(0, 0, 18, 18)];
    _close.image = Y_symbol(@"xmark", 8, NSFontWeightHeavy);
    _close.imagePosition = NSImageOnly;
    _close.imageScaling = NSImageScaleNone;
    _close.bordered = NO;
    _close.wantsLayer = YES;
    _close.layer.cornerRadius = 9;
    _close.target = self;
    _close.action = @selector(closeGroup:);
    _close.toolTip = @"Collapse group (click the group to reopen)";
    _close.hidden = YES;
    [self addSubview:_close];
    return self;
}
- (void)configureWithText:(NSString *)text colorIndex:(NSInteger)idx collapsed:(BOOL)collapsed {
    _collapsed = collapsed;
    if (collapsed) { _close.hidden = YES; _label.hidden = NO; }
    NSArray<NSColor *> *colors = YGroupColors();
    NSColor *c = colors[MAX(0, MIN((NSInteger)colors.count - 1, idx))];
    NSColor *fg = (idx == 3) ? Y_ink() : [NSColor whiteColor];
    self.layer.backgroundColor = c.CGColor;
    _label.stringValue = text;
    _label.textColor = fg;
    _close.contentTintColor = fg;
    _hasText = text.length > 0;
    [self setNeedsLayout:YES];
}
- (void)layout {
    [super layout];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    _label.frame = NSMakeRect(10, (h - 16) / 2, MAX(0, w - 10 - (_hasText ? 24 : 10)), 16);
    _close.frame = _hasText ? NSMakeRect(w - 22, (h - 18) / 2, 18, 18) : NSMakeRect((w - 18) / 2, (h - 18) / 2, 18, 18);
}
- (void)setFrameSize:(NSSize)s { [super setFrameSize:s]; [self setNeedsLayout:YES]; }
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_area) [self removeTrackingArea:_area];
    _area = [[NSTrackingArea alloc] initWithRect:self.bounds options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect owner:self userInfo:nil];
    [self addTrackingArea:_area];
}
- (void)mouseEntered:(NSEvent *)e { (void)e; if (_collapsed) return; _close.hidden = NO; if (!_hasText) _label.hidden = YES; }
- (void)mouseExited:(NSEvent *)e { (void)e; _close.hidden = YES; _label.hidden = NO; }
- (void)closeGroup:(id)sender { (void)sender; [self.hostWindow toggleGroupCollapse:self.groupID]; }

// Click toggles collapse; dragging moves the whole group.
- (void)mouseDown:(NSEvent *)event {
    _downPoint = [self.superview convertPoint:event.locationInWindow fromView:nil];
    _dragging = NO;
}
- (void)mouseDragged:(NSEvent *)event {
    NSPoint p = [self.superview convertPoint:event.locationInWindow fromView:nil];
    if (!_dragging && fabs(p.x - _downPoint.x) < 5) return;
    _dragging = YES;
    [self.hostWindow groupDragMoved:self deltaX:p.x - _downPoint.x];
}
- (void)mouseUp:(NSEvent *)event {
    (void)event;
    if (_dragging) { _dragging = NO; [self.hostWindow groupDragEnded:self]; }
    else [self.hostWindow toggleGroupCollapse:self.groupID];
}
- (NSMenu *)menuForEvent:(NSEvent *)event { (void)event; return [self.hostWindow menuForGroup:self.groupID]; }
@end

#pragma mark - Rename group sheet (custom modal)

// Borderless panels can't become key by default, which the text field needs.
@interface YSheetPanel : NSPanel
@end
@implementation YSheetPanel
- (BOOL)canBecomeKeyWindow { return YES; }
@end

@interface YSheetButton : NSButton
@property (nonatomic, assign) BOOL primary;
- (instancetype)initWithTitle:(NSString *)title primary:(BOOL)primary frame:(NSRect)frame;
@end
@implementation YSheetButton {
    NSTrackingArea *_ta;
}
- (instancetype)initWithTitle:(NSString *)title primary:(BOOL)primary frame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _primary = primary;
    self.bordered = NO;
    self.wantsLayer = YES;
    self.layer.cornerRadius = frame.size.height / 2;
    NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
    ps.alignment = NSTextAlignmentCenter;
    self.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{
        NSForegroundColorAttributeName: primary ? [NSColor whiteColor] : Y_ink(),
        NSFontAttributeName: [NSFont systemFontOfSize:14 weight:NSFontWeightBold],
        NSParagraphStyleAttributeName: ps }];
    [self applyHover:NO];
    return self;
}
- (void)applyHover:(BOOL)hover {
    NSColor *c = _primary ? (hover ? Y_blueHover() : Y_blue())
                          : (hover ? [NSColor colorWithSRGBRed:0xE4/255.0 green:0xE9/255.0 blue:0xEE/255.0 alpha:1] : Y_soft());
    [CATransaction begin];
    [CATransaction setAnimationDuration:0.2];
    self.layer.backgroundColor = c.CGColor;
    [CATransaction commit];
}
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_ta) [self removeTrackingArea:_ta];
    _ta = [[NSTrackingArea alloc] initWithRect:self.bounds options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect owner:self userInfo:nil];
    [self addTrackingArea:_ta];
}
- (void)mouseEntered:(NSEvent *)e { (void)e; [self applyHover:YES]; }
- (void)mouseExited:(NSEvent *)e { (void)e; [self applyHover:NO]; }
@end

// Round colour swatch; the selected one wears an ink ring.
@interface YSwatch : NSButton
@property (nonatomic, assign) BOOL chosen;
- (instancetype)initWithColor:(NSColor *)color frame:(NSRect)frame;
@end
@implementation YSwatch {
    CALayer *_dot;
}
- (instancetype)initWithColor:(NSColor *)color frame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.bordered = NO;
    self.title = @"";
    self.wantsLayer = YES;
    self.layer.cornerRadius = frame.size.width / 2;
    self.layer.borderWidth = 2;
    _dot = [CALayer layer];
    _dot.frame = CGRectInset(self.bounds, 4, 4);
    _dot.cornerRadius = _dot.frame.size.width / 2;
    _dot.backgroundColor = color.CGColor;
    [self.layer addSublayer:_dot];
    [self setChosen:NO];
    return self;
}
- (void)setChosen:(BOOL)chosen {
    _chosen = chosen;
    [CATransaction begin];
    [CATransaction setAnimationDuration:0.15];
    self.layer.borderColor = (chosen ? Y_ink() : [NSColor clearColor]).CGColor;
    [CATransaction commit];
}
@end

@interface YRenameSheet : NSObject <NSTextFieldDelegate>
+ (void)presentOnWindow:(NSWindow *)parent name:(NSString *)name colorIndex:(NSInteger)colorIndex
             completion:(void (^)(NSString *name, NSInteger colorIndex))done;
@end

static YRenameSheet *sActiveRenameSheet;

@implementation YRenameSheet {
    YSheetPanel *_panel;
    __weak NSWindow *_parent;
    NSTextField *_field;
    NSView *_fieldBox;
    NSArray<YSwatch *> *_swatches;
    NSInteger _color;
    void (^_done)(NSString *, NSInteger);
}

+ (void)presentOnWindow:(NSWindow *)parent name:(NSString *)name colorIndex:(NSInteger)colorIndex
             completion:(void (^)(NSString *, NSInteger))done {
    YRenameSheet *s = [[YRenameSheet alloc] init];
    sActiveRenameSheet = s;
    [s buildForParent:parent name:name colorIndex:colorIndex completion:done];
}

- (void)buildForParent:(NSWindow *)parent name:(NSString *)name colorIndex:(NSInteger)colorIndex completion:(void (^)(NSString *, NSInteger))done {
    _parent = parent;
    _color = colorIndex;
    _done = [done copy];

    const CGFloat W = 420, H = 284;
    _panel = [[YSheetPanel alloc] initWithContentRect:NSMakeRect(0, 0, W, H) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    _panel.backgroundColor = [NSColor clearColor];
    _panel.opaque = NO;
    _panel.hasShadow = YES;
    _panel.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];

    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, W, H)];
    root.wantsLayer = YES;
    root.layer.cornerRadius = 24;
    root.layer.masksToBounds = YES;
    root.layer.backgroundColor = [NSColor whiteColor].CGColor;
    root.layer.borderColor = Y_hairline().CGColor;
    root.layer.borderWidth = 1;
    _panel.contentView = root;

    NSTextField *title = [NSTextField labelWithString:@"Rename group"];
    title.font = [NSFont systemFontOfSize:24 weight:NSFontWeightMedium];
    title.textColor = Y_ink();
    title.frame = NSMakeRect(28, H - 28 - 30, W - 56, 30);
    [root addSubview:title];

    NSTextField *sub = [NSTextField labelWithString:@"Give this group a name and a colour."];
    sub.font = [NSFont systemFontOfSize:14 weight:NSFontWeightRegular];
    sub.textColor = Y_muted();
    sub.frame = NSMakeRect(28, 196, W - 56, 20);
    [root addSubview:sub];

    // Field with a blue focus ring
    _fieldBox = [[NSView alloc] initWithFrame:NSMakeRect(28, 130, W - 56, 52)];
    _fieldBox.wantsLayer = YES;
    _fieldBox.layer.cornerRadius = 12;
    _fieldBox.layer.backgroundColor = [NSColor whiteColor].CGColor;
    [root addSubview:_fieldBox];
    _field = [[NSTextField alloc] initWithFrame:NSMakeRect(16, 15, _fieldBox.bounds.size.width - 32, 22)];
    _field.bezeled = NO;
    _field.drawsBackground = NO;
    _field.focusRingType = NSFocusRingTypeNone;
    _field.font = [NSFont systemFontOfSize:16 weight:NSFontWeightRegular];
    _field.textColor = Y_ink();
    _field.stringValue = name ?: @"";
    _field.placeholderAttributedString = [[NSAttributedString alloc] initWithString:@"Group name" attributes:@{NSForegroundColorAttributeName: Y_muted2(), NSFontAttributeName: [NSFont systemFontOfSize:16]}];
    _field.delegate = self;
    _field.target = self;
    _field.action = @selector(save:);
    [_fieldBox addSubview:_field];
    [self setFieldFocused:YES];

    // Colour swatches
    NSArray<NSColor *> *colors = YGroupColors();
    NSMutableArray<YSwatch *> *sw = [NSMutableArray array];
    CGFloat x = 24;
    for (NSInteger i = 0; i < (NSInteger)colors.count; i++) {
        YSwatch *b = [[YSwatch alloc] initWithColor:colors[i] frame:NSMakeRect(x, 84, 32, 32)];
        b.tag = i;
        b.target = self;
        b.action = @selector(pickColor:);
        b.toolTip = YGroupColorNames()[i];
        b.chosen = (i == colorIndex);
        [root addSubview:b];
        [sw addObject:b];
        x += 32 + 10;
    }
    _swatches = sw;

    // Buttons
    YSheetButton *save = [[YSheetButton alloc] initWithTitle:@"Save" primary:YES frame:NSMakeRect(W - 28 - 120, 24, 120, 44)];
    save.target = self; save.action = @selector(save:);
    save.keyEquivalent = @"\r";
    YSheetButton *cancel = [[YSheetButton alloc] initWithTitle:@"Cancel" primary:NO frame:NSMakeRect(W - 28 - 120 - 10 - 110, 24, 110, 44)];
    cancel.target = self; cancel.action = @selector(cancel:);
    cancel.keyEquivalent = @"\033";
    [root addSubview:cancel];
    [root addSubview:save];

    _panel.initialFirstResponder = _field;
    __weak YRenameSheet *weak = self;
    [parent beginSheet:_panel completionHandler:^(NSModalResponse code) {
        (void)code;
        YRenameSheet *strong = weak;
        [strong->_panel orderOut:nil];
        sActiveRenameSheet = nil;
    }];
    [_panel makeFirstResponder:_field];
    [_field selectText:nil];
}

- (void)setFieldFocused:(BOOL)focused {
    _fieldBox.layer.borderWidth = focused ? 2 : 1;
    _fieldBox.layer.borderColor = (focused ? Y_blue() : Y_border()).CGColor;
}
- (void)controlTextDidBeginEditing:(NSNotification *)n { (void)n; [self setFieldFocused:YES]; }
- (void)controlTextDidEndEditing:(NSNotification *)n { (void)n; [self setFieldFocused:NO]; }

- (void)pickColor:(YSwatch *)sender {
    _color = sender.tag;
    for (YSwatch *b in _swatches) b.chosen = (b == sender);
}
- (void)save:(id)sender {
    (void)sender;
    NSString *name = [_field.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    void (^done)(NSString *, NSInteger) = _done;
    _done = nil;
    [_parent endSheet:_panel returnCode:NSModalResponseOK];
    if (done) done(name, _color);
}
- (void)cancel:(id)sender {
    (void)sender;
    _done = nil;
    [_parent endSheet:_panel returnCode:NSModalResponseCancel];
}
@end

#pragma mark - Downloads UI

@interface YFlippedView : NSView
@end
@implementation YFlippedView
- (BOOL)isFlipped { return YES; }
@end

static NSString *YBytes(int64_t b) { return [NSByteCountFormatter stringFromByteCount:b countStyle:NSByteCountFormatterCountStyleFile]; }

@interface YDownloadRow : NSView
@property (nonatomic, strong) SaturnDownloadItem *item;
- (instancetype)initWithItem:(SaturnDownloadItem *)item width:(CGFloat)w;
- (void)refresh;
@end

@implementation YDownloadRow {
    NSImageView *_icon;
    NSTextField *_name, *_sub;
    NSView *_track, *_fill;
    YIconButton *_primary, *_secondary;
    NSTrackingArea *_area;
}
- (instancetype)initWithItem:(SaturnDownloadItem *)item width:(CGFloat)w {
    self = [super initWithFrame:NSMakeRect(0, 0, w, 64)];
    if (!self) return nil;
    _item = item;
    self.wantsLayer = YES;
    self.layer.cornerRadius = 16;
    self.autoresizingMask = NSViewWidthSizable;

    _icon = [[NSImageView alloc] initWithFrame:NSMakeRect(16, 14, 36, 36)];
    [self addSubview:_icon];
    _name = [NSTextField labelWithString:@""];
    _name.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
    _name.textColor = Y_ink();
    _name.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _name.frame = NSMakeRect(64, 34, w - 64 - 84, 18);
    _name.autoresizingMask = NSViewWidthSizable;
    [self addSubview:_name];
    _sub = [NSTextField labelWithString:@""];
    _sub.font = [NSFont systemFontOfSize:12 weight:NSFontWeightRegular];
    _sub.textColor = Y_muted();
    _sub.lineBreakMode = NSLineBreakByTruncatingTail;
    _sub.frame = NSMakeRect(64, 16, w - 64 - 84, 16);
    _sub.autoresizingMask = NSViewWidthSizable;
    [self addSubview:_sub];

    _track = [[NSView alloc] initWithFrame:NSMakeRect(64, 8, w - 64 - 84, 4)];
    _track.wantsLayer = YES;
    _track.layer.cornerRadius = 2;
    _track.layer.backgroundColor = Y_soft().CGColor;
    _track.autoresizingMask = NSViewWidthSizable;
    [self addSubview:_track];
    _fill = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 0, 4)];
    _fill.wantsLayer = YES;
    _fill.layer.cornerRadius = 2;
    _fill.layer.backgroundColor = Y_blue().CGColor;
    [_track addSubview:_fill];

    _primary = [[YIconButton alloc] initWithFrame:NSMakeRect(w - 76, 18, 28, 28)];
    _primary.imagePosition = NSImageOnly; _primary.imageScaling = NSImageScaleNone; _primary.bordered = NO; _primary.wantsLayer = YES;
    _primary.layer.cornerRadius = 14;
    _primary.image = Y_symbol(@"folder", 14, NSFontWeightMedium);
    _primary.contentTintColor = Y_ink();
    _primary.toolTip = @"Show in Finder";
    _primary.target = self; _primary.action = @selector(revealTapped:);
    _primary.autoresizingMask = NSViewMinXMargin;
    [self addSubview:_primary];
    _secondary = [[YIconButton alloc] initWithFrame:NSMakeRect(w - 44, 18, 28, 28)];
    _secondary.imagePosition = NSImageOnly; _secondary.imageScaling = NSImageScaleNone; _secondary.bordered = NO; _secondary.wantsLayer = YES;
    _secondary.layer.cornerRadius = 14;
    _secondary.image = Y_symbol(@"xmark", 12, NSFontWeightMedium);
    _secondary.contentTintColor = Y_ink();
    _secondary.target = self; _secondary.action = @selector(secondaryTapped:);
    _secondary.autoresizingMask = NSViewMinXMargin;
    [self addSubview:_secondary];
    [self refresh];
    return self;
}
- (void)refresh {
    SaturnDownloadItem *it = _item;
    _name.stringValue = it.filename ?: @"Download";
    BOOL active = it.state == SaturnDownloadStateActive, done = it.state == SaturnDownloadStateDone;
    NSString *sub;
    switch (it.state) {
        case SaturnDownloadStateActive:
            sub = it.bytesTotal > 0 ? [NSString stringWithFormat:@"%@ of %@", YBytes(it.bytesReceived), YBytes(it.bytesTotal)]
                                    : (it.bytesReceived > 0 ? [NSString stringWithFormat:@"Downloading… %@", YBytes(it.bytesReceived)] : @"Starting…");
            break;
        case SaturnDownloadStateDone: sub = [NSString stringWithFormat:@"%@ · Done", YBytes(it.bytesTotal)]; break;
        case SaturnDownloadStateFailed: sub = it.errorText.length ? [@"Failed: " stringByAppendingString:it.errorText] : @"Failed"; break;
        default: sub = @"Cancelled"; break;
    }
    _sub.stringValue = sub;
    _sub.textColor = it.state == SaturnDownloadStateFailed ? Y_negative() : Y_muted();
    _track.hidden = !active;
    double f = it.fraction;
    _fill.frame = NSMakeRect(0, 0, f >= 0 ? _track.bounds.size.width * f : _track.bounds.size.width * 0.25, 4);
    _primary.hidden = !done;
    _secondary.toolTip = active ? @"Cancel download" : @"Remove from list";
    NSImage *img = nil;
    if (done && it.destination.path && [[NSFileManager defaultManager] fileExistsAtPath:it.destination.path]) img = [[NSWorkspace sharedWorkspace] iconForFile:it.destination.path];
    if (!img) img = [[NSWorkspace sharedWorkspace] iconForFileType:it.filename.pathExtension.length ? it.filename.pathExtension : @"dat"];
    _icon.image = img;
}
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_area) [self removeTrackingArea:_area];
    _area = [[NSTrackingArea alloc] initWithRect:self.bounds options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect owner:self userInfo:nil];
    [self addTrackingArea:_area];
}
- (void)mouseEntered:(NSEvent *)e { (void)e; self.layer.backgroundColor = Y_soft().CGColor; }
- (void)mouseExited:(NSEvent *)e { (void)e; self.layer.backgroundColor = [NSColor clearColor].CGColor; }
- (void)mouseDown:(NSEvent *)e { (void)e; [[SaturnDownloads shared] open:_item]; }
- (void)revealTapped:(id)s { (void)s; [[SaturnDownloads shared] reveal:_item]; }
- (void)secondaryTapped:(id)s {
    (void)s;
    if (_item.state == SaturnDownloadStateActive) [[SaturnDownloads shared] cancel:_item];
    else [[SaturnDownloads shared] remove:_item];
}
@end

@interface YDownloadsVC : NSViewController
@end

@implementation YDownloadsVC {
    NSScrollView *_scroll;
    YFlippedView *_doc;
    NSTextField *_empty;
    NSMutableArray<YDownloadRow *> *_rows;
    NSString *_signature;
}
static const CGFloat kDLW = 392, kDLHeader = 64, kDLRow = 64;

- (void)loadView {
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kDLW, 300)];
    root.wantsLayer = YES;
    root.layer.backgroundColor = [NSColor whiteColor].CGColor;
    self.view = root;
    _rows = [NSMutableArray array];

    NSTextField *title = [NSTextField labelWithString:@"Downloads"];
    title.font = [NSFont systemFontOfSize:18 weight:NSFontWeightMedium];
    title.textColor = Y_ink();
    title.frame = NSMakeRect(20, 300 - 46, 200, 24);
    title.autoresizingMask = NSViewMinYMargin;
    [root addSubview:title];
    YSheetButton *clear = [[YSheetButton alloc] initWithTitle:@"Clear" primary:NO frame:NSMakeRect(kDLW - 20 - 72, 300 - 50, 72, 32)];
    clear.target = self; clear.action = @selector(clearTapped:);
    clear.autoresizingMask = NSViewMinYMargin;
    [root addSubview:clear];

    _scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, kDLW, 300 - kDLHeader)];
    _scroll.hasVerticalScroller = YES;
    _scroll.autohidesScrollers = YES;
    _scroll.drawsBackground = NO;
    _scroll.borderType = NSNoBorder;
    _scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _doc = [[YFlippedView alloc] initWithFrame:NSMakeRect(0, 0, kDLW, 10)];
    _scroll.documentView = _doc;
    [root addSubview:_scroll];

    _empty = [NSTextField labelWithString:@"No downloads yet"];
    _empty.font = [NSFont systemFontOfSize:14 weight:NSFontWeightRegular];
    _empty.textColor = Y_muted();
    _empty.alignment = NSTextAlignmentCenter;
    _empty.frame = NSMakeRect(0, 100, kDLW, 20);
    _empty.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [root addSubview:_empty];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:SaturnDownloadsChangedNotification object:nil];
    [self reload];
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)clearTapped:(id)s { (void)s; [[SaturnDownloads shared] clearFinished]; }

- (void)reload {
    if (!self.isViewLoaded) return;
    NSArray<SaturnDownloadItem *> *items = [SaturnDownloads shared].items;
    NSMutableString *sig = [NSMutableString string];
    for (SaturnDownloadItem *i in items) [sig appendFormat:@"%p:%ld;", i, (long)i.state];
    if (![sig isEqualToString:_signature]) {
        _signature = sig;
        for (YDownloadRow *r in _rows) [r removeFromSuperview];
        [_rows removeAllObjects];
        CGFloat y = 4;
        for (SaturnDownloadItem *i in items) {
            YDownloadRow *r = [[YDownloadRow alloc] initWithItem:i width:kDLW - 16];
            r.frame = NSMakeRect(8, y, kDLW - 16, kDLRow);
            [_doc addSubview:r];
            [_rows addObject:r];
            y += kDLRow;
        }
        _doc.frame = NSMakeRect(0, 0, kDLW, MAX(10, y + 4));
        _empty.hidden = items.count > 0;
        CGFloat listH = items.count ? MIN(items.count * kDLRow + 8, 340) : 120;
        self.preferredContentSize = NSMakeSize(kDLW, kDLHeader + listH);
    }
    for (YDownloadRow *r in _rows) [r refresh];
}
@end

#pragma mark - Update popover

@interface YUpdateVC : NSViewController
@end

@implementation YUpdateVC {
    SaturnUpdateState _shownState;
    NSView *_fill;
    NSTextField *_pct;
}
static const CGFloat kUpW = 380;

- (void)loadView {
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kUpW, 200)];
    root.wantsLayer = YES;
    root.layer.backgroundColor = [NSColor whiteColor].CGColor;
    self.view = root;
    _shownState = (SaturnUpdateState)-1;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:SaturnUpdateStateChangedNotification object:nil];
    [self refresh];
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

static NSString *PlainNotes(NSString *md) {
    NSMutableString *t = [md mutableCopy];
    for (NSString *junk in @[@"**", @"__", @"`", @"\r"]) [t replaceOccurrencesOfString:junk withString:@"" options:0 range:NSMakeRange(0, t.length)];
    NSMutableArray *lines = [NSMutableArray array];
    for (NSString *l in [t componentsSeparatedByString:@"\n"]) {
        NSString *x = [l stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"# \t"]];
        if ([l hasPrefix:@"- "] || [l hasPrefix:@"* "]) x = [@"• " stringByAppendingString:[l substringFromIndex:2]];
        if (x.length) [lines addObject:x];
    }
    NSString *joined = [lines componentsJoinedByString:@"\n"];
    return joined.length > 520 ? [[joined substringToIndex:520] stringByAppendingString:@"…"] : joined;
}

- (void)refresh {
    if (!self.isViewLoaded) return;
    SaturnUpdater *u = [SaturnUpdater shared];
    if (u.state == _shownState && u.state == SaturnUpdateStateDownloading) {   // only the bar moves
        _fill.frame = NSMakeRect(0, 0, (kUpW - 44) * u.progress, 6);
        _pct.stringValue = [NSString stringWithFormat:@"%d%%", (int)round(u.progress * 100)];
        return;
    }
    _shownState = u.state;
    NSView *root = self.view;
    for (NSView *v in [root.subviews copy]) [v removeFromSuperview];

    NSString *title, *sub = nil, *notes = nil;
    BOOL showProgress = NO, subIsError = NO;
    NSString *primary = nil, *secondary = nil;
    switch (u.state) {
        case SaturnUpdateStateAvailable:
            title = [NSString stringWithFormat:@"Saturn %@ is available", u.availableVersion];
            sub = [NSString stringWithFormat:@"You have version %@.", u.currentVersion];
            notes = u.releaseNotes.length ? PlainNotes(u.releaseNotes) : nil;
            primary = @"Update now"; secondary = @"Later";
            break;
        case SaturnUpdateStateDownloading:
            title = [NSString stringWithFormat:@"Downloading Saturn %@", u.availableVersion];
            showProgress = YES;
            break;
        case SaturnUpdateStateInstalling:
            title = @"Installing the update";
            sub = @"Saturn will restart in a moment and reopen your tabs.";
            break;
        case SaturnUpdateStateFailed:
            title = @"The update didn't finish";
            sub = u.errorText; subIsError = YES;
            primary = @"Try again"; secondary = @"Later";
            break;
        default:
            title = @"Saturn is up to date";
            sub = [NSString stringWithFormat:@"Version %@ is the latest.", u.currentVersion];
            secondary = @"OK";
            break;
    }

    const CGFloat pad = 22, w = kUpW - 2 * pad;
    NSFont *tf = [NSFont systemFontOfSize:18 weight:NSFontWeightMedium], *sf = [NSFont systemFontOfSize:13], *nf = [NSFont systemFontOfSize:13];
    CGFloat th = 24;
    CGFloat sh = sub.length ? ceil([sub boundingRectWithSize:NSMakeSize(w, 400) options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName: sf}].size.height) : 0;
    CGFloat nh = notes.length ? MIN(130, ceil([notes boundingRectWithSize:NSMakeSize(w - 28, 400) options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName: nf}].size.height)) + 24 : 0;
    CGFloat H = pad + th + (sh ? 4 + sh : 0) + (nh ? 14 + nh : 0) + (showProgress ? 18 + 6 + 8 + 16 : 0) + ((primary || secondary) ? 18 + 40 : 0) + pad;
    root.frame = NSMakeRect(0, 0, kUpW, H);
    self.preferredContentSize = NSMakeSize(kUpW, H);

    CGFloat y = H - pad;
    NSTextField *t = [NSTextField labelWithString:title];
    t.font = tf; t.textColor = Y_ink();
    t.frame = NSMakeRect(pad, y - th, w, th);
    [root addSubview:t];
    y -= th;
    if (sh) {
        NSTextField *s = [NSTextField wrappingLabelWithString:sub];
        s.font = sf; s.textColor = subIsError ? Y_negative() : Y_muted();
        s.frame = NSMakeRect(pad, y - 4 - sh, w, sh);
        [root addSubview:s];
        y -= 4 + sh;
    }
    if (nh) {
        NSView *box = [[NSView alloc] initWithFrame:NSMakeRect(pad, y - 14 - nh, w, nh)];
        box.wantsLayer = YES;
        box.layer.cornerRadius = 16;
        box.layer.backgroundColor = Y_soft().CGColor;
        NSTextField *n = [NSTextField wrappingLabelWithString:notes];
        n.font = nf; n.textColor = Y_ink();
        n.maximumNumberOfLines = 8;
        n.frame = NSMakeRect(14, 12, w - 28, nh - 24);
        [box addSubview:n];
        [root addSubview:box];
        y -= 14 + nh;
    }
    if (showProgress) {
        NSView *track = [[NSView alloc] initWithFrame:NSMakeRect(pad, y - 18 - 6, w, 6)];
        track.wantsLayer = YES;
        track.layer.cornerRadius = 3;
        track.layer.backgroundColor = Y_soft().CGColor;
        _fill = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, w * u.progress, 6)];
        _fill.wantsLayer = YES;
        _fill.layer.cornerRadius = 3;
        _fill.layer.backgroundColor = Y_blue().CGColor;
        [track addSubview:_fill];
        [root addSubview:track];
        _pct = [NSTextField labelWithString:[NSString stringWithFormat:@"%d%%", (int)round(u.progress * 100)]];
        _pct.font = sf; _pct.textColor = Y_muted();
        _pct.frame = NSMakeRect(pad, y - 18 - 6 - 8 - 16, w, 16);
        [root addSubview:_pct];
        y -= 18 + 6 + 8 + 16;
    }
    if (primary || secondary) {
        CGFloat bw = 120, bh = 40, by = pad;
        if (primary) {
            YSheetButton *b = [[YSheetButton alloc] initWithTitle:primary primary:YES frame:NSMakeRect(kUpW - pad - bw, by, bw, bh)];
            b.target = self; b.action = @selector(primaryTapped:);
            b.keyEquivalent = @"\r";
            [root addSubview:b];
        }
        if (secondary) {
            YSheetButton *b = [[YSheetButton alloc] initWithTitle:secondary primary:NO frame:NSMakeRect(kUpW - pad - (primary ? bw * 2 + 8 : bw), by, bw, bh)];
            b.target = self; b.action = @selector(laterTapped:);
            [root addSubview:b];
        }
    }
}
- (void)primaryTapped:(id)s { (void)s; [[SaturnUpdater shared] installUpdate]; }
- (void)laterTapped:(id)s { (void)s; [self.view.window close]; }
@end

#pragma mark - Find in page bar

@interface SaturnFindBar : NSView <NSTextFieldDelegate>
@property (nonatomic, weak) SaturnWindow *host;
@property (nonatomic, strong, readonly) NSTextField *field;
- (void)setStatus:(NSString *)text;
@end

@implementation SaturnFindBar {
    NSTextField *_field;
    NSTextField *_status;
}
@synthesize field = _field;
- (instancetype)initWithFrame:(NSRect)f {
    self = [super initWithFrame:f];
    if (!self) return nil;
    self.wantsLayer = YES;
    self.layer.cornerRadius = 22;
    self.layer.masksToBounds = NO;
    self.layer.backgroundColor = [NSColor whiteColor].CGColor;
    self.layer.borderColor = Y_hairline().CGColor;
    self.layer.borderWidth = 1;
    self.layer.shadowColor = [NSColor blackColor].CGColor;
    self.layer.shadowOpacity = 0.20;
    self.layer.shadowRadius = 10;
    self.layer.shadowOffset = NSMakeSize(0, -8);

    NSImageView *icon = [[NSImageView alloc] initWithFrame:NSMakeRect(16, 13, 18, 18)];
    icon.image = Y_symbol(@"magnifyingglass", 14, NSFontWeightMedium);
    icon.contentTintColor = Y_muted2();
    [self addSubview:icon];

    _field = [[NSTextField alloc] initWithFrame:NSMakeRect(42, 11, 176, 22)];
    _field.bezeled = NO;
    _field.drawsBackground = NO;
    _field.focusRingType = NSFocusRingTypeNone;
    _field.font = [NSFont systemFontOfSize:14];
    _field.textColor = Y_ink();
    _field.placeholderAttributedString = [[NSAttributedString alloc] initWithString:@"Find in page" attributes:@{NSForegroundColorAttributeName: Y_muted2(), NSFontAttributeName: [NSFont systemFontOfSize:14]}];
    _field.delegate = self;
    [self addSubview:_field];

    _status = [NSTextField labelWithString:@""];
    _status.font = [NSFont systemFontOfSize:12];
    _status.textColor = Y_muted();
    _status.alignment = NSTextAlignmentRight;
    _status.frame = NSMakeRect(222, 13, 92, 18);
    [self addSubview:_status];

    NSArray *btns = @[@[@"chevron.up", @"previous:", @"Previous match (⇧⌘G)"], @[@"chevron.down", @"next:", @"Next match (⌘G)"], @[@"xmark", @"closeBar:", @"Close (Esc)"]];
    CGFloat x = 318;
    for (NSArray *b in btns) {
        YIconButton *ib = [[YIconButton alloc] initWithFrame:NSMakeRect(x, 7, 30, 30)];
        ib.image = Y_symbol(b[0], 13, NSFontWeightMedium);
        ib.imagePosition = NSImageOnly; ib.imageScaling = NSImageScaleNone; ib.bordered = NO; ib.wantsLayer = YES;
        ib.layer.cornerRadius = 15;
        ib.contentTintColor = Y_ink();
        ib.toolTip = b[2];
        ib.target = self; ib.action = NSSelectorFromString(b[1]);
        [self addSubview:ib];
        x += 32;
    }
    return self;
}
- (void)setStatus:(NSString *)text { _status.stringValue = text ?: @""; }
- (void)previous:(id)s { (void)s; [self.host findPreviousInPage:nil]; }
- (void)next:(id)s { (void)s; [self.host findNextInPage:nil]; }
- (void)closeBar:(id)s { (void)s; [self.host hideFindBar]; }
- (void)controlTextDidChange:(NSNotification *)n { (void)n; [self.host findQueryChanged]; }
- (BOOL)control:(NSControl *)c textView:(NSTextView *)tv doCommandBySelector:(SEL)sel {
    (void)c; (void)tv;
    if (sel == @selector(insertNewline:)) {
        if (NSApp.currentEvent.modifierFlags & NSEventModifierFlagShift) [self.host findPreviousInPage:nil];
        else [self.host findNextInPage:nil];
        return YES;
    }
    if (sel == @selector(cancelOperation:)) { [self.host hideFindBar]; return YES; }
    return NO;
}
@end

#pragma mark - Address bar suggestions

@interface SaturnSuggestRow : NSView
@property (nonatomic, assign) NSInteger index;
@property (nonatomic, copy) void (^onHover)(NSInteger index);
@property (nonatomic, copy) void (^onPick)(NSInteger index);
- (instancetype)initWithItem:(NSDictionary *)item engineName:(NSString *)engine width:(CGFloat)w;
- (void)setSelected:(BOOL)selected;
@end

@implementation SaturnSuggestRow {
    NSTrackingArea *_area;
}
- (instancetype)initWithItem:(NSDictionary *)item engineName:(NSString *)engine width:(CGFloat)w {
    self = [super initWithFrame:NSMakeRect(0, 0, w, 44)];
    if (!self) return nil;
    self.wantsLayer = YES;
    self.layer.cornerRadius = 16;
    NSString *kind = item[@"kind"];
    NSString *sym = [kind isEqualToString:@"search"] ? @"magnifyingglass" : [kind isEqualToString:@"url"] ? @"globe" : [kind isEqualToString:@"bookmark"] ? @"bookmark.fill" : @"clock";
    NSImageView *icon = [[NSImageView alloc] initWithFrame:NSMakeRect(16, 13, 18, 18)];
    icon.image = Y_symbol(sym, 14, NSFontWeightMedium);
    icon.contentTintColor = [kind isEqualToString:@"bookmark"] ? Y_blue() : Y_muted();
    [self addSubview:icon];

    NSFont *main = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium], *sub = [NSFont systemFontOfSize:13 weight:NSFontWeightRegular];
    NSMutableAttributedString *a = [[NSMutableAttributedString alloc] init];
    void (^add)(NSString *, NSFont *, NSColor *) = ^(NSString *t, NSFont *f, NSColor *c) {
        [a appendAttributedString:[[NSAttributedString alloc] initWithString:t attributes:@{NSFontAttributeName: f, NSForegroundColorAttributeName: c}]];
    };
    if ([kind isEqualToString:@"search"]) {
        add([NSString stringWithFormat:@"%@", item[@"title"]], main, Y_ink());
        add([NSString stringWithFormat:@"  —  Search %@", engine ?: @"the web"], sub, Y_muted());
    } else if ([kind isEqualToString:@"url"]) {
        add([NSString stringWithFormat:@"%@", item[@"title"]], main, Y_ink());
        add(@"  —  Go to site", sub, Y_muted());
    } else {
        NSString *u = item[@"url"];
        NSString *host = [NSURL URLWithString:u].host ?: u;
        if ([host hasPrefix:@"www."]) host = [host substringFromIndex:4];
        add(item[@"title"], main, Y_ink());
        add([NSString stringWithFormat:@"  —  %@", host], sub, Y_muted());
    }
    NSTextField *label = [NSTextField labelWithAttributedString:a];
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.frame = NSMakeRect(46, 12, w - 46 - 16, 20);
    label.autoresizingMask = NSViewWidthSizable;
    [self addSubview:label];
    return self;
}
- (void)setSelected:(BOOL)selected { self.layer.backgroundColor = (selected ? Y_soft() : [NSColor clearColor]).CGColor; }
- (NSView *)hitTest:(NSPoint)p { return NSPointInRect(p, self.frame) ? self : nil; }
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_area) [self removeTrackingArea:_area];
    _area = [[NSTrackingArea alloc] initWithRect:self.bounds options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect owner:self userInfo:nil];
    [self addTrackingArea:_area];
}
- (void)mouseEntered:(NSEvent *)e { (void)e; if (self.onHover) self.onHover(self.index); }
- (void)mouseDown:(NSEvent *)e { (void)e; if (self.onPick) self.onPick(self.index); }
@end

@interface SaturnSuggestView : NSView
@property (nonatomic, copy) void (^onPick)(NSDictionary *item);
@property (nonatomic, readonly) NSArray<NSDictionary *> *items;
@property (nonatomic, readonly) NSInteger selected;
- (void)setItems:(NSArray<NSDictionary *> *)items engineName:(NSString *)engine width:(CGFloat)w;
- (void)moveSelection:(NSInteger)delta;
- (NSDictionary *)selectedItem;
+ (CGFloat)heightForCount:(NSInteger)n;
@end

@implementation SaturnSuggestView {
    NSArray<NSDictionary *> *_items;
    NSMutableArray<SaturnSuggestRow *> *_rows;
    NSInteger _selected;
}
@synthesize items = _items;
@synthesize selected = _selected;
+ (CGFloat)heightForCount:(NSInteger)n { return n * 44 + 16; }
- (instancetype)initWithFrame:(NSRect)f {
    self = [super initWithFrame:f];
    if (!self) return nil;
    self.wantsLayer = YES;
    self.layer.cornerRadius = 24;
    self.layer.masksToBounds = NO;
    self.layer.backgroundColor = [NSColor whiteColor].CGColor;
    self.layer.borderColor = Y_hairline().CGColor;
    self.layer.borderWidth = 1;
    self.layer.shadowColor = [NSColor blackColor].CGColor;
    self.layer.shadowOpacity = 0.20;
    self.layer.shadowRadius = 10;
    self.layer.shadowOffset = NSMakeSize(0, -8);
    _rows = [NSMutableArray array];
    return self;
}
- (void)setItems:(NSArray<NSDictionary *> *)items engineName:(NSString *)engine width:(CGFloat)w {
    _items = [items copy];
    for (NSView *r in _rows) [r removeFromSuperview];
    [_rows removeAllObjects];
    CGFloat h = [SaturnSuggestView heightForCount:items.count];
    [self setFrameSize:NSMakeSize(w, h)];
    __weak SaturnSuggestView *weak = self;
    for (NSInteger i = 0; i < (NSInteger)items.count; i++) {
        SaturnSuggestRow *row = [[SaturnSuggestRow alloc] initWithItem:items[i] engineName:engine width:w - 16];
        row.index = i;
        row.frame = NSMakeRect(8, h - 8 - (i + 1) * 44, w - 16, 44);
        row.onHover = ^(NSInteger idx) { [weak selectIndex:idx]; };
        row.onPick = ^(NSInteger idx) { if (weak.onPick && idx < (NSInteger)weak.items.count) weak.onPick(weak.items[idx]); };
        [self addSubview:row];
        [_rows addObject:row];
    }
    [self selectIndex:0];
}
- (void)selectIndex:(NSInteger)i {
    _selected = MAX(0, MIN((NSInteger)_rows.count - 1, i));
    for (NSInteger k = 0; k < (NSInteger)_rows.count; k++) [_rows[k] setSelected:k == _selected];
}
- (void)moveSelection:(NSInteger)delta {
    if (!_rows.count) return;
    NSInteger n = _rows.count;
    [self selectIndex:((_selected + delta) % n + n) % n];   // wraps around
}
- (NSDictionary *)selectedItem { return _selected < (NSInteger)_items.count ? _items[_selected] : nil; }
@end

#pragma mark - Permission / confirmation prompt card

// Small card that hangs under the address bar: icon, question, optional "remember", and two buttons.
@interface SaturnPromptCard : NSView
@property (nonatomic, copy) void (^onDecision)(BOOL allow, BOOL remember);
- (instancetype)initWithSymbol:(NSString *)symbol title:(NSString *)title detail:(NSString *)detail
                    allowTitle:(NSString *)allowTitle denyTitle:(NSString *)denyTitle showRemember:(BOOL)showRemember;
@end

@implementation SaturnPromptCard {
    NSButton *_remember;
    BOOL _answered;
}
static const CGFloat kPromptW = 380;

- (instancetype)initWithSymbol:(NSString *)symbol title:(NSString *)title detail:(NSString *)detail
                    allowTitle:(NSString *)allowTitle denyTitle:(NSString *)denyTitle showRemember:(BOOL)showRemember {
    self = [super initWithFrame:NSMakeRect(0, 0, kPromptW, 200)];
    if (!self) return nil;
    self.wantsLayer = YES;
    self.layer.cornerRadius = 24;
    self.layer.masksToBounds = NO;
    self.layer.backgroundColor = [NSColor whiteColor].CGColor;
    self.layer.borderColor = Y_hairline().CGColor;
    self.layer.borderWidth = 1;
    self.layer.shadowColor = [NSColor blackColor].CGColor;
    self.layer.shadowOpacity = 0.20;
    self.layer.shadowRadius = 10;
    self.layer.shadowOffset = NSMakeSize(0, -8);

    const CGFloat pad = 20, textX = 72, textW = kPromptW - textX - pad;
    NSFont *tf = [NSFont systemFontOfSize:15 weight:NSFontWeightMedium], *df = [NSFont systemFontOfSize:13];
    CGFloat th = ceil([title boundingRectWithSize:NSMakeSize(textW, 200) options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName: tf}].size.height);
    CGFloat dh = detail.length ? ceil([detail boundingRectWithSize:NSMakeSize(textW, 200) options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName: df}].size.height) : 0;
    CGFloat H = pad + th + (dh ? 4 + dh : 0) + 16 + (showRemember ? 22 + 14 : 0) + 40 + pad;
    [self setFrameSize:NSMakeSize(kPromptW, H)];

    CGFloat y = H - pad;
    NSView *icon = [[NSView alloc] initWithFrame:NSMakeRect(pad, y - 40, 40, 40)];
    icon.wantsLayer = YES;
    icon.layer.cornerRadius = 20;
    icon.layer.backgroundColor = Y_soft().CGColor;
    NSImageView *iv = [[NSImageView alloc] initWithFrame:NSMakeRect(10, 10, 20, 20)];
    iv.image = Y_symbol(symbol, 16, NSFontWeightMedium);
    iv.contentTintColor = Y_blue();
    [icon addSubview:iv];
    [self addSubview:icon];

    NSTextField *t = [NSTextField wrappingLabelWithString:title];
    t.font = tf; t.textColor = Y_ink();
    t.frame = NSMakeRect(textX, y - th, textW, th);
    [self addSubview:t];
    y -= th;
    if (dh) {
        NSTextField *d = [NSTextField wrappingLabelWithString:detail];
        d.font = df; d.textColor = Y_muted();
        d.frame = NSMakeRect(textX, y - 4 - dh, textW, dh);
        [self addSubview:d];
        y -= 4 + dh;
    }
    y -= 16;
    if (showRemember) {
        _remember = [NSButton checkboxWithTitle:@"Remember my choice for this site" target:nil action:nil];
        _remember.state = NSControlStateValueOn;
        _remember.font = [NSFont systemFontOfSize:13];
        _remember.frame = NSMakeRect(textX, y - 22, textW, 22);
        [self addSubview:_remember];
        y -= 22 + 14;
    }
    CGFloat bw = 110, bh = 40;
    YSheetButton *allow = [[YSheetButton alloc] initWithTitle:allowTitle primary:YES frame:NSMakeRect(kPromptW - pad - bw, pad, bw, bh)];
    allow.target = self; allow.action = @selector(allowTapped:);
    allow.keyEquivalent = @"\r";
    YSheetButton *deny = [[YSheetButton alloc] initWithTitle:denyTitle primary:NO frame:NSMakeRect(kPromptW - pad - bw * 2 - 8, pad, bw, bh)];
    deny.target = self; deny.action = @selector(denyTapped:);
    [self addSubview:deny];
    [self addSubview:allow];
    return self;
}
- (void)decide:(BOOL)allow {
    if (_answered) return;
    _answered = YES;
    BOOL remember = _remember ? _remember.state == NSControlStateValueOn : NO;
    if (self.onDecision) self.onDecision(allow, remember);
}
- (void)allowTapped:(id)s { (void)s; [self decide:YES]; }
- (void)denyTapped:(id)s { (void)s; [self decide:NO]; }
@end

// Draws but never takes clicks, so the page underneath stays usable.
@interface YPassThroughView : NSView
@end
@implementation YPassThroughView
- (NSView *)hitTest:(NSPoint)p { (void)p; return nil; }
@end

#pragma mark - Feedback / crash report sheet

// One sheet, two uses: "Send feedback" (kind + message + email) and the "Saturn quit unexpectedly" report.
@interface YFeedbackSheet : NSObject <NSTextViewDelegate>
+ (void)presentOnWindow:(NSWindow *)parent crashSummary:(NSString *)crashSummary crashDetails:(NSString *)crashDetails
                 submit:(void (^)(NSDictionary *values, void (^done)(NSError *error)))submit
                dismiss:(void (^)(void))dismiss;
@end

static YFeedbackSheet *sActiveFeedbackSheet;

@implementation YFeedbackSheet {
    YSheetPanel *_panel;
    __weak NSWindow *_parent;
    BOOL _crash;
    NSTextView *_text;
    NSTextField *_placeholder, *_email, *_error;
    NSView *_textBox, *_emailBox;
    NSButton *_diag;
    NSArray<NSButton *> *_kindButtons;
    NSInteger _kind;
    NSButton *_send, *_cancel;
    void (^_submit)(NSDictionary *, void (^)(NSError *));
    void (^_dismiss)(void);
}

+ (void)presentOnWindow:(NSWindow *)parent crashSummary:(NSString *)crashSummary crashDetails:(NSString *)crashDetails
                 submit:(void (^)(NSDictionary *, void (^)(NSError *)))submit dismiss:(void (^)(void))dismiss {
    YFeedbackSheet *s = [[YFeedbackSheet alloc] init];
    sActiveFeedbackSheet = s;
    [s buildOn:parent crashSummary:crashSummary crashDetails:crashDetails submit:submit dismiss:dismiss];
}

static NSView *YBox(NSRect f) {
    NSView *b = [[NSView alloc] initWithFrame:f];
    b.wantsLayer = YES;
    b.layer.cornerRadius = 12;
    b.layer.backgroundColor = [NSColor whiteColor].CGColor;
    b.layer.borderColor = Y_border().CGColor;
    b.layer.borderWidth = 1;
    return b;
}
static void YRing(NSView *box, BOOL on) {
    box.layer.borderWidth = on ? 2 : 1;
    box.layer.borderColor = (on ? Y_blue() : Y_border()).CGColor;
}

- (void)buildOn:(NSWindow *)parent crashSummary:(NSString *)crashSummary crashDetails:(NSString *)crashDetails
         submit:(void (^)(NSDictionary *, void (^)(NSError *)))submit dismiss:(void (^)(void))dismiss {
    _parent = parent;
    _crash = crashSummary.length > 0;
    _submit = [submit copy];
    _dismiss = [dismiss copy];
    _kind = 0;

    const CGFloat W = 480, pad = 28, cw = W - 2 * pad;
    const CGFloat H = _crash ? 520 : 508;
    _panel = [[YSheetPanel alloc] initWithContentRect:NSMakeRect(0, 0, W, H) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    _panel.backgroundColor = [NSColor clearColor];
    _panel.opaque = NO;
    _panel.hasShadow = YES;
    _panel.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];

    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, W, H)];
    root.wantsLayer = YES;
    root.layer.cornerRadius = 24;
    root.layer.masksToBounds = YES;
    root.layer.backgroundColor = [NSColor whiteColor].CGColor;
    root.layer.borderColor = Y_hairline().CGColor;
    root.layer.borderWidth = 1;
    _panel.contentView = root;

    CGFloat y = H - pad;
    NSTextField *title = [NSTextField labelWithString:_crash ? @"Saturn quit unexpectedly" : @"Send feedback"];
    title.font = [NSFont systemFontOfSize:24 weight:NSFontWeightMedium];
    title.textColor = Y_ink();
    title.frame = NSMakeRect(pad, y - 30, cw, 30);
    [root addSubview:title];
    y -= 30 + 8;

    NSString *subText = _crash ? @"Sending a report helps us fix it. It contains technical details about the crash, never the pages you were visiting."
                               : @"Tell us what's broken or what you'd like to see. We read every message.";
    NSTextField *sub = [NSTextField wrappingLabelWithString:subText];
    sub.font = [NSFont systemFontOfSize:14];
    sub.textColor = Y_muted();
    CGFloat sh = _crash ? 40 : 20;
    sub.frame = NSMakeRect(pad, y - sh, cw, sh);
    [root addSubview:sub];
    y -= sh + 16;

    if (_crash) {
        NSTextField *what = [NSTextField labelWithString:[NSString stringWithFormat:@"What happened: %@", crashSummary]];
        what.font = [NSFont systemFontOfSize:12.5 weight:NSFontWeightMedium];
        what.textColor = Y_ink();
        what.lineBreakMode = NSLineBreakByTruncatingTail;
        what.frame = NSMakeRect(pad, y - 18, cw, 18);
        [root addSubview:what];
        y -= 18 + 6;
        NSView *dbox = YBox(NSMakeRect(pad, y - 110, cw, 110));
        dbox.layer.backgroundColor = Y_soft().CGColor;
        dbox.layer.borderWidth = 0;
        NSScrollView *ds = [[NSScrollView alloc] initWithFrame:NSMakeRect(2, 2, cw - 4, 106)];
        ds.hasVerticalScroller = YES; ds.autohidesScrollers = YES; ds.drawsBackground = NO; ds.borderType = NSNoBorder;
        NSTextView *dt = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, cw - 4, 106)];
        dt.editable = NO; dt.drawsBackground = NO;
        dt.textContainerInset = NSMakeSize(8, 8);
        dt.font = [NSFont monospacedSystemFontOfSize:10.5 weight:NSFontWeightRegular];
        dt.textColor = Y_muted();
        dt.string = crashDetails ?: @"";
        ds.documentView = dt;
        [dbox addSubview:ds];
        [root addSubview:dbox];
        y -= 110 + 12;
    } else {
        NSArray *kinds = @[@"Bug", @"Idea", @"Other"];
        NSMutableArray *kb = [NSMutableArray array];
        CGFloat x = pad;
        for (NSInteger i = 0; i < 3; i++) {
            NSButton *b = [[NSButton alloc] initWithFrame:NSMakeRect(x, y - 36, 96, 36)];
            b.bordered = NO; b.wantsLayer = YES; b.layer.cornerRadius = 18; b.tag = i; b.title = kinds[i];
            b.target = self; b.action = @selector(pickKind:);
            [root addSubview:b];
            [kb addObject:b];
            x += 96 + 8;
        }
        _kindButtons = kb;
        [self styleKinds];
        y -= 36 + 12;
    }

    CGFloat th = _crash ? 84 : 128;
    _textBox = YBox(NSMakeRect(pad, y - th, cw, th));
    NSScrollView *sc = [[NSScrollView alloc] initWithFrame:NSMakeRect(2, 2, cw - 4, th - 4)];
    sc.hasVerticalScroller = YES; sc.autohidesScrollers = YES; sc.drawsBackground = NO; sc.borderType = NSNoBorder;
    _text = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, cw - 4, th - 4)];
    _text.minSize = NSMakeSize(0, th - 4);
    _text.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    _text.verticallyResizable = YES;
    _text.autoresizingMask = NSViewWidthSizable;
    _text.textContainer.widthTracksTextView = YES;
    _text.drawsBackground = NO;
    _text.textContainerInset = NSMakeSize(10, 10);
    _text.font = [NSFont systemFontOfSize:14];
    _text.textColor = Y_ink();
    _text.insertionPointColor = Y_blue();
    _text.delegate = self;
    sc.documentView = _text;
    [_textBox addSubview:sc];
    _placeholder = [NSTextField labelWithString:_crash ? @"What were you doing? (optional)" : @"What happened, or what would you like?"];
    _placeholder.font = [NSFont systemFontOfSize:14];
    _placeholder.textColor = Y_muted2();
    _placeholder.frame = NSMakeRect(15, th - 30, cw - 30, 20);
    [_textBox addSubview:_placeholder];
    [root addSubview:_textBox];
    y -= th + 12;

    if (!_crash) {
        _emailBox = YBox(NSMakeRect(pad, y - 48, cw, 48));
        _email = [[NSTextField alloc] initWithFrame:NSMakeRect(16, 13, cw - 32, 22)];
        _email.bezeled = NO; _email.drawsBackground = NO; _email.focusRingType = NSFocusRingTypeNone;
        _email.font = [NSFont systemFontOfSize:14];
        _email.textColor = Y_ink();
        _email.placeholderAttributedString = [[NSAttributedString alloc] initWithString:@"Email (optional, if you'd like a reply)" attributes:@{NSForegroundColorAttributeName: Y_muted2(), NSFontAttributeName: [NSFont systemFontOfSize:14]}];
        [_emailBox addSubview:_email];
        [root addSubview:_emailBox];
        y -= 48 + 12;
    }

    _diag = [NSButton checkboxWithTitle:_crash ? @"Include the crash details shown above" : @"Include Saturn and macOS version" target:nil action:nil];
    _diag.state = NSControlStateValueOn;
    _diag.font = [NSFont systemFontOfSize:13];
    _diag.frame = NSMakeRect(pad, y - 22, cw, 22);
    [root addSubview:_diag];
    y -= 22 + 6;

    _error = [NSTextField wrappingLabelWithString:@""];
    _error.font = [NSFont systemFontOfSize:12.5];
    _error.textColor = Y_negative();
    _error.frame = NSMakeRect(pad, 24 + 44 + 10, cw, 34);
    [root addSubview:_error];

    _send = [[YSheetButton alloc] initWithTitle:@"Send" primary:YES frame:NSMakeRect(W - pad - 120, 24, 120, 44)];
    _send.target = self; _send.action = @selector(sendTapped:);
    _send.keyEquivalent = @"";
    _cancel = [[YSheetButton alloc] initWithTitle:_crash ? @"Don't send" : @"Cancel" primary:NO frame:NSMakeRect(W - pad - 120 - 10 - 120, 24, 120, 44)];
    _cancel.target = self; _cancel.action = @selector(cancelTapped:);
    _cancel.keyEquivalent = @"\033";
    [root addSubview:_cancel];
    [root addSubview:_send];
    [self validate];

    __weak YFeedbackSheet *weak = self;
    [parent beginSheet:_panel completionHandler:^(NSModalResponse code) {
        (void)code;
        YFeedbackSheet *strong = weak;
        [strong->_panel orderOut:nil];
        if (strong->_dismiss) strong->_dismiss();
        sActiveFeedbackSheet = nil;
    }];
    [_panel makeFirstResponder:_text];
    YRing(_textBox, YES);
}

- (void)styleKinds {
    for (NSButton *b in _kindButtons) {
        BOOL on = b.tag == _kind;
        NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
        ps.alignment = NSTextAlignmentCenter;
        b.attributedTitle = [[NSAttributedString alloc] initWithString:b.title attributes:@{
            NSForegroundColorAttributeName: on ? Y_blue() : Y_ink(),
            NSFontAttributeName: [NSFont systemFontOfSize:13.5 weight:on ? NSFontWeightBold : NSFontWeightMedium],
            NSParagraphStyleAttributeName: ps}];
        b.layer.backgroundColor = (on ? Y_soft() : [NSColor whiteColor]).CGColor;
        b.layer.borderWidth = on ? 2 : 1;
        b.layer.borderColor = (on ? Y_blue() : Y_border()).CGColor;
    }
}
- (void)pickKind:(NSButton *)sender { _kind = sender.tag; [self styleKinds]; }

- (void)textDidChange:(NSNotification *)n { (void)n; [self validate]; }
- (void)textDidBeginEditing:(NSNotification *)n { (void)n; YRing(_textBox, YES); }
- (void)textDidEndEditing:(NSNotification *)n { (void)n; YRing(_textBox, NO); }
- (void)validate {
    NSString *t = [_text.string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    _placeholder.hidden = _text.string.length > 0;
    BOOL ok = _crash || t.length >= 5;
    _send.enabled = ok;
    _send.alphaValue = ok ? 1 : 0.4;
}

- (void)setBusy:(BOOL)busy {
    _send.enabled = !busy; _cancel.enabled = !busy;
    NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
    ps.alignment = NSTextAlignmentCenter;
    _send.attributedTitle = [[NSAttributedString alloc] initWithString:busy ? @"Sending…" : @"Send" attributes:@{
        NSForegroundColorAttributeName: [NSColor whiteColor], NSFontAttributeName: [NSFont systemFontOfSize:14 weight:NSFontWeightBold], NSParagraphStyleAttributeName: ps}];
    _send.alphaValue = busy ? 0.7 : 1;
}

- (void)sendTapped:(id)sender {
    (void)sender;
    _error.stringValue = @"";
    [self setBusy:YES];
    NSDictionary *values = @{@"kind": @[@"bug", @"idea", @"other"][MAX(0, MIN(2, _kind))], @"text": _text.string ?: @"",
                             @"email": _email.stringValue ?: @"", @"diag": @(_diag.state == NSControlStateValueOn)};
    __weak YFeedbackSheet *weak = self;
    _submit(values, ^(NSError *error) {
        YFeedbackSheet *s = weak;
        if (!s) return;
        if (error) { [s setBusy:NO]; [s validate]; s->_error.stringValue = error.localizedDescription; return; }
        [s showThanks];
    });
}

- (void)showThanks {
    NSView *root = _panel.contentView;
    for (NSView *v in [root.subviews copy]) [v removeFromSuperview];
    CGFloat W = root.bounds.size.width, H = root.bounds.size.height;
    NSImageView *ic = [[NSImageView alloc] initWithFrame:NSMakeRect((W - 56) / 2, H / 2 + 6, 56, 56)];
    ic.image = Y_symbol(@"checkmark.circle.fill", 48, NSFontWeightRegular);
    ic.contentTintColor = Y_blue();
    [root addSubview:ic];
    NSTextField *t = [NSTextField labelWithString:@"Thank you"];
    t.font = [NSFont systemFontOfSize:24 weight:NSFontWeightMedium];
    t.textColor = Y_ink();
    t.alignment = NSTextAlignmentCenter;
    t.frame = NSMakeRect(0, H / 2 - 30, W, 30);
    [root addSubview:t];
    NSTextField *s = [NSTextField labelWithString:_crash ? @"Your report was sent." : @"Your feedback was sent."];
    s.font = [NSFont systemFontOfSize:14];
    s.textColor = Y_muted();
    s.alignment = NSTextAlignmentCenter;
    s.frame = NSMakeRect(0, H / 2 - 56, W, 20);
    [root addSubview:s];
    CABasicAnimation *pop = [CABasicAnimation animationWithKeyPath:@"opacity"];
    pop.fromValue = @0; pop.toValue = @1; pop.duration = 0.25;
    for (NSView *v in root.subviews) { v.wantsLayer = YES; [v.layer addAnimation:pop forKey:@"in"]; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self close]; });
}

- (void)cancelTapped:(id)sender { (void)sender; [self close]; }
- (void)close { [_parent endSheet:_panel returnCode:NSModalResponseCancel]; }
@end

#pragma mark - SaturnWindow

@implementation SaturnWindow

- (WKWebView *)webView {
    if (self.tabWebViews.count > 0 && self.activeTabIndex >= 0 && self.activeTabIndex < (NSInteger)self.tabWebViews.count) {
        return self.tabWebViews[self.activeTabIndex];
    }
    return nil;
}
- (ChromeTabView *)activeTab {
    if (self.tabs.count > 0 && self.activeTabIndex >= 0 && self.activeTabIndex < (NSInteger)self.tabs.count) {
        return self.tabs[self.activeTabIndex];
    }
    return nil;
}

- (instancetype)initWithURL:(NSURL *)url { return [self initWithURL:url privateMode:NO]; }

- (instancetype)initWithURL:(NSURL *)url privateMode:(BOOL)privateMode {
    NSRect frame = NSMakeRect(0, 0, 1360, 860);
    self = [super initWithContentRect:frame
                            styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView)
                              backing:NSBackingStoreBuffered
                                defer:NO];
    if (self) {
        self.titleVisibility = NSWindowTitleHidden;
        self.titlebarAppearsTransparent = YES;
        self.backgroundColor = [NSColor whiteColor];
        self.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
        self.minSize = NSMakeSize(1024, 680);
        self.hasShadow = YES;
        self.styleMask |= NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable;
        _isPrivate = privateMode;
        _privateStore = privateMode ? [WKWebsiteDataStore nonPersistentDataStore] : nil;   // nothing is written to disk
        _tabs = [NSMutableArray array];
        _tabWebViews = [NSMutableArray array];
        _faviconCache = [NSMutableDictionary dictionary];
        _activeTabIndex = -1;
        [self center];
        [self makeKeyAndOrderFront:nil];
        [self buildChrome];
        NSString *home = SaturnSettings.shared.currentEngineInfo.homeURL;
        if (!home.length) home = @"https://www.google.com";
        NSURL *initial = url ?: [NSURL URLWithString:home];
        [self createNewTabWithURL:initial];
    }
    return self;
}

- (void)chromeDidResize:(NSNotification *)n { (void)n; [self layoutChrome]; }

- (CGFloat)currentChromeH {
    CGFloat b = self.bookmarksBar.hidden ? 0 : SaturnBookmarksH();
    return SaturnTabBarH() + SaturnToolbarH() + b + SaturnProgressH();
}

- (void)toggleFavoritesBar:(id)sender {
    (void)sender;
    self.bookmarksBar.hidden = !self.bookmarksBar.hidden;
    [self layoutChrome];
}

// Centre the close/minimise/zoom buttons on the tab bar (the default title bar is shorter).
- (void)alignTrafficLights {
    NSButton *close = [self standardWindowButton:NSWindowCloseButton];
    NSView *titlebar = close.superview;
    NSView *container = titlebar.superview;
    if (!close || !titlebar || !container) return;
    CGFloat barH = SaturnTabBarH();
    CGFloat frameH = container.superview.bounds.size.height;
    container.frame = NSMakeRect(container.frame.origin.x, frameH - barH, container.frame.size.width, barH);
    titlebar.frame = container.bounds;
    for (NSNumber *t in @[@(NSWindowCloseButton), @(NSWindowMiniaturizeButton), @(NSWindowZoomButton)]) {
        NSButton *b = [self standardWindowButton:(NSWindowButton)t.integerValue];
        if (!b) continue;
        NSRect f = b.frame;
        f.origin.y = (barH - f.size.height) / 2;
        b.frame = f;
    }
}

- (void)layoutChrome {
    NSView *content = self.contentView;
    if (!content || !self.tabBar || !self.toolbarView) return;
    CGFloat W = content.bounds.size.width;
    CGFloat H = content.bounds.size.height;
    if (W < 100 || H < 200) return;
    const CGFloat tabBarH = SaturnTabBarH(), toolbarH = SaturnToolbarH(), progressH = SaturnProgressH();
    const CGFloat bookmarksH = self.bookmarksBar.hidden ? 0 : SaturnBookmarksH();
    self.tabBar.frame = NSMakeRect(0, H - tabBarH, W, tabBarH);
    self.toolbarView.frame = NSMakeRect(0, H - tabBarH - toolbarH, W, toolbarH);
    self.bookmarksBar.frame = NSMakeRect(0, H - tabBarH - toolbarH - bookmarksH, W, bookmarksH);
    self.progress.frame = NSMakeRect(0, H - tabBarH - toolbarH - bookmarksH - progressH, W, progressH);
    CGFloat webH = H - tabBarH - toolbarH - bookmarksH - progressH;
    for (WKWebView *wv in self.tabWebViews) {
        NSRect f = wv.frame;
        f.origin.x = 0; f.origin.y = 0; f.size.width = W; f.size.height = webH;
        wv.frame = f;
    }
    // Sidebar tracks height
    if (self.aiSidebar) {
        CGFloat sidebarW = 380;
        NSRect sf = self.aiSidebar.frame;
        sf.size.height = webH;
        sf.size.width = sidebarW;
        sf.origin.y = 0;
        sf.origin.x = self.aiSidebarVisible ? (W - sidebarW - 12) : W;
        // keep 12px floating margin when visible
        if (self.aiSidebarVisible) sf.size.height = webH - 24, sf.origin.y = 12;
        self.aiSidebar.frame = sf;
    }
    // Toolbar internals: Safari rounded-rect field centered, clusters pinned
    CGFloat omniboxW = MIN(680, MAX(340, W - 620));
    CGFloat omniboxX = (W - omniboxW) / 2;
    if (self.omniboxContainer) {
        NSRect of = self.omniboxContainer.frame;
        of.origin.x = omniboxX; of.origin.y = 9; of.size.width = omniboxW; of.size.height = 38;
        self.omniboxContainer.frame = of;
        // address field + trailing icons track width
        for (NSView *sub in self.omniboxContainer.subviews) {
            if (sub == self.addressBar) {
                NSRect af = sub.frame;
                af.origin.x = 40; af.origin.y = 10; af.size.width = omniboxW - 40 - 120; af.size.height = 18;
                sub.frame = af;
            } else if (sub == self.reloadBtn) {
                NSRect bf = sub.frame; bf.origin.x = omniboxW - 108; bf.origin.y = 5; sub.frame = bf;
            } else if (sub == self.shieldButton) {
                NSRect bf = sub.frame; bf.origin.x = omniboxW - 76; bf.origin.y = 5; sub.frame = bf;
            } else if ([sub isKindOfClass:[NSButton class]] && sub != self.shieldButton && sub != self.reloadBtn && sub.tag == 777) {
                NSRect bf = sub.frame; bf.origin.x = omniboxW - 48; bf.origin.y = 5; sub.frame = bf;
            }
        }
    }
    [self layoutTabs];
    [self alignTrafficLights];
    [self layoutFindBar];
    [self rebuildFavoritesBar];
    [self layoutSuggestions];
    [self layoutPrompt];
    [self layoutAgentOverlay];
}

- (void)buildChrome {
    NSView *content = self.contentView;
    content.wantsLayer = YES;
    content.layer.backgroundColor = [NSColor whiteColor].CGColor;

    CGFloat W0 = content.bounds.size.width > 0 ? content.bounds.size.width : 1360;
    CGFloat H0 = content.bounds.size.height > 0 ? content.bounds.size.height : 860;
    const CGFloat tabBarH = SaturnTabBarH();
    const CGFloat toolbarH = SaturnToolbarH();
    const CGFloat bookmarksH = SaturnBookmarksH();
    const CGFloat progressH = SaturnProgressH();

    // Tab bar — native titlebar material, traffic-light aware
    NSVisualEffectView *tabBar = GlassBar(NSMakeRect(0, H0 - tabBarH, W0, tabBarH), NSVisualEffectMaterialTitlebar, 1.0);
    tabBar.layer.cornerRadius = 0;
    ((NSView *)tabBar.subviews.firstObject).layer.backgroundColor = (self.isPrivate ? Y_ink() : Y_soft()).CGColor;
    // Sidebar toggle (Safari-style) tucked right of traffic lights
    NSButton *sideBtn = SaturnPlainButton(@"sidebar.left", @selector(toggleFavoritesBar:), self, NSMakeRect(76, 6, 32, 32), 15);
    sideBtn.toolTip = @"Show/Hide Favorites Bar";
    if (self.isPrivate) { ((YIconButton *)sideBtn).onDark = YES; sideBtn.contentTintColor = [NSColor whiteColor]; }
    [tabBar addSubview:sideBtn];
    if (self.isPrivate) {
        NSView *badge = [[NSView alloc] initWithFrame:NSMakeRect(W0 - 16 - 104, 10, 104, 24)];
        badge.wantsLayer = YES;
        badge.layer.cornerRadius = 12;
        badge.layer.backgroundColor = [NSColor colorWithWhite:1 alpha:0.16].CGColor;
        badge.autoresizingMask = NSViewMinXMargin;
        NSImageView *eye = [[NSImageView alloc] initWithFrame:NSMakeRect(10, 4, 16, 16)];
        eye.image = Y_symbol(@"eye.slash", 12, NSFontWeightBold);
        eye.contentTintColor = [NSColor whiteColor];
        [badge addSubview:eye];
        NSTextField *t = [NSTextField labelWithString:@"Private"];
        t.font = [NSFont systemFontOfSize:12 weight:NSFontWeightBold];
        t.textColor = [NSColor whiteColor];
        t.frame = NSMakeRect(30, 4, 66, 16);
        [badge addSubview:t];
        badge.toolTip = @"Private window: history, cookies and site data are not saved";
        [tabBar addSubview:badge];
    }
    self.tabBar = tabBar;
    [content addSubview:tabBar];

    self.addTabButton = SaturnPlainButton(@"plus", @selector(handleNewTab:), self, NSMakeRect(116 + 206, 6, 32, 32), 16);
    self.addTabButton.toolTip = @"New Tab (⌘T)";
    if (self.isPrivate) { ((YIconButton *)self.addTabButton).onDark = YES; self.addTabButton.contentTintColor = [NSColor whiteColor]; }
    [self.tabBar addSubview:self.addTabButton];

    // Toolbar — native titlebar material for seamless unified chrome (Safari-style)
    NSVisualEffectView *toolbar = GlassBar(NSMakeRect(0, H0 - tabBarH - toolbarH, W0, toolbarH), NSVisualEffectMaterialTitlebar, 1.0);
    AddBottomHairline(toolbar);
    self.toolbarView = toolbar;
    [content addSubview:toolbar];

    self.backBtn = SaturnPlainButton(@"chevron.left", @selector(goBack:), self, NSMakeRect(10, 11, 34, 34), 17);
    self.backBtn.toolTip = @"Back";
    [toolbar addSubview:self.backBtn];
    self.forwardBtn = SaturnPlainButton(@"chevron.right", @selector(goForward:), self, NSMakeRect(48, 11, 34, 34), 17);
    self.forwardBtn.toolTip = @"Forward";
    [toolbar addSubview:self.forwardBtn];

    // Omnibox — Safari-style rounded-rect field (solid, subtle)
    CGFloat omniboxW = MIN(680, MAX(340, W0 - 620));
    CGFloat omniboxX = (W0 - omniboxW)/2;
    NSView *omnibox = [[NSView alloc] initWithFrame:NSMakeRect(omniboxX, 9, omniboxW, 38)];
    omnibox.wantsLayer = YES;
    omnibox.layer.cornerRadius = 19;
    omnibox.layer.masksToBounds = NO;
    omnibox.layer.backgroundColor = Y_soft().CGColor;
    omnibox.layer.borderColor = [NSColor clearColor].CGColor;
    omnibox.layer.borderWidth = 2;
    self.omniboxContainer = omnibox;
    [toolbar addSubview:omnibox];
    // Click anywhere in field focuses address bar
    NSClickGestureRecognizer *omniboxClick = [[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(focusOmnibox:)];
    omniboxClick.buttonMask = 0x1;
    omniboxClick.delaysPrimaryMouseButtonEvents = NO;   // otherwise the buttons inside the field never see the click
    [omnibox addGestureRecognizer:omniboxClick];

    NSImageView *searchIcon = [[NSImageView alloc] initWithFrame:NSMakeRect(16, 11, 16, 16)];
    searchIcon.image = [NSImage imageWithSystemSymbolName:@"magnifyingglass" accessibilityDescription:nil];
    searchIcon.contentTintColor = Y_muted2();
    if (searchIcon.image) { searchIcon.image.size = NSMakeSize(13, 13); [searchIcon.image setTemplate:YES]; }
    [self.omniboxContainer addSubview:searchIcon];

    self.addressBar = [[NSTextField alloc] initWithFrame:NSMakeRect(40, 10, omniboxW - 40 - 120, 18)];
    NSString *ph = [NSString stringWithFormat:@"Search %@ or enter website name", SaturnSettings.shared.currentEngineInfo.shortName ?: @"Google"];
    self.addressBar.placeholderString = ph;
    self.addressBar.stringValue = SaturnSettings.shared.currentEngineInfo.homeURL ?: @"";
    self.addressBar.bezeled = NO;
    self.addressBar.drawsBackground = NO;
    self.addressBar.focusRingType = NSFocusRingTypeNone;
    self.addressBar.delegate = self;
    self.addressBar.target = self;
    self.addressBar.action = @selector(goAddress:);
    self.addressBar.font = [NSFont systemFontOfSize:14 weight:NSFontWeightRegular];
    self.addressBar.textColor = Y_ink();
    self.addressBar.alignment = NSTextAlignmentLeft;
    self.addressBar.editable = YES;
    self.addressBar.selectable = YES;
    self.addressBar.enabled = YES;
    self.addressBar.usesSingleLineMode = YES;
    self.addressBar.cell.scrollable = YES;
    self.addressBar.cell.wraps = NO;
    self.addressBar.cell.truncatesLastVisibleLine = YES;
    self.addressBar.refusesFirstResponder = NO;
    ((NSTextFieldCell *)self.addressBar.cell).placeholderAttributedString = [[NSAttributedString alloc] initWithString:ph attributes:@{NSForegroundColorAttributeName: Y_muted2(), NSFontAttributeName: [NSFont systemFontOfSize:14]}];
    [self.omniboxContainer addSubview:self.addressBar];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateSearchPlaceholder) name:@"SaturnSearchEngineChanged" object:nil];

    // Reload inside the field (Safari-style)
    self.reloadBtn = SaturnPlainButton(@"arrow.clockwise", @selector(reloadOrStop:), self, NSMakeRect(omniboxW - 108, 5, 28, 28), 14);
    self.reloadBtn.toolTip = @"Reload (⌘R)";
    [self.omniboxContainer addSubview:self.reloadBtn];

    // Saturn Shield button
    NSButton *shieldBtn = SaturnPlainButton(@"checkmark.shield.fill", @selector(showShieldPopover:), self, NSMakeRect(omniboxW - 76, 5, 28, 28), 14);
    shieldBtn.contentTintColor = Y_positive();
    shieldBtn.toolTip = @"Saturn Shield — Ad & Tracker Blocker";
    self.shieldButton = shieldBtn;
    [self.omniboxContainer addSubview:shieldBtn];

    NSButton *starBtn = SaturnPlainButton(@"bookmark", @selector(star:), self, NSMakeRect(omniboxW - 48, 5, 28, 28), 14);
    starBtn.tag = 777;
    starBtn.contentTintColor = Y_muted();
    starBtn.toolTip = @"Bookmark this page";
    self.bookmarkButton = starBtn;
    [self.omniboxContainer addSubview:starBtn];

    // Right cluster pinned to trailing edge: share + sidebar + Zarah + avatar (Safari-style)
    CGFloat (^rx)(CGFloat) = ^CGFloat(CGFloat off){ return W0 - off; };
    NSButton *shareBtn = SaturnPlainButton(@"exclamationmark.bubble", @selector(showFeedbackSheet:), self, NSMakeRect(rx(188), 11, 34, 34), 15);
    shareBtn.autoresizingMask = NSViewMinXMargin;
    shareBtn.toolTip = @"Send feedback";
    [toolbar addSubview:shareBtn];
    NSButton *tabsBtn = SaturnPlainButton(@"square.on.square", nil, nil, NSMakeRect(rx(150), 11, 34, 34), 15);
    tabsBtn.autoresizingMask = NSViewMinXMargin;
    tabsBtn.toolTip = @"Tab Overview";
    [toolbar addSubview:tabsBtn];
    // Downloads button (appears after the first download), with a progress ring
    NSButton *dlBtn = SaturnPlainButton(@"arrow.down.circle", @selector(showDownloads:), self, NSMakeRect(rx(226), 11, 34, 34), 17);
    dlBtn.autoresizingMask = NSViewMinXMargin;
    dlBtn.toolTip = @"Downloads (⇧⌘J)";
    dlBtn.hidden = [SaturnDownloads shared].items.count == 0;
    CAShapeLayer *ring = [CAShapeLayer layer];
    ring.frame = CGRectMake(0, 0, 34, 34);
    CGPathRef rp = CGPathCreateWithEllipseInRect(CGRectMake(2, 2, 30, 30), NULL);
    ring.path = rp; CGPathRelease(rp);
    ring.fillColor = NULL;
    ring.strokeColor = Y_blue().CGColor;
    ring.lineWidth = 2;
    ring.lineCap = kCALineCapRound;
    ring.transform = CATransform3DMakeRotation(-M_PI_2, 0, 0, 1);
    ring.hidden = YES;
    [dlBtn.layer addSublayer:ring];
    self.downloadsRing = ring;
    self.downloadsButton = dlBtn;
    [toolbar addSubview:dlBtn];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(downloadsChanged:) name:SaturnDownloadsChangedNotification object:nil];
    [self updateDownloadsButton];

    // Update pill (only visible when a newer release exists)
    YSheetButton *upBtn = [[YSheetButton alloc] initWithTitle:@"Update" primary:YES frame:NSMakeRect(rx(334), 12, 100, 32)];
    upBtn.target = self;
    upBtn.action = @selector(showUpdatePopover:);
    upBtn.autoresizingMask = NSViewMinXMargin;
    upBtn.hidden = YES;
    self.updateButton = upBtn;
    [toolbar addSubview:upBtn];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateStateChanged:) name:SaturnUpdateStateChangedNotification object:nil];
    [self updateUpdateButton];

    // Zarah AI Assistant button — compact violet key
    NSButton *aiBtn = [NSButton buttonWithTitle:@"" target:self action:@selector(toggleAISidebar)];
    aiBtn.frame = NSMakeRect(rx(108), 14, 28, 28);
    aiBtn.bezelStyle = NSBezelStyleCircular;
    aiBtn.bordered = NO;
    aiBtn.wantsLayer = YES;
    aiBtn.layer.cornerRadius = 14;
    aiBtn.layer.masksToBounds = NO;
    aiBtn.layer.backgroundColor = Y_blue().CGColor;
    aiBtn.autoresizingMask = NSViewMinXMargin;
    aiBtn.toolTip = @"✦ Zarah AI Assistant (⌘I)";
    self.aiButton = aiBtn;

    NSImage *aiImg = [NSImage imageWithSystemSymbolName:@"sparkles" accessibilityDescription:@"Zarah"];
    if (aiImg) { aiImg.size = NSMakeSize(14, 14); [aiImg setTemplate:YES]; }
    aiBtn.image = aiImg;
    aiBtn.imagePosition = NSImageOnly;
    aiBtn.contentTintColor = [NSColor whiteColor];
    aiBtn.hidden = NO; // Re-enabled fresh AI sidebar
    [toolbar addSubview:aiBtn];

    // Avatar — live from Supabase profiles.avatar_url
    NSButton *avatarBtn = [NSButton buttonWithTitle:@"" target:self action:@selector(showAuth:)];
    avatarBtn.frame = NSMakeRect(W0 - 40, 14, 28, 28);
    avatarBtn.bezelStyle = NSBezelStyleCircular;
    avatarBtn.bordered = NO;
    avatarBtn.wantsLayer = YES;
    avatarBtn.layer.cornerRadius = 14;
    avatarBtn.layer.masksToBounds = YES;
    avatarBtn.layer.backgroundColor = Y_soft().CGColor;
    avatarBtn.autoresizingMask = NSViewMinXMargin;
    avatarBtn.toolTip = @"Account";
    self.avatarButton = avatarBtn;

    NSImageView *avatarIV = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 28, 28)];
    avatarIV.imageScaling = NSImageScaleAxesIndependently;
    avatarIV.wantsLayer = YES;
    avatarIV.layer.cornerRadius = 14;
    avatarIV.layer.masksToBounds = YES;
    avatarIV.hidden = YES;
    self.avatarImageView = avatarIV;
    // placeholder person glyph (replaced by avatar_url)
    NSImageView *p = [[NSImageView alloc] initWithFrame:NSMakeRect(7, 7, 14, 14)];
    p.image = [NSImage imageWithSystemSymbolName:@"person.circle" accessibilityDescription:nil];
    if (p.image) { p.image.size = NSMakeSize(14, 14); [p.image setTemplate:YES]; }
    p.contentTintColor = Y_ink();
    p.tag = 999;
    [avatarBtn addSubview:avatarIV];
    [avatarBtn addSubview:p];
    [toolbar addSubview:avatarBtn];
    // observe profile updates
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleProfileUpdated:) name:@"SaturnProfileUpdated" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleSessionChanged:) name:@"SupabaseSessionChanged" object:nil];
    // initial load
    [self updateAvatarFromProfile];

    // Favorites bar — Safari-style plain text items
    NSVisualEffectView *bookmarks = GlassBar(NSMakeRect(0, H0 - tabBarH - toolbarH - bookmarksH, W0, bookmarksH), NSVisualEffectMaterialSidebar, 1.0);
    self.bookmarksBar = bookmarks;
    [content addSubview:bookmarks];
    AddBottomHairline(bookmarks);
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(bookmarksChanged:) name:SaturnBookmarksChangedNotification object:nil];
    [self rebuildFavoritesBar];
    [self updateBookmarkButton];

    // Progress — Safari blue hairline
    self.progress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0, H0 - tabBarH - toolbarH - bookmarksH - progressH, W0, progressH)];
    self.progress.style = NSProgressIndicatorStyleBar;
    self.progress.indeterminate = YES;
    self.progress.hidden = YES;
    self.progress.controlSize = NSControlSizeMini;
    self.progress.wantsLayer = YES;
    self.progress.layer.backgroundColor = Y_blue().CGColor;
    self.progress.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [content addSubview:self.progress];

    // AI Sidebar — floating Yavqo card: white, 24px radius, hairline border, soft float shadow
    CGFloat sidebarW = 380;
    CGFloat webH = H0 - tabBarH - toolbarH - bookmarksH - progressH;
    CGFloat cardH = webH - 24;
    NSVisualEffectView *sidebar = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(W0, 12, sidebarW, cardH)];
    sidebar.material = NSVisualEffectMaterialPopover;
    sidebar.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    sidebar.state = NSVisualEffectStateActive;
    sidebar.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    sidebar.wantsLayer = YES;
    sidebar.layer.cornerRadius = 24;
    sidebar.layer.masksToBounds = NO;
    sidebar.layer.borderColor = Y_hairline().CGColor;
    sidebar.layer.borderWidth = 1;
    sidebar.layer.shadowColor = [NSColor blackColor].CGColor;
    sidebar.layer.shadowOpacity = 0.20;
    sidebar.layer.shadowRadius = 10;
    sidebar.layer.shadowOffset = NSMakeSize(0, -8);

    // Opaque white surface, clipped to the rounded card
    NSView *tint = [[NSView alloc] initWithFrame:sidebar.bounds];
    tint.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    tint.wantsLayer = YES;
    tint.layer.backgroundColor = [NSColor whiteColor].CGColor;
    tint.layer.cornerRadius = 24;
    tint.layer.masksToBounds = YES;
    [sidebar addSubview:tint positioned:NSWindowBelow relativeTo:nil];
    sidebar.autoresizingMask = NSViewMinXMargin | NSViewHeightSizable;
    sidebar.hidden = YES;
    sidebar.alphaValue = 0;
    self.aiSidebar = sidebar;
    self.aiSidebarVisible = NO;
    [content addSubview:sidebar positioned:NSWindowAbove relativeTo:nil];

    // Zarah chat history
    self.hannaHistory = [NSMutableArray array];

    // === Layout constants (all relative to the card, not the web area) ===
    CGFloat headerH = 64;
    CGFloat inputH = 52;
    CGFloat inputY = 16;
    CGFloat scrollBottom = inputY + inputH + 12;
    CGFloat modeH = 44;
    CGFloat scrollH = cardH - headerH - modeH - scrollBottom;
    if (scrollH < 100) scrollH = 100;

    // === TOP: Header (plain, transparent) ===
    NSView *dragHeader = [[NSView alloc] initWithFrame:NSMakeRect(0, cardH - headerH, sidebarW, headerH)];
    dragHeader.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [sidebar addSubview:dragHeader];

    NSView *starBadge = HannaAvatar(36);
    starBadge.frame = NSMakeRect(18, 14, 36, 36);
    [dragHeader addSubview:starBadge];

    NSTextField *aiTitle = [NSTextField labelWithString:@"Zarah"];
    aiTitle.font = [NSFont systemFontOfSize:16 weight:NSFontWeightBold];
    aiTitle.textColor = Y_ink();
    aiTitle.frame = NSMakeRect(62, 31, 150, 20);
    [dragHeader addSubview:aiTitle];

    NSTextField *aiSub = [NSTextField labelWithString:@"Vercel AI Gateway · mimo-v2.6-flash"];
    aiSub.font = [NSFont systemFontOfSize:12 weight:NSFontWeightRegular];
    aiSub.textColor = Y_muted();
    aiSub.frame = NSMakeRect(62, 14, 170, 16);
    [dragHeader addSubview:aiSub];

    // Header right: voice, new chat, close — 32px soft circles
    NSArray *hdrBtns = @[
        @{@"sym": @"mic.fill", @"sel": @"toggleVoiceAgent:", @"tip": @"Talk with Zarah"},
        @{@"sym": @"square.and.pencil", @"sel": @"hannaNewChat:", @"tip": @"New chat"},
        @{@"sym": @"xmark", @"sel": @"toggleAISidebar", @"tip": @"Close"},
    ];
    CGFloat hbx = sidebarW - 18 - 32;
    for (NSInteger i = (NSInteger)hdrBtns.count - 1; i >= 0; i--) {
        NSDictionary *d = hdrBtns[i];
        NSButton *b = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:d[@"sym"] accessibilityDescription:d[@"tip"]] target:self action:NSSelectorFromString(d[@"sel"])];
        b.frame = NSMakeRect(hbx, 16, 32, 32);
        b.bezelStyle = NSBezelStyleCircular;
        b.bordered = NO;
        b.imageScaling = NSImageScaleProportionallyDown;
        b.wantsLayer = YES;
        b.layer.backgroundColor = Y_soft().CGColor;
        b.layer.cornerRadius = 16;
        b.contentTintColor = Y_ink();
        b.toolTip = d[@"tip"];
        b.autoresizingMask = NSViewMinXMargin;
        [dragHeader addSubview:b];
        if (i == 0) self.hannaHeaderVoiceButton = b;
        hbx -= 32 + 8;
    }

    // === Chat / Act switch ===
    NSView *modeBar = [[NSView alloc] initWithFrame:NSMakeRect(0, cardH - headerH - modeH, sidebarW, modeH)];
    modeBar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [sidebar addSubview:modeBar];
    NSView *seg = [[NSView alloc] initWithFrame:NSMakeRect(18, 6, 150, 32)];
    seg.wantsLayer = YES;
    seg.layer.cornerRadius = 16;
    seg.layer.backgroundColor = Y_soft().CGColor;
    [modeBar addSubview:seg];
    NSArray *segTitles = @[@"Chat", @"Act"];
    for (NSInteger i = 0; i < 2; i++) {
        NSButton *b = [[NSButton alloc] initWithFrame:NSMakeRect(3 + i * 72, 3, 72, 26)];
        b.bordered = NO;
        b.wantsLayer = YES;
        b.layer.cornerRadius = 13;
        b.tag = i;
        b.target = self;
        b.action = @selector(setHannaMode:);
        b.toolTip = i == 0 ? @"Ask Zarah questions about the page" : @"Let Zarah click, type and open pages for you";
        b.title = segTitles[i];
        [seg addSubview:b];
        if (i == 0) self.chatModeButton = b; else self.actModeButton = b;
    }
    self.modeHint = [NSTextField wrappingLabelWithString:@""];
    self.modeHint.font = [NSFont systemFontOfSize:11.5];
    self.modeHint.textColor = Y_muted();
    self.modeHint.frame = NSMakeRect(178, 5, sidebarW - 178 - 18, 34);
    [modeBar addSubview:self.modeHint];
    [self applyHannaMode];

    // === MIDDLE: Scroll view for chat stream ===
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(14, scrollBottom, sidebarW - 28, scrollH)];
    scroll.hasVerticalScroller = YES;
    scroll.hasHorizontalScroller = NO;
    scroll.autohidesScrollers = YES;
    scroll.borderType = NSNoBorder;
    scroll.drawsBackground = NO;
    scroll.backgroundColor = [NSColor clearColor];
    scroll.contentView.drawsBackground = NO;
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    HannaChatDocView *docView = [[HannaChatDocView alloc] initWithFrame:NSMakeRect(0, 0, scroll.contentSize.width, scroll.contentSize.height)];
    docView.autoresizingMask = NSViewWidthSizable;
    scroll.documentView = docView;
    self.hannaScrollView = scroll;
    [sidebar addSubview:scroll];

    // === VOICE AGENT HUD (soft grey card with live wave bars) ===
    NSView *voiceHUD = [[NSView alloc] initWithFrame:NSMakeRect(16, inputY + inputH + 10, sidebarW - 32, 60)];
    voiceHUD.wantsLayer = YES;
    voiceHUD.layer.cornerRadius = 20;
    voiceHUD.layer.masksToBounds = YES;
    voiceHUD.layer.backgroundColor = Y_soft().CGColor;
    voiceHUD.hidden = YES;
    voiceHUD.autoresizingMask = NSViewWidthSizable;
    self.hannaVoiceHUD = voiceHUD;
    [sidebar addSubview:voiceHUD];

    NSView *waveBox = [[NSView alloc] initWithFrame:NSMakeRect(18, 13, 34, 34)];
    self.hannaVoiceWaveBars = [NSMutableArray array];
    for (int i = 0; i < 5; i++) {
        NSView *bar = [[NSView alloc] initWithFrame:NSMakeRect(i * 7, 13, 4, 8)];
        bar.wantsLayer = YES;
        bar.layer.cornerRadius = 2;
        bar.layer.backgroundColor = Y_blue().CGColor;
        [waveBox addSubview:bar];
        [self.hannaVoiceWaveBars addObject:bar];
    }
    [voiceHUD addSubview:waveBox];

    self.hannaVoiceStatusLabel = [NSTextField labelWithString:@"● Listening…"];
    self.hannaVoiceStatusLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightBold];
    self.hannaVoiceStatusLabel.textColor = Y_ink();
    self.hannaVoiceStatusLabel.frame = NSMakeRect(60, 31, voiceHUD.bounds.size.width - 100, 18);
    self.hannaVoiceStatusLabel.autoresizingMask = NSViewWidthSizable;
    [voiceHUD addSubview:self.hannaVoiceStatusLabel];

    self.hannaVoiceTranscriptLabel = [NSTextField labelWithString:@"Say something to Zarah…"];
    self.hannaVoiceTranscriptLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightRegular];
    self.hannaVoiceTranscriptLabel.textColor = Y_muted();
    self.hannaVoiceTranscriptLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.hannaVoiceTranscriptLabel.frame = NSMakeRect(60, 11, voiceHUD.bounds.size.width - 100, 16);
    self.hannaVoiceTranscriptLabel.autoresizingMask = NSViewWidthSizable;
    [voiceHUD addSubview:self.hannaVoiceTranscriptLabel];

    NSButton *hudStop = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"xmark" accessibilityDescription:@"Stop"] target:self action:@selector(toggleVoiceAgent:)];
    hudStop.frame = NSMakeRect(voiceHUD.bounds.size.width - 42, 14, 32, 32);
    hudStop.bezelStyle = NSBezelStyleCircular;
    hudStop.bordered = NO;
    hudStop.wantsLayer = YES;
    hudStop.layer.backgroundColor = [NSColor whiteColor].CGColor;
    hudStop.layer.cornerRadius = 16;
    hudStop.contentTintColor = Y_ink();
    hudStop.autoresizingMask = NSViewMinXMargin;
    [voiceHUD addSubview:hudStop];

    // === BOTTOM: pill input ===
    NSView *inputGlass = [[NSView alloc] initWithFrame:NSMakeRect(16, inputY, sidebarW - 32, inputH)];
    inputGlass.wantsLayer = YES;
    inputGlass.layer.cornerRadius = inputH / 2;
    inputGlass.layer.backgroundColor = [NSColor whiteColor].CGColor;
    inputGlass.layer.borderColor = Y_border().CGColor;
    inputGlass.layer.borderWidth = 1.0;
    inputGlass.autoresizingMask = NSViewWidthSizable;
    [sidebar addSubview:inputGlass];
    CGFloat inW = inputGlass.bounds.size.width;

    self.hannaInputField = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 11, inW - 20 - 94, 30)];
    self.hannaInputField.bezeled = NO;
    self.hannaInputField.drawsBackground = NO;
    self.hannaInputField.focusRingType = NSFocusRingTypeNone;
    self.hannaInputField.font = [NSFont systemFontOfSize:14 weight:NSFontWeightRegular];
    self.hannaInputField.textColor = Y_ink();
    self.hannaInputField.delegate = self;
    self.hannaInputField.target = self;
    self.hannaInputField.action = @selector(hannaSend:);
    self.hannaInputField.placeholderAttributedString = [[NSAttributedString alloc] initWithString:@"Ask Zarah anything" attributes:@{NSForegroundColorAttributeName: Y_muted2(), NSFontAttributeName: [NSFont systemFontOfSize:14]}];
    self.hannaInputField.autoresizingMask = NSViewWidthSizable;
    [inputGlass addSubview:self.hannaInputField];

    // Mic: soft circle
    self.hannaVoiceButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"mic.fill" accessibilityDescription:@"Voice input"] target:self action:@selector(toggleVoiceAgent:)];
    self.hannaVoiceButton.frame = NSMakeRect(inW - 88, 8, 36, 36);
    self.hannaVoiceButton.bezelStyle = NSBezelStyleCircular;
    self.hannaVoiceButton.bordered = NO;
    self.hannaVoiceButton.wantsLayer = YES;
    self.hannaVoiceButton.layer.backgroundColor = Y_soft().CGColor;
    self.hannaVoiceButton.layer.cornerRadius = 18;
    self.hannaVoiceButton.contentTintColor = Y_ink();
    self.hannaVoiceButton.toolTip = @"Talk to Zarah";
    self.hannaVoiceButton.autoresizingMask = NSViewMinXMargin;
    [inputGlass addSubview:self.hannaVoiceButton];

    // Send: blue circle
    self.hannaSendButton = [NSButton buttonWithTitle:@"" target:self action:@selector(hannaSend:)];
    self.hannaSendButton.frame = NSMakeRect(inW - 44, 8, 36, 36);
    self.hannaSendButton.bezelStyle = NSBezelStyleCircular;
    self.hannaSendButton.bordered = NO;
    self.hannaSendButton.wantsLayer = YES;
    self.hannaSendButton.layer.backgroundColor = Y_blue().CGColor;
    self.hannaSendButton.layer.cornerRadius = 18;
    NSImageView *arrow = [[NSImageView alloc] initWithFrame:NSMakeRect(9, 9, 18, 18)];
    arrow.image = [NSImage imageWithSystemSymbolName:@"arrow.up" accessibilityDescription:@"Send"];
    arrow.contentTintColor = [NSColor whiteColor];
    [self.hannaSendButton addSubview:arrow];
    self.hannaSendButton.autoresizingMask = NSViewMinXMargin;
    [inputGlass addSubview:self.hannaSendButton];

    // Spinner (kept for state; the typing dots are the visible indicator)
    self.hannaSpinner = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(sidebarW/2 - 12, cardH/2 - 12, 24, 24)];
    self.hannaSpinner.style = NSProgressIndicatorStyleSpinning;
    self.hannaSpinner.controlSize = NSControlSizeSmall;
    self.hannaSpinner.displayedWhenStopped = NO;
    self.hannaSpinner.hidden = YES;
    self.hannaSpinner.alphaValue = 0;
    [sidebar addSubview:self.hannaSpinner];

    // Initialize with welcome message & action chips
    [self hannaNewChat:nil];

    [self updateNavButtons];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(addressBarDidBecomeFirstResponder:) name:NSControlTextDidBeginEditingNotification object:self.addressBar];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(addressBarDidResignFirstResponder:) name:NSControlTextDidEndEditingNotification object:self.addressBar];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(chromeDidResize:) name:NSWindowDidResizeNotification object:self];
    [self layoutChrome];
    dispatch_async(dispatch_get_main_queue(), ^{ [self alignTrafficLights]; });
}

- (void)bookmarksChanged:(NSNotification *)n {
    (void)n;
    [self rebuildFavoritesBar];
    [self updateBookmarkButton];
}

// Favorites bar shows the saved bookmarks that fit; right-click a chip to remove it.
- (void)rebuildFavoritesBar {
    NSView *bar = self.bookmarksBar;
    if (!bar) return;
    NSArray<NSDictionary<NSString *, NSString *> *> *items = [SaturnBookmarks shared].items;
    NSMutableString *sig = [NSMutableString stringWithFormat:@"%.0f|", bar.bounds.size.width];
    for (NSDictionary *it in items) [sig appendFormat:@"%@\n", it[@"url"]];
    if ([sig isEqualToString:self.favoritesSignature]) return;
    self.favoritesSignature = sig;

    for (NSView *v in [bar.subviews copy]) if ([v isKindOfClass:[YIconButton class]]) [v removeFromSuperview];
    NSDictionary *attrs = @{NSForegroundColorAttributeName: Y_ink(), NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightRegular]};
    CGFloat bx = 12, maxX = bar.bounds.size.width - 12;
    for (NSDictionary *it in items) {
        NSString *t = it[@"title"];
        CGFloat cw = MIN(160, ceil([t sizeWithAttributes:attrs].width) + 24);
        if (bx + cw > maxX) break;
        YIconButton *chip = [[YIconButton alloc] initWithFrame:NSMakeRect(bx, 3, cw, 26)];
        chip.target = self; chip.action = @selector(bookmarkChipTapped:);
        chip.wantsLayer = YES;
        chip.attributedTitle = [[NSAttributedString alloc] initWithString:t attributes:attrs];
        chip.lineBreakMode = NSLineBreakByTruncatingTail;
        chip.identifier = it[@"url"];
        chip.toolTip = it[@"url"];
        chip.bezelStyle = NSBezelStyleInline;
        chip.bordered = NO;
        NSMenu *m = [[NSMenu alloc] initWithTitle:@""];
        NSMenuItem *open = [[NSMenuItem alloc] initWithTitle:@"Open in New Tab" action:@selector(menuOpenBookmarkInNewTab:) keyEquivalent:@""];
        open.target = self; open.representedObject = it[@"url"];
        NSMenuItem *rm = [[NSMenuItem alloc] initWithTitle:@"Remove Bookmark" action:@selector(menuRemoveBookmark:) keyEquivalent:@""];
        rm.target = self; rm.representedObject = it[@"url"];
        [m addItem:open]; [m addItem:rm];
        chip.menu = m;
        [bar addSubview:chip];
        bx += cw + 4;
    }
}
- (void)menuOpenBookmarkInNewTab:(NSMenuItem *)it {
    NSURL *u = [NSURL URLWithString:it.representedObject];
    if (u) [self createNewTabWithURL:u];
}
- (void)menuRemoveBookmark:(NSMenuItem *)it { [[SaturnBookmarks shared] removeURLString:it.representedObject]; }

// Bookmark button: outline when the page isn't saved, filled blue when it is.
- (void)updateBookmarkButton {
    NSURL *u = self.webView.URL;
    BOOL can = [SaturnBookmarks canBookmarkURL:u];
    BOOL on = can && [[SaturnBookmarks shared] containsURL:u];
    self.bookmarkButton.image = Y_symbol(on ? @"bookmark.fill" : @"bookmark", 14, NSFontWeightMedium);
    self.bookmarkButton.contentTintColor = on ? Y_blue() : (can ? Y_muted() : Y_muted2());
    self.bookmarkButton.toolTip = on ? @"Remove bookmark" : @"Bookmark this page";
    self.bookmarkButton.enabled = can;
}

- (void)bookmarkChipTapped:(NSButton *)sender {
    NSString *urlStr = sender.identifier;
    if (urlStr.length) [self navigateToString:urlStr];
}

- (void)showAuth:(id)sender {
    [[AuthWindow shared] showForWindow:self];
}
- (void)handleSessionChanged:(NSNotification *)n {
    [self updateAvatarFromProfile];
}
- (void)handleProfileUpdated:(NSNotification *)n {
    NSDictionary *profile = n.userInfo;
    NSString *url = profile[@"avatar_url"];
    if ([url isKindOfClass:[NSString class]] && url.length) {
        [self loadAvatarFromURLString:url];
    } else {
        [self showPlaceholderAvatar];
    }
}
- (void)updateAvatarFromProfile {
    if (![[SupabaseClient shared] isSignedIn]) {
        [self showPlaceholderAvatar];
        return;
    }
    __weak typeof(self) weakSelf = self;
    [[SupabaseClient shared] fetchOwnProfileWithCompletion:^(NSDictionary *profile, NSError *err){
        __strong typeof(weakSelf) s = weakSelf;
        if (!s) return;
        if (err || !profile) {
            dispatch_async(dispatch_get_main_queue(), ^{ [s showPlaceholderAvatar]; });
            return;
        }
        NSString *url = profile[@"avatar_url"];
        if ([url isKindOfClass:[NSString class]] && url.length) {
            [s loadAvatarFromURLString:url];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{ [s showPlaceholderAvatar]; });
        }
    }];
}
- (void)loadAvatarFromURLString:(NSString *)urlString {
    NSString *trimmed = [urlString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!trimmed.length) { [self showPlaceholderAvatar]; return; }
    NSURL *url = nil;
    if ([trimmed hasPrefix:@"http://"] || [trimmed hasPrefix:@"https://"]) {
        url = [NSURL URLWithString:trimmed];
    } else {
        // Assume Supabase storage path like "avatars/xxx.jpg" or just filename
        NSString *base = [SupabaseClient shared].supabaseURL;
        if (base.length) {
            // Ensure no leading slash duplicate
            NSString *path = trimmed;
            if ([path hasPrefix:@"/"]) path = [path substringFromIndex:1];
            // If already contains bucket, use as is, else prefix avatars/
            if (![path hasPrefix:@"avatars/"]) {
                // Could be full storage path or just filename — treat as avatars/
                if (![path containsString:@"/"]) path = [@"avatars/" stringByAppendingString:path];
            }
            NSString *full = [NSString stringWithFormat:@"%@/storage/v1/object/public/%@", [base stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]], path];
            url = [NSURL URLWithString:full];
        }
    }
    if (!url) { [self showPlaceholderAvatar]; return; }
    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *d, NSURLResponse *r, NSError *e){
        NSImage *img = nil;
        if (d && !e && [(NSHTTPURLResponse*)r statusCode] < 400) {
            img = [[NSImage alloc] initWithData:d];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) s = weakSelf;
            if (!s) return;
            if (img && img.size.width > 0) {
                // Hide placeholder "P"
                for (NSView *v in s.avatarButton.subviews) {
                    if (v.tag == 999) v.hidden = YES;
                }
                s.avatarImageView.image = img;
                s.avatarImageView.hidden = NO;
                s.avatarButton.layer.backgroundColor = [NSColor clearColor].CGColor;
                s.avatarButton.layer.borderWidth = 1;
            } else {
                [s showPlaceholderAvatar];
            }
        });
    }];
    [task resume];
}
- (void)showPlaceholderAvatar {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.avatarImageView.image = nil;
        self.avatarImageView.hidden = YES;
        for (NSView *v in self.avatarButton.subviews) {
            if (v.tag == 999) v.hidden = NO;
        }
        BOOL in = [[SupabaseClient shared] isSignedIn];
        self.avatarButton.layer.backgroundColor = (in ? Y_blue() : Y_soft()).CGColor;
        for (NSView *v in self.avatarButton.subviews) {
            if (v.tag == 999 && [v isKindOfClass:[NSImageView class]]) ((NSImageView *)v).contentTintColor = in ? [NSColor whiteColor] : Y_ink();
        }
    });
}
- (void)updateSearchPlaceholder {
    NSString *ph = [NSString stringWithFormat:@"Search %@ or enter website name", SaturnSettings.shared.currentEngineInfo.shortName ?: @"Google"];
    self.addressBar.placeholderString = ph;
    ((NSTextFieldCell *)self.addressBar.cell).placeholderAttributedString = [[NSAttributedString alloc] initWithString:ph attributes:@{NSForegroundColorAttributeName: Y_muted2(), NSFontAttributeName: [NSFont systemFontOfSize:14]}];
}
- (void)hannaNewChat:(id)sender {
    (void)sender;
    [self.hannaHistory removeAllObjects];
    NSScrollView *scroll = self.hannaScrollView;
    HannaChatDocView *doc = (HannaChatDocView *)scroll.documentView;
    if (![doc isKindOfClass:[HannaChatDocView class]]) return;

    [doc clearAll];
    [doc addMessageView:[self hannaEmptyStateWithWidth:scroll.contentSize.width - 12]];

    [scroll.contentView scrollToPoint:NSMakePoint(0, 0)];
    [scroll reflectScrolledClipView:scroll.contentView];

    self.hannaInputField.stringValue = @"";
    [self.hannaInputField becomeFirstResponder];
}

// Greeting + suggestion pills, shown until the first message is sent.
- (NSView *)hannaEmptyStateWithWidth:(CGFloat)width {
    NSArray<NSArray<NSString *> *> *prompts = @[
        @[@"doc.text", @"Summarize this page"],
        @[@"list.bullet", @"Key takeaways"],
        @[@"square.on.square", @"What tabs do I have open?"],
        @[@"lightbulb", @"Explain it simply"],
    ];
    CGFloat avatar = 64, pillH = 48, gap = 10;
    CGFloat topPad = 36, titleH = 34, subH = 40;
    CGFloat total = topPad + avatar + 20 + titleH + 6 + subH + 28 + prompts.count * pillH + (prompts.count - 1) * gap;

    HannaEmptyState *root = [[HannaEmptyState alloc] initWithFrame:NSMakeRect(0, 0, width, total)];
    root.identifier = @"fullWidth";
    root.autoresizingMask = NSViewWidthSizable;

    // Flipped-style top-down layout, converted to AppKit's bottom-up coordinates
    CGFloat y = total - topPad - avatar;
    NSView *av = HannaAvatar(avatar);
    av.frame = NSMakeRect((width - avatar) / 2, y, avatar, avatar);
    av.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin;
    [root addSubview:av];

    y -= 20 + titleH;
    NSTextField *title = [NSTextField labelWithString:@"Ask Zarah anything"];
    title.font = [NSFont systemFontOfSize:24 weight:NSFontWeightMedium];
    title.textColor = Y_ink();
    title.alignment = NSTextAlignmentCenter;
    title.frame = NSMakeRect(0, y, width, titleH);
    title.autoresizingMask = NSViewWidthSizable;
    [root addSubview:title];

    y -= 6 + subH;
    NSTextField *sub = [NSTextField wrappingLabelWithString:@"Zarah can see the page you're on and your open tabs."];
    sub.font = [NSFont systemFontOfSize:14 weight:NSFontWeightRegular];
    sub.textColor = Y_muted();
    sub.alignment = NSTextAlignmentCenter;
    sub.frame = NSMakeRect(24, y, width - 48, subH);
    sub.autoresizingMask = NSViewWidthSizable;
    [root addSubview:sub];

    y -= 28;
    for (NSArray<NSString *> *p in prompts) {
        y -= pillH;
        HannaPillButton *pill = [[HannaPillButton alloc] initWithFrame:NSMakeRect(0, y, width, pillH)];
        pill.title = @"";
        pill.bordered = NO;
        pill.target = self;
        pill.action = @selector(hannaActionChipTapped:);
        pill.identifier = p[1];
        pill.wantsLayer = YES;
        pill.layer.backgroundColor = [NSColor whiteColor].CGColor;
        pill.layer.borderColor = Y_hairline().CGColor;
        pill.layer.borderWidth = 1;
        pill.layer.cornerRadius = pillH / 2;
        pill.autoresizingMask = NSViewWidthSizable;

        NSImageView *icon = [[NSImageView alloc] initWithFrame:NSMakeRect(18, (pillH - 18) / 2, 18, 18)];
        icon.image = [NSImage imageWithSystemSymbolName:p[0] accessibilityDescription:nil];
        icon.contentTintColor = Y_blue();
        [pill addSubview:icon];

        NSTextField *label = [NSTextField labelWithString:p[1]];
        label.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
        label.textColor = Y_ink();
        label.frame = NSMakeRect(46, (pillH - 18) / 2, width - 64, 18);
        label.autoresizingMask = NSViewWidthSizable;
        [pill addSubview:label];

        [root addSubview:pill];
        y -= gap;
    }
    return root;
}

- (void)hannaActionChipTapped:(NSButton *)sender {
    NSString *prompt = sender.identifier ?: sender.title ?: @"";
    if (prompt.length) {
        self.hannaInputField.stringValue = prompt;
        [self hannaSend:nil];
    }
}

#pragma mark - Zarah Markdown + Typing

- (NSAttributedString *)hannaAttrForMarkdown:(NSString *)markdown {
    return AttrForMarkdownColored(markdown, 14, Y_ink(), YES);
}

- (void)showHannaTyping:(BOOL)show {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSScrollView *scroll = self.hannaScrollView;
        HannaChatDocView *doc = (HannaChatDocView *)scroll.documentView;
        if (![doc isKindOfClass:[HannaChatDocView class]]) return;

        NSView *existing = nil;
        for (NSView *v in doc.messageViews) {
            if ([v.identifier isEqualToString:@"hannaTypingRow"]) {
                existing = v;
                break;
            }
        }

        if (show) {
            if (existing) return;

            NSView *row = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 32)];

            NSView *av = HannaAvatar(24);
            av.frame = NSMakeRect(0, 4, 24, 24);
            [row addSubview:av];

            NSView *bubble = [[NSView alloc] initWithFrame:NSMakeRect(32, 0, 60, 32)];
            bubble.wantsLayer = YES;
            bubble.layer.cornerRadius = 16;
            bubble.layer.backgroundColor = Y_soft().CGColor;

            for (int i=0; i<3; i++) {
                NSView *dot = [[NSView alloc] initWithFrame:NSMakeRect(15 + i*11, 12, 7, 7)];
                dot.wantsLayer = YES;
                dot.layer.cornerRadius = 3.5;
                dot.layer.backgroundColor = Y_muted().CGColor;
                [bubble addSubview:dot];

                CABasicAnimation *op = [CABasicAnimation animationWithKeyPath:@"opacity"];
                op.fromValue = @(0.3);
                op.toValue = @(1.0);
                op.duration = 0.5;
                op.autoreverses = YES;
                op.repeatCount = HUGE_VALF;
                op.beginTime = CACurrentMediaTime() + i*0.16;
                [dot.layer addAnimation:op forKey:@"fade"];
            }

            [row addSubview:bubble];
            row.identifier = @"hannaTypingRow";
            [doc addMessageView:row];

            CGFloat maxY = MAX(0, doc.frame.size.height - scroll.contentView.bounds.size.height);
            [scroll.contentView scrollToPoint:NSMakePoint(0, maxY)];
            [scroll reflectScrolledClipView:scroll.contentView];
        } else {
            if (existing) {
                [doc removeMessageView:existing];
            }
        }
    });
}

- (void)animateHannaDots {
    // No longer used — dots are animated when typing bubble is created
}

- (void)hannaPromptTapped:(id)sender {
    self.hannaInputField.stringValue = @"organize your tabs!";
    [self hannaSend:nil];
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Tab Management

- (void)createNewTabWithURL:(NSURL *)url {
    const CGFloat W = self.contentView.bounds.size.width > 0 ? self.contentView.bounds.size.width : 1360;
    const CGFloat H = self.contentView.bounds.size.height > 0 ? self.contentView.bounds.size.height : 860;
    const CGFloat webH = H - [self currentChromeH];
    WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
    cfg.preferences.javaScriptEnabled = YES;
    cfg.preferences.javaScriptCanOpenWindowsAutomatically = NO;
    cfg.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    // Without a Version/… Safari/… token sites (Google especially) treat WKWebView as unsupported and serve their basic pages.
    cfg.applicationNameForUserAgent = @"Version/18.0 Safari/605.1.15";
    [cfg.preferences setValue:@YES forKey:@"developerExtrasEnabled"];

    // Injected script to capture selection & element info on right-click contextmenu event
    NSString *scriptSource =
    @"document.addEventListener('contextmenu', function(e) {\n"
    "  var sel = window.getSelection();\n"
    "  var text = (sel ? sel.toString() : '').trim();\n"
    "  var rect = null;\n"
    "  if (text && sel.rangeCount > 0) {\n"
    "    rect = sel.getRangeAt(0).getBoundingClientRect();\n"
    "  }\n"
    "  var link = e.target ? e.target.closest('a') : null;\n"
    "  var img = (e.target && e.target.tagName === 'IMG') ? e.target : null;\n"
    "  window.webkit.messageHandlers.contextMenuInfo.postMessage({\n"
    "    text: text,\n"
    "    x: rect ? rect.x : e.clientX,\n"
    "    y: rect ? rect.y : e.clientY,\n"
    "    w: rect ? rect.width : 1,\n"
    "    h: rect ? rect.height : 1,\n"
    "    linkUrl: link ? link.href : '',\n"
    "    imgUrl: img ? img.src : '',\n"
    "    tagName: e.target ? e.target.tagName : ''\n"
    "  });\n"
    "}, true);\n"
    "document.addEventListener('selectionchange', function() {\n"
    "  var sel = window.getSelection();\n"
    "  var text = (sel ? sel.toString() : '').trim();\n"
    "  if (text && sel.rangeCount > 0) {\n"
    "    var rect = sel.getRangeAt(0).getBoundingClientRect();\n"
    "    window.webkit.messageHandlers.contextMenuInfo.postMessage({\n"
    "      text: text, x: rect.x, y: rect.y, w: rect.width, h: rect.height\n"
    "    });\n"
    "  }\n"
    "});";

    WKUserScript *script = [[WKUserScript alloc] initWithSource:scriptSource injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO];
    [cfg.userContentController addUserScript:script];
    [cfg.userContentController addScriptMessageHandler:self name:@"contextMenuInfo"];

    // Apply Saturn Shield declarative content blocking rules
    WKContentRuleList *rules = [[SaturnShield shared] currentRuleList];
    if (rules) {
        [cfg.userContentController addContentRuleList:rules];
    } else {
        [[SaturnShield shared] setupContentRulesWithCompletion:^(WKContentRuleList *ruleList, NSError *error) {
            (void)error;
            if (ruleList) {
                [cfg.userContentController addContentRuleList:ruleList];
            }
        }];
    }

    // Injected full-power Saturn Shield ad & tracker blocker script at DocumentStart
    NSString *shieldBlockingSource = SaturnShieldGetBlockingScript();
    WKUserScript *shieldScript = [[WKUserScript alloc] initWithSource:shieldBlockingSource injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO];
    [cfg.userContentController addUserScript:shieldScript];
    [cfg.userContentController addScriptMessageHandler:self name:@"shieldBlocked"];
    [cfg.userContentController addScriptMessageHandler:self name:@"saturnHistory"];   // only honoured from saturn://history
    [cfg setURLSchemeHandler:[SaturnSchemeHandler shared] forURLScheme:@"saturn"];
    if (self.isPrivate) cfg.websiteDataStore = self.privateStore;

    EnsureWKContentViewSwizzled();
    SaturnWebView *wv = [[SaturnWebView alloc] initWithFrame:NSMakeRect(0, 0, W, webH) configuration:cfg];
    wv.saturnWindow = self;
    wv.navigationDelegate = self;
    wv.UIDelegate = self;
    wv.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    wv.allowsBackForwardNavigationGestures = YES;
    wv.underPageBackgroundColor = [NSColor whiteColor];
    wv.hidden = YES;
    [self.contentView addSubview:wv positioned:NSWindowBelow relativeTo:self.tabBar];
    [self.tabWebViews addObject:wv];

    ChromeTabView *tab = [[ChromeTabView alloc] initWithFrame:NSMakeRect(0, 6, 200, 32)];
    tab.hostWindow = self;
    tab.privateMode = self.isPrivate;
    tab.tabIndex = self.tabs.count;
    [tab updateTitle:@"New Tab" favicon:[NSImage imageWithSystemSymbolName:@"globe" accessibilityDescription:nil] active:NO];
    [self.tabs addObject:tab];
    [self.tabBar addSubview:tab];

    [self layoutTabs];
    [self switchToTabAtIndex:self.tabs.count - 1];
    [tab playAppear];
    [[SaturnSession shared] scheduleSave];

    if (url.isFileURL) [wv loadFileURL:url allowingReadAccessToURL:[url URLByDeletingLastPathComponent]];   // a page opened from Finder
    else if (url) [wv loadRequest:[NSURLRequest requestWithURL:url]];
}

#pragma mark Keyboard shortcut actions

// Shortcuts a menu item can't express cleanly: ⌃Tab / ⌃⇧Tab (next / previous tab) and ⌘= (zoom in without Shift).
- (BOOL)performKeyEquivalent:(NSEvent *)event {
    NSEventModifierFlags f = event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagControl | NSEventModifierFlagShift);
    if (event.keyCode == 48 && f == NSEventModifierFlagControl) { [self selectNextTab:nil]; return YES; }
    if (event.keyCode == 48 && f == (NSEventModifierFlagControl | NSEventModifierFlagShift)) { [self selectPreviousTab:nil]; return YES; }
    if (f == NSEventModifierFlagCommand && [event.charactersIgnoringModifiers isEqualToString:@"="]) {
        [NSApp sendAction:@selector(zoomIn:) to:nil from:self];
        return YES;
    }
    return [super performKeyEquivalent:event];
}

- (NSArray<ChromeTabView *> *)visibleTabs {
    NSMutableArray *v = [NSMutableArray array];
    for (ChromeTabView *t in self.tabs) if (!t.hidden) [v addObject:t];
    return v;
}

// ⌘1…⌘8 pick that tab, ⌘9 the last one (sender.tag carries the number).
- (void)selectTabByNumber:(id)sender {
    NSArray<ChromeTabView *> *v = [self visibleTabs];
    if (!v.count) return;
    NSInteger n = [sender tag];
    ChromeTabView *t = n >= 9 ? v.lastObject : (n >= 1 && n <= (NSInteger)v.count ? v[n - 1] : nil);
    if (t) [self switchToTabAtIndex:[self.tabs indexOfObject:t]];
}
- (void)stepTab:(NSInteger)delta {
    NSArray<ChromeTabView *> *v = [self visibleTabs];
    if (v.count < 2) return;
    NSInteger cur = [v indexOfObject:self.activeTab];
    if (cur == NSNotFound) cur = 0;
    NSInteger n = (NSInteger)v.count;
    [self switchToTabAtIndex:[self.tabs indexOfObject:v[((cur + delta) % n + n) % n]]];
}
- (void)selectNextTab:(id)sender { (void)sender; [self stepTab:1]; }
- (void)selectPreviousTab:(id)sender { (void)sender; [self stepTab:-1]; }
- (void)hardReload:(id)sender { (void)sender; [self.webView reloadFromOrigin]; }
- (void)stopLoadingPage:(id)sender { (void)sender; [self.webView stopLoading]; }
- (void)toggleHanna:(id)sender { (void)sender; [self toggleAISidebar]; }
- (void)bookmarkPage:(id)sender { [self star:sender]; }
- (void)togglePinActiveTab:(id)sender {
    (void)sender;
    ChromeTabView *t = self.activeTab;
    if (!t) return;
    t.pinned = !t.pinned;
    if (t.pinned) t.groupID = nil;
    [self relayoutAnimated];
}
- (void)printPage:(id)sender {
    (void)sender;
    NSPrintOperation *op = [self.webView printOperationWithPrintInfo:[NSPrintInfo sharedPrintInfo]];
    op.view.frame = self.webView.bounds;
    [op runOperationModalForWindow:self delegate:nil didRunSelector:nil contextInfo:nil];
}
- (void)showShortcutsPage:(id)sender {
    (void)sender;
    for (NSInteger i = 0; i < (NSInteger)self.tabWebViews.count; i++) {
        if ([self.tabWebViews[i].URL.absoluteString hasPrefix:@"saturn://shortcuts"]) { [self switchToTabAtIndex:i]; return; }
    }
    [self createNewTabWithURL:[NSURL URLWithString:@"saturn://shortcuts"]];
}

#pragma mark Session, history page, closed tabs

- (NSDictionary *)sessionState {
    NSMutableArray *tabs = [NSMutableArray array];
    NSMutableSet *usedGroups = [NSMutableSet set];
    NSInteger active = 0;
    for (NSInteger i = 0; i < (NSInteger)self.tabs.count; i++) {
        ChromeTabView *t = self.tabs[i];
        NSString *u = self.tabWebViews[i].URL.absoluteString ?: t.pendingURL.absoluteString;
        if (!u.length || [u hasPrefix:@"about:"]) continue;
        if (i == self.activeTabIndex) active = tabs.count;
        NSString *g = (t.groupID && !t.pinned) ? t.groupID : @"";
        if (g.length) [usedGroups addObject:g];
        [tabs addObject:@{@"url": u, @"title": t.title ?: @"", @"pinned": @(t.pinned), @"group": g}];
    }
    if (!tabs.count) return nil;
    NSMutableDictionary *groups = [NSMutableDictionary dictionary];
    for (NSString *g in usedGroups) if (self.tabGroups[g]) groups[g] = [self.tabGroups[g] copy];
    return @{@"tabs": tabs, @"active": @(active), @"groups": groups};
}

// The window was just created with the first saved tab already open; add the rest without loading them.
- (void)restoreSessionState:(NSDictionary *)state {
    NSArray *saved = state[@"tabs"];
    if (![saved isKindOfClass:[NSArray class]] || !saved.count) return;
    [self ensureGroupStorage];
    // Groups are installed only after every tab exists: layoutTabs drops groups that have no members yet.
    for (NSInteger i = 0; i < (NSInteger)saved.count; i++) {
        NSDictionary *d = saved[i];
        ChromeTabView *t;
        if (i == 0) {
            t = self.tabs.firstObject;
        } else {
            [self createNewTabWithURL:nil];
            t = self.tabs.lastObject;
            NSURL *u = [NSURL URLWithString:d[@"url"]];
            if (u) t.pendingURL = u;
        }
        if ([d[@"title"] length]) [t updateTitle:d[@"title"] favicon:nil active:NO];
        t.pinned = [d[@"pinned"] boolValue];
    }
    NSDictionary *groups = state[@"groups"];
    if ([groups isKindOfClass:[NSDictionary class]]) {
        for (NSString *gid in groups) if ([groups[gid] isKindOfClass:[NSDictionary class]]) self.tabGroups[gid] = [groups[gid] mutableCopy];
    }
    for (NSInteger i = 0; i < (NSInteger)saved.count && i < (NSInteger)self.tabs.count; i++) {
        NSString *g = saved[i][@"group"];
        ChromeTabView *t = self.tabs[i];
        t.groupID = (g.length && self.tabGroups[g] && !t.pinned) ? g : nil;
    }
    [self layoutTabs];
    NSInteger active = MAX(0, MIN((NSInteger)saved.count - 1, [state[@"active"] integerValue]));
    [self switchToTabAtIndex:active];
}

- (void)showHistoryPage:(id)sender {
    (void)sender;
    for (NSInteger i = 0; i < (NSInteger)self.tabWebViews.count; i++) {
        if ([self.tabWebViews[i].URL.absoluteString hasPrefix:@"saturn://history"]) {
            [self switchToTabAtIndex:i];
            [self.tabWebViews[i] reload];   // pick up visits made since it was opened
            return;
        }
    }
    [self createNewTabWithURL:[NSURL URLWithString:@"saturn://history"]];
}

- (void)reopenClosedTab:(id)sender {
    (void)sender;
    NSDictionary *d = self.closedTabs.lastObject;
    NSURL *u = d ? [NSURL URLWithString:d[@"url"]] : nil;
    if (!u) { NSBeep(); return; }
    [self.closedTabs removeLastObject];
    [self createNewTabWithURL:u];
    if ([d[@"pinned"] boolValue]) {
        self.tabs.lastObject.pinned = YES;
        [self relayoutAnimated];
    }
}

- (void)handleHistoryMessage:(WKScriptMessage *)m {
    // Only the built-in history page may change history; ignore the same message from any website.
    NSURL *origin = m.frameInfo.request.URL;
    if (!m.frameInfo.isMainFrame || ![origin.scheme isEqualToString:@"saturn"] || ![origin.host isEqualToString:@"history"]) return;
    if (![m.body isKindOfClass:[NSDictionary class]]) return;
    NSDictionary *b = m.body;
    NSString *action = b[@"action"];
    if ([action isEqualToString:@"delete"] && [b[@"u"] isKindOfClass:[NSString class]]) {
        [[SaturnHistory shared] removeURLString:b[@"u"] visitedAt:[b[@"d"] doubleValue]];
    } else if ([action isEqualToString:@"clear"]) {
        double since = [b[@"since"] doubleValue];
        [[SaturnHistory shared] clearSince:since > 0 ? [NSDate dateWithTimeIntervalSince1970:since] : nil];
    }
}

#pragma mark Permission prompts + JavaScript dialogs

// Prompts are shown one at a time under the address bar; each carries a completion that gets the answer.
- (void)enqueuePromptSymbol:(NSString *)symbol title:(NSString *)title detail:(NSString *)detail
                      allow:(NSString *)allow deny:(NSString *)deny remember:(BOOL)remember
                 completion:(void (^)(BOOL allow, BOOL remember))completion {
    if (!self.promptQueue) self.promptQueue = [NSMutableArray array];
    [self.promptQueue addObject:@{@"symbol": symbol, @"title": title, @"detail": detail ?: @"", @"allow": allow, @"deny": deny,
                                  @"remember": @(remember), @"completion": [completion copy]}];
    [self showNextPrompt];
}

- (void)showNextPrompt {
    if (self.promptCard || !self.promptQueue.count) return;
    NSDictionary *p = self.promptQueue.firstObject;
    [self.promptQueue removeObjectAtIndex:0];
    SaturnPromptCard *card = [[SaturnPromptCard alloc] initWithSymbol:p[@"symbol"] title:p[@"title"] detail:p[@"detail"]
                                                           allowTitle:p[@"allow"] denyTitle:p[@"deny"] showRemember:[p[@"remember"] boolValue]];
    void (^completion)(BOOL, BOOL) = p[@"completion"];
    __weak SaturnWindow *weak = self;
    card.onDecision = ^(BOOL allow, BOOL remember) {
        SaturnWindow *strong = weak;
        SaturnPromptCard *c = strong.promptCard;
        strong.promptCard = nil;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) { ctx.duration = 0.15; c.animator.alphaValue = 0; }
                            completionHandler:^{ [c removeFromSuperview]; [strong showNextPrompt]; }];
        completion(allow, remember);
    };
    self.promptCard = card;
    card.alphaValue = 0;
    [self.contentView addSubview:card positioned:NSWindowAbove relativeTo:nil];
    [self layoutPrompt];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) { ctx.duration = 0.25; card.animator.alphaValue = 1; }];
    [self makeKeyAndOrderFront:nil];
}

- (void)layoutPrompt {
    if (!self.promptCard) return;
    NSRect box = [self.contentView convertRect:self.omniboxContainer.bounds fromView:self.omniboxContainer];
    NSSize sz = self.promptCard.frame.size;
    self.promptCard.frame = NSMakeRect(MAX(12, box.origin.x), box.origin.y - 8 - sz.height, sz.width, sz.height);
}

- (void)webView:(WKWebView *)webView requestMediaCapturePermissionForOrigin:(WKSecurityOrigin *)origin initiatedByFrame:(WKFrameInfo *)frame type:(WKMediaCaptureType)type decisionHandler:(void (^)(WKPermissionDecision))decisionHandler API_AVAILABLE(macos(12.0)) {
    (void)webView; (void)frame;
    NSArray<NSString *> *kinds = type == WKMediaCaptureTypeCamera ? @[@"camera"] : type == WKMediaCaptureTypeMicrophone ? @[@"microphone"] : @[@"camera", @"microphone"];
    NSString *key = [SaturnPermissions originKeyForProtocol:origin.protocol host:origin.host port:origin.port];
    BOOL priv = self.isPrivate, allAllowed = YES;
    for (NSString *k in kinds) {
        NSString *d = [SaturnPermissions decisionForOrigin:key kind:k privateMode:priv];
        if ([d isEqualToString:@"block"]) { decisionHandler(WKPermissionDecisionDeny); return; }
        if (![d isEqualToString:@"allow"]) allAllowed = NO;
    }
    if (allAllowed) { decisionHandler(WKPermissionDecisionGrant); return; }

    NSString *what = type == WKMediaCaptureTypeCamera ? @"camera" : type == WKMediaCaptureTypeMicrophone ? @"microphone" : @"camera and microphone";
    NSString *symbol = type == WKMediaCaptureTypeMicrophone ? @"mic.fill" : @"video.fill";
    NSString *host = origin.host.length ? origin.host : @"This site";
    [self enqueuePromptSymbol:symbol title:[NSString stringWithFormat:@"%@ wants to use your %@", host, what]
                       detail:@"It will only be able to use it while the page is open."
                        allow:@"Allow" deny:@"Block" remember:YES
                   completion:^(BOOL allow, BOOL remember) {
        if (remember) [SaturnPermissions setDecision:allow ? @"allow" : @"block" forOrigin:key kinds:kinds privateMode:priv];
        decisionHandler(allow ? WKPermissionDecisionGrant : WKPermissionDecisionDeny);
    }];
}

// Links that open another app (mailto:, tel:, zoommtg: …): only after a click, and only after asking.
- (void)confirmOpenExternalURL:(NSURL *)url fromHost:(NSString *)host {
    NSURL *appURL = [[NSWorkspace sharedWorkspace] URLForApplicationToOpenURL:url];
    if (!appURL) { NSBeep(); return; }
    NSString *appName = [[NSFileManager defaultManager] displayNameAtPath:appURL.path];
    appName = [appName hasSuffix:@".app"] ? [appName substringToIndex:appName.length - 4] : appName;
    [self enqueuePromptSymbol:@"arrow.up.forward.app" title:[NSString stringWithFormat:@"%@ wants to open %@", host.length ? host : @"This page", appName]
                       detail:url.absoluteString.length > 80 ? [[url.absoluteString substringToIndex:77] stringByAppendingString:@"…"] : url.absoluteString
                        allow:@"Open" deny:@"Cancel" remember:NO
                   completion:^(BOOL allow, BOOL remember) {
        (void)remember;
        if (allow) [[NSWorkspace sharedWorkspace] openURL:url];
    }];
}

- (NSAlert *)jsDialogForFrame:(WKFrameInfo *)frame message:(NSString *)message {
    NSAlert *a = [[NSAlert alloc] init];
    NSString *host = frame.request.URL.host;
    a.messageText = host.length ? [NSString stringWithFormat:@"%@ says", host] : @"This page says";
    a.informativeText = message ?: @"";
    return a;
}

- (void)webView:(WKWebView *)webView runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt defaultText:(NSString *)defaultText initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(NSString *))completionHandler {
    (void)webView;
    NSAlert *a = [self jsDialogForFrame:frame message:prompt];
    [a addButtonWithTitle:@"OK"];
    [a addButtonWithTitle:@"Cancel"];
    NSTextField *f = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 280, 24)];
    f.stringValue = defaultText ?: @"";
    a.accessoryView = f;
    a.window.initialFirstResponder = f;
    completionHandler([a runModal] == NSAlertFirstButtonReturn ? f.stringValue : nil);
}

#pragma mark Address bar suggestions

- (void)updateSuggestions {
    NSString *q = [self.addressBar.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!q.length || !self.addressBar.currentEditor) { [self hideSuggestions]; return; }

    BOOL looksURL = [q containsString:@"://"] || ([q containsString:@"."] && ![q containsString:@" "]);
    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    [items addObject:@{@"kind": looksURL ? @"url" : @"search", @"title": q, @"url": q}];
    [items addObjectsFromArray:[[SaturnHistory shared] suggestionsForQuery:q limit:6]];

    if (!self.suggestView) {
        self.suggestView = [[SaturnSuggestView alloc] initWithFrame:NSMakeRect(0, 0, 400, 100)];
        __weak SaturnWindow *weak = self;
        self.suggestView.onPick = ^(NSDictionary *item) { [weak pickSuggestion:item]; };
        [self.contentView addSubview:self.suggestView positioned:NSWindowAbove relativeTo:nil];
    }
    NSRect box = [self.contentView convertRect:self.omniboxContainer.bounds fromView:self.omniboxContainer];
    [self.suggestView setItems:items engineName:SaturnSettings.shared.currentEngineInfo.name width:box.size.width];
    self.suggestView.hidden = NO;
    [self layoutSuggestions];
}

- (void)layoutSuggestions {
    if (!self.suggestView || self.suggestView.hidden) return;
    NSRect box = [self.contentView convertRect:self.omniboxContainer.bounds fromView:self.omniboxContainer];
    CGFloat h = [SaturnSuggestView heightForCount:self.suggestView.items.count];
    self.suggestView.frame = NSMakeRect(box.origin.x, box.origin.y - 8 - h, box.size.width, h);
}

- (void)hideSuggestions {
    if (self.suggestView) self.suggestView.hidden = YES;
}

- (BOOL)suggestionsVisible { return self.suggestView && !self.suggestView.hidden; }

- (void)pickSuggestion:(NSDictionary *)item {
    NSString *target = item[@"url"];
    [self hideSuggestions];
    [self makeFirstResponder:nil];
    if (target.length) [self navigateToString:target];
}

#pragma mark Zarah Act mode (browser control)

- (void)applyHannaMode {
    BOOL act = self.hannaActMode;
    NSArray<NSButton *> *btns = @[self.chatModeButton, self.actModeButton];
    for (NSInteger i = 0; i < 2; i++) {
        BOOL on = (i == 1) == act;
        NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
        ps.alignment = NSTextAlignmentCenter;
        btns[i].attributedTitle = [[NSAttributedString alloc] initWithString:btns[i].title attributes:@{
            NSForegroundColorAttributeName: on ? Y_ink() : Y_muted(),
            NSFontAttributeName: [NSFont systemFontOfSize:13 weight:on ? NSFontWeightBold : NSFontWeightMedium],
            NSParagraphStyleAttributeName: ps}];
        btns[i].layer.backgroundColor = (on ? [NSColor whiteColor] : [NSColor clearColor]).CGColor;
        btns[i].layer.borderWidth = on ? 1 : 0;
        btns[i].layer.borderColor = Y_hairline().CGColor;
    }
    self.modeHint.stringValue = act ? @"Zarah can click, type and open pages. Stop her any time." : @"Ask Zarah about this page or your tabs.";
    NSString *ph = act ? @"Tell Zarah what to do" : @"Ask Zarah anything";
    self.hannaInputField.placeholderAttributedString = [[NSAttributedString alloc] initWithString:ph attributes:@{NSForegroundColorAttributeName: Y_muted2(), NSFontAttributeName: [NSFont systemFontOfSize:14]}];
}

- (void)setHannaMode:(NSButton *)sender {
    if (self.hannaAgent.running) { NSBeep(); return; }
    self.hannaActMode = sender.tag == 1;
    [self applyHannaMode];
}

- (void)hannaSendAgentTask:(NSString *)text {
    if (self.hannaAgent.running) { NSBeep(); return; }
    [self.hannaHistory addObject:@{@"role": @"user", @"content": text}];
    [self appendHannaMessage:text from:@"user"];
    self.hannaInputField.stringValue = @"";
    if (!self.aiSidebarVisible) [self toggleAISidebar];
    if (!self.hannaAgent) self.hannaAgent = [[HannaAgent alloc] initWithWindow:self];
    [self.hannaAgent runTask:text];
}

- (void)stopHannaAgent { [self.hannaAgent stop]; }

- (void)layoutAgentOverlay {
    if (!self.agentGlow) return;
    CGFloat W = self.contentView.bounds.size.width, H = self.contentView.bounds.size.height;
    CGFloat webH = H - [self currentChromeH];
    self.agentGlow.frame = NSMakeRect(0, 0, W, webH);
    CGFloat sidebar = self.aiSidebarVisible ? 392 : 0;
    CGFloat bw = self.agentBar.frame.size.width;
    self.agentBar.frame = NSMakeRect(MAX(12, (W - sidebar - bw) / 2), 24, bw, 48);
}

- (void)showAgentOverlay {
    if (!self.agentGlow) {
        YPassThroughView *glow = [[YPassThroughView alloc] initWithFrame:NSZeroRect];
        glow.wantsLayer = YES;
        glow.layer.borderWidth = 3;
        glow.layer.borderColor = [Y_blue() colorWithAlphaComponent:0.7].CGColor;
        self.agentGlow = glow;

        NSView *bar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 48)];
        bar.wantsLayer = YES;
        bar.layer.cornerRadius = 24;
        bar.layer.backgroundColor = Y_ink().CGColor;
        for (int i = 0; i < 3; i++) {
            NSView *dot = [[NSView alloc] initWithFrame:NSMakeRect(20 + i * 12, 20, 8, 8)];
            dot.wantsLayer = YES;
            dot.layer.cornerRadius = 4;
            dot.layer.backgroundColor = [NSColor whiteColor].CGColor;
            CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"opacity"];
            a.fromValue = @0.25; a.toValue = @1; a.duration = 0.6; a.autoreverses = YES; a.repeatCount = HUGE_VALF;
            a.beginTime = CACurrentMediaTime() + i * 0.18;
            [dot.layer addAnimation:a forKey:@"pulse"];
            [bar addSubview:dot];
        }
        NSTextField *label = [NSTextField labelWithString:@"Zarah is working"];
        label.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
        label.textColor = [NSColor whiteColor];
        label.frame = NSMakeRect(66, 14, 150, 20);
        [bar addSubview:label];
        YSheetButton *stop = [[YSheetButton alloc] initWithTitle:@"Stop" primary:NO frame:NSMakeRect(300 - 8 - 76, 8, 76, 32)];
        stop.target = self;
        stop.action = @selector(stopHannaAgent);
        stop.keyEquivalent = @"\033";
        [bar addSubview:stop];
        self.agentBar = bar;
    }
    [self.contentView addSubview:self.agentGlow positioned:NSWindowAbove relativeTo:nil];
    [self.contentView addSubview:self.agentBar positioned:NSWindowAbove relativeTo:nil];
    self.agentGlow.hidden = NO;
    self.agentBar.hidden = NO;
    [self layoutAgentOverlay];
    CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"opacity"];
    pulse.fromValue = @0.45; pulse.toValue = @1; pulse.duration = 1.1; pulse.autoreverses = YES; pulse.repeatCount = HUGE_VALF;
    pulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.agentGlow.layer addAnimation:pulse forKey:@"pulse"];
}

- (void)agentStarted {
    self.hannaSendButton.enabled = NO;
    self.hannaInputField.enabled = NO;
    [self showAgentOverlay];
}

// One line in the chat for each thing Zarah did.
- (void)agentStep:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSScrollView *scroll = self.hannaScrollView;
        HannaChatDocView *doc = (HannaChatDocView *)scroll.documentView;
        if (![doc isKindOfClass:[HannaChatDocView class]]) return;
        for (NSView *v in [doc.messageViews copy]) if ([v isKindOfClass:[HannaEmptyState class]]) [doc removeMessageView:v];
        NSView *row = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 22)];
        row.identifier = @"fullWidth";
        row.autoresizingMask = NSViewWidthSizable;
        NSImageView *icon = [[NSImageView alloc] initWithFrame:NSMakeRect(8, 4, 14, 14)];
        icon.image = Y_symbol(@"checkmark.circle.fill", 12, NSFontWeightMedium);
        icon.contentTintColor = Y_blue();
        [row addSubview:icon];
        NSTextField *l = [NSTextField labelWithString:text];
        l.font = [NSFont systemFontOfSize:12.5];
        l.textColor = Y_muted();
        l.lineBreakMode = NSLineBreakByTruncatingTail;
        l.frame = NSMakeRect(30, 3, 280, 16);
        l.autoresizingMask = NSViewWidthSizable;
        [row addSubview:l];
        [doc addMessageView:row];
        CGFloat maxY = MAX(0, doc.frame.size.height - scroll.contentView.bounds.size.height);
        [scroll.contentView scrollToPoint:NSMakePoint(0, maxY)];
        [scroll reflectScrolledClipView:scroll.contentView];
    });
}

- (void)agentFinished:(NSString *)message isError:(BOOL)isError {
    [self.agentGlow.layer removeAnimationForKey:@"pulse"];
    self.agentGlow.hidden = YES;
    self.agentBar.hidden = YES;
    self.hannaSendButton.enabled = YES;
    self.hannaInputField.enabled = YES;
    [self makeFirstResponder:self.hannaInputField];
    if (!isError && message.length) [self.hannaHistory addObject:@{@"role": @"assistant", @"content": message}];
    [self appendHannaMessage:isError ? [@"⚠️ " stringByAppendingString:message] : message from:@"hanna"];
}

- (void)agentConfirmWithTitle:(NSString *)title detail:(NSString *)detail completion:(void (^)(BOOL))completion {
    [self enqueuePromptSymbol:@"hand.raised.fill" title:title detail:detail allow:@"Allow" deny:@"Stop" remember:NO
                   completion:^(BOOL allow, BOOL remember) { (void)remember; completion(allow); }];
}

#pragma mark Default browser

- (void)offerDefaultBrowser {
    if (self.promptCard || self.attachedSheet) return;
    [self enqueuePromptSymbol:@"globe" title:@"Make Saturn your default browser?"
                       detail:@"Links you click in other apps will open here."
                        allow:@"Make default" deny:@"Not now" remember:NO
                   completion:^(BOOL allow, BOOL remember) {
        (void)remember;
        if (allow) [SaturnDefaultBrowser makeDefaultWithCompletion:nil];   // macOS then asks you to confirm
    }];
}

#pragma mark Feedback + crash reports

- (void)showFeedbackSheet:(id)sender {
    (void)sender;
    if (self.attachedSheet) return;
    [YFeedbackSheet presentOnWindow:self crashSummary:nil crashDetails:nil
        submit:^(NSDictionary *v, void (^done)(NSError *)) {
            [[SaturnReporter shared] submitFeedbackKind:v[@"kind"] message:v[@"text"] email:v[@"email"] includeDiagnostics:[v[@"diag"] boolValue] completion:done];
        } dismiss:nil];
}

// Called shortly after launch: if macOS logged a Saturn crash since last time, offer to send it.
- (void)presentPendingCrashReport {
    if (self.attachedSheet || self.isPrivate) return;
    NSDictionary *crash = [[SaturnReporter shared] pendingCrashReport];
    if (!crash) return;
    [YFeedbackSheet presentOnWindow:self crashSummary:crash[@"summary"] crashDetails:crash[@"details"]
        submit:^(NSDictionary *v, void (^done)(NSError *)) {
            [[SaturnReporter shared] submitCrash:crash note:v[@"text"] includeDetails:[v[@"diag"] boolValue] completion:done];
        }
        dismiss:^{ [[SaturnReporter shared] markCrashHandled:crash]; }];   // asked once, whatever the answer
}

#pragma mark Updates

- (void)updateUpdateButton {
    SaturnUpdater *u = [SaturnUpdater shared];
    BOOL show = u.updateIsWaiting;
    self.updateButton.hidden = !show;
    if (!show) return;
    NSString *label = u.state == SaturnUpdateStateDownloading ? @"Updating…" : u.state == SaturnUpdateStateInstalling ? @"Restarting…" : u.state == SaturnUpdateStateFailed ? @"Retry update" : @"Update";
    NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
    ps.alignment = NSTextAlignmentCenter;
    self.updateButton.attributedTitle = [[NSAttributedString alloc] initWithString:label attributes:@{
        NSForegroundColorAttributeName: [NSColor whiteColor], NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightBold], NSParagraphStyleAttributeName: ps}];
    self.updateButton.toolTip = [NSString stringWithFormat:@"Saturn %@ is available", u.availableVersion];
}

- (void)updateStateChanged:(NSNotification *)n { (void)n; [self updateUpdateButton]; }

- (void)showUpdatePopover:(id)sender {
    (void)sender;
    if (self.updatePopover.shown) { [self.updatePopover close]; return; }
    NSView *anchor = self.updateButton.hidden ? self.avatarButton : self.updateButton;   // up-to-date message hangs off the account button
    NSPopover *pop = [[NSPopover alloc] init];
    pop.behavior = NSPopoverBehaviorTransient;
    pop.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    pop.contentViewController = [[YUpdateVC alloc] init];
    self.updatePopover = pop;
    [pop showRelativeToRect:anchor.bounds ofView:anchor preferredEdge:NSRectEdgeMinY];
}

#pragma mark Downloads + find in page

- (void)updateDownloadsButton {
    SaturnDownloads *d = [SaturnDownloads shared];
    self.downloadsButton.hidden = d.items.count == 0;
    BOOL active = d.activeCount > 0;
    self.downloadsButton.contentTintColor = active ? Y_blue() : Y_ink();
    CAShapeLayer *ring = self.downloadsRing;
    ring.hidden = !active;
    double f = d.overallFraction;
    if (active && f < 0) {
        ring.strokeEnd = 0.3;
        if (![ring animationForKey:@"spin"]) {
            CABasicAnimation *spin = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
            spin.fromValue = @(-M_PI_2); spin.toValue = @(-M_PI_2 - 2 * M_PI);
            spin.duration = 1; spin.repeatCount = HUGE_VALF;
            [ring addAnimation:spin forKey:@"spin"];
        }
    } else {
        [ring removeAnimationForKey:@"spin"];
        ring.strokeEnd = MAX(0.04, f);
    }
}
- (void)downloadsChanged:(NSNotification *)n { (void)n; [self updateDownloadsButton]; }

- (void)showDownloads:(id)sender {
    (void)sender;
    if (self.downloadsPopover.shown) { [self.downloadsPopover close]; return; }
    self.downloadsButton.hidden = NO;
    NSPopover *pop = [[NSPopover alloc] init];
    pop.behavior = NSPopoverBehaviorTransient;
    pop.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    pop.contentViewController = [[YDownloadsVC alloc] init];
    self.downloadsPopover = pop;
    [pop showRelativeToRect:self.downloadsButton.bounds ofView:self.downloadsButton preferredEdge:NSRectEdgeMinY];
}

- (void)beginDownload:(WKDownload *)download {
    [[SaturnDownloads shared] adopt:download];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateDownloadsButton];
        if (!self.downloadsPopover.shown) [self showDownloads:nil];
    });
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    (void)webView;
    if (navigationAction.shouldPerformDownload) { decisionHandler(WKNavigationActionPolicyDownload); return; }
    NSURL *u = navigationAction.request.URL;
    NSString *scheme = u.scheme.lowercaseString;
    NSSet *handledHere = [NSSet setWithArray:@[@"http", @"https", @"about", @"saturn", @"data", @"blob", @"file", @"javascript", @"ws", @"wss"]];
    if (scheme.length && ![handledHere containsObject:scheme]) {
        decisionHandler(WKNavigationActionPolicyCancel);
        if (navigationAction.navigationType == WKNavigationTypeLinkActivated) {   // never from background redirects
            [self confirmOpenExternalURL:u fromHost:navigationAction.sourceFrame.request.URL.host];
        }
        return;
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}
- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    (void)webView;
    BOOL attachment = NO;
    if ([navigationResponse.response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSString *cd = [(NSHTTPURLResponse *)navigationResponse.response valueForHTTPHeaderField:@"Content-Disposition"];
        attachment = [cd.lowercaseString hasPrefix:@"attachment"];
    }
    BOOL download = navigationResponse.isForMainFrame && (attachment || !navigationResponse.canShowMIMEType);
    decisionHandler(download ? WKNavigationResponsePolicyDownload : WKNavigationResponsePolicyAllow);
}
- (void)webView:(WKWebView *)webView navigationAction:(WKNavigationAction *)navigationAction didBecomeDownload:(WKDownload *)download {
    (void)webView; (void)navigationAction;
    [self beginDownload:download];
}
- (void)webView:(WKWebView *)webView navigationResponse:(WKNavigationResponse *)navigationResponse didBecomeDownload:(WKDownload *)download {
    (void)webView; (void)navigationResponse;
    [self beginDownload:download];
}

// ---- Find in page ----

- (void)layoutFindBar {
    if (!self.findBar) return;
    CGFloat W = self.contentView.bounds.size.width, H = self.contentView.bounds.size.height;
    CGFloat barW = 420, barH = 44;
    CGFloat sidebar = self.aiSidebarVisible ? 392 : 0;
    CGFloat x = MAX(12, (W - sidebar - barW) / 2);
    self.findBar.frame = NSMakeRect(x, H - [self currentChromeH] - 12 - barH, barW, barH);
}

- (void)showFindBar:(id)sender {
    (void)sender;
    if (!self.findBar) {
        self.findBar = [[SaturnFindBar alloc] initWithFrame:NSMakeRect(0, 0, 420, 44)];
        self.findBar.host = self;
        self.findBar.hidden = YES;
        [self.contentView addSubview:self.findBar positioned:NSWindowAbove relativeTo:nil];
    }
    [self layoutFindBar];
    if (self.findBar.hidden) {
        self.findBar.alphaValue = 0;
        self.findBar.hidden = NO;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) { ctx.duration = 0.15; self.findBar.animator.alphaValue = 1; }];
    }
    [self makeFirstResponder:self.findBar.field];
    [self.findBar.field selectText:nil];
    if (self.findBar.field.stringValue.length) [self runFindFresh:YES backwards:NO];
}

- (void)hideFindBar {
    if (!self.findBar || self.findBar.hidden) return;
    self.findBar.hidden = YES;
    [self.webView evaluateJavaScript:@"window.getSelection().removeAllRanges()" completionHandler:nil];
    self.findIndex = 0; self.findCount = 0;
    [self.findBar setStatus:@""];
    if (self.webView) [self makeFirstResponder:self.webView];
}

- (void)findQueryChanged { [self runFindFresh:YES backwards:NO]; }

- (void)findNextInPage:(id)sender {
    (void)sender;
    if (!self.findBar || self.findBar.hidden) { [self showFindBar:nil]; return; }
    [self runFindFresh:NO backwards:NO];
}
- (void)findPreviousInPage:(id)sender {
    (void)sender;
    if (!self.findBar || self.findBar.hidden) { [self showFindBar:nil]; return; }
    [self runFindFresh:NO backwards:YES];
}

- (void)updateFindStatus {
    [self.findBar setStatus:self.findCount > 0 ? [NSString stringWithFormat:@"%ld of %ld", (long)self.findIndex, (long)self.findCount] : @"1 match"];
}

- (void)countMatchesFor:(NSString *)q completion:(void (^)(NSInteger))done {
    NSData *json = [NSJSONSerialization dataWithJSONObject:@[q] options:0 error:nil];
    NSString *arg = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    NSString *js = [NSString stringWithFormat:@"(function(a){var q=a[0].toLowerCase();var t=(document.body?document.body.innerText:'').toLowerCase();var c=0,i=0;while(q&&(i=t.indexOf(q,i))!==-1){c++;i+=q.length;}return c;})(%@)", arg];
    [self.webView evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
        (void)error;
        done([result isKindOfClass:[NSNumber class]] ? [result integerValue] : 0);
    }];
}

- (void)runFindFresh:(BOOL)fresh backwards:(BOOL)backwards {
    WKWebView *wv = self.webView;
    NSString *q = self.findBar.field.stringValue;
    if (!wv) return;
    if (!q.length) {
        [wv evaluateJavaScript:@"window.getSelection().removeAllRanges()" completionHandler:nil];
        self.findIndex = 0; self.findCount = 0;
        [self.findBar setStatus:@""];
        return;
    }
    void (^doFind)(void) = ^{
        WKFindConfiguration *cfg = [[WKFindConfiguration alloc] init];
        cfg.backwards = backwards;
        cfg.wraps = YES;
        cfg.caseSensitive = NO;
        [wv findString:q withConfiguration:cfg completionHandler:^(WKFindResult *result) {
            if (![self.findBar.field.stringValue isEqualToString:q]) return;   // query changed meanwhile
            if (!result.matchFound) {
                self.findIndex = 0; self.findCount = 0;
                [self.findBar setStatus:@"No results"];
                return;
            }
            if (fresh || self.findCount == 0) {
                self.findIndex = 1;
                [self countMatchesFor:q completion:^(NSInteger n) {
                    self.findCount = MAX(1, n);
                    [self updateFindStatus];
                }];
            } else {
                self.findIndex += backwards ? -1 : 1;
                if (self.findIndex < 1) self.findIndex = self.findCount;
                if (self.findIndex > self.findCount) self.findIndex = 1;
                [self updateFindStatus];
            }
        }];
    };
    if (fresh) [wv evaluateJavaScript:@"window.getSelection().removeAllRanges()" completionHandler:^(id r, NSError *e) { (void)r; (void)e; doFind(); }];
    else doFind();
}

#pragma mark Pinned tabs + groups

- (void)ensureGroupStorage {
    if (!self.tabGroups) self.tabGroups = [NSMutableDictionary dictionary];
    if (!self.groupChips) self.groupChips = [NSMutableDictionary dictionary];
    if (!self.groupBars) self.groupBars = [NSMutableDictionary dictionary];
}

- (BOOL)isGroupCollapsed:(NSString *)gid { return gid && [self.tabGroups[gid][@"collapsed"] boolValue]; }

- (NSArray<ChromeTabView *> *)membersOfGroup:(NSString *)gid {
    NSMutableArray *m = [NSMutableArray array];
    for (ChromeTabView *t in self.tabs) if ([t.groupID isEqualToString:gid]) [m addObject:t];
    return m;
}

- (NSString *)chipTextForGroup:(NSString *)gid {
    NSString *name = self.tabGroups[gid][@"name"] ?: @"";
    if ([self isGroupCollapsed:gid]) return [NSString stringWithFormat:@"%@ · %lu", name.length ? name : @"Group", (unsigned long)[self membersOfGroup:gid].count];
    return name;
}

- (CGFloat)chipWidthForGroup:(NSString *)gid {
    NSString *text = [self chipTextForGroup:gid];
    if (!text.length) return 28;
    CGFloat w = ceil([text sizeWithAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightBold]}].width);
    return MIN(170, MAX(36, w + 36));
}

// Pinned tabs first, then groups kept contiguous (a group sits where its first tab is).
- (void)normalizeTabOrder {
    NSMutableArray<ChromeTabView *> *ordered = [NSMutableArray array];
    for (ChromeTabView *t in self.tabs) if (t.pinned) [ordered addObject:t];
    NSMutableSet *done = [NSMutableSet set];
    for (ChromeTabView *t in self.tabs) {
        if (t.pinned) continue;
        if (!t.groupID) { [ordered addObject:t]; continue; }
        if ([done containsObject:t.groupID]) continue;
        [done addObject:t.groupID];
        for (ChromeTabView *u in self.tabs) if (!u.pinned && [u.groupID isEqualToString:t.groupID]) [ordered addObject:u];
    }
    if (![ordered isEqualToArray:self.tabs]) [self applyTabOrder:ordered];
}

- (void)applyTabOrder:(NSArray<ChromeTabView *> *)ordered {
    ChromeTabView *active = self.activeTab;
    NSMutableArray<WKWebView *> *views = [NSMutableArray array];
    for (ChromeTabView *t in ordered) {
        NSInteger old = [self.tabs indexOfObject:t];
        [views addObject:self.tabWebViews[old]];
    }
    self.tabs = [ordered mutableCopy];
    self.tabWebViews = views;
    self.activeTabIndex = active ? (NSInteger)[ordered indexOfObject:active] : -1;
    for (NSInteger i = 0; i < (NSInteger)self.tabs.count; i++) self.tabs[i].tabIndex = i;
}

- (void)layoutTabs {
    [self ensureGroupStorage];
    [self normalizeTabOrder];

    // While a tab is dragged, lay the others out around a reserved slot (live "switch")
    NSArray<ChromeTabView *> *order = self.dragPreviewOrder ?: self.tabs;
    ChromeTabView *dragging = self.dragTab;
    BOOL previewing = self.dragPreviewOrder != nil;
    NSString *(^groupOf)(ChromeTabView *) = ^NSString *(ChromeTabView *t) {
        return (previewing && t == dragging) ? self.dragPreviewGroup : t.groupID;
    };

    // Drop groups that no longer have members
    NSMutableSet *live = [NSMutableSet set];
    for (ChromeTabView *t in self.tabs) if (t.groupID) [live addObject:t.groupID];
    for (NSString *g in [self.tabGroups.allKeys copy]) {
        if ([live containsObject:g]) continue;
        [self.tabGroups removeObjectForKey:g];
        [self.groupChips[g] removeFromSuperview]; [self.groupChips removeObjectForKey:g];
        [self.groupBars[g] removeFromSuperview]; [self.groupBars removeObjectForKey:g];
    }

    const CGFloat tabX = 116, gap = 6, pinW = 40, pinGap = 4, chipGap = 6;
    CGFloat fixed = 0;
    NSInteger visibleNormal = 0;
    NSMutableSet *seen = [NSMutableSet set];
    for (ChromeTabView *t in order) {
        if (t.pinned) { fixed += pinW + pinGap; continue; }
        NSString *gid = groupOf(t);
        if (gid && ![seen containsObject:gid]) { [seen addObject:gid]; fixed += [self chipWidthForGroup:gid] + chipGap; }
        if (![self isGroupCollapsed:gid]) visibleNormal++;
    }
    CGFloat available = self.contentView.bounds.size.width - tabX - 56 - fixed;
    if (self.contentView.bounds.size.width <= 0) available = 800;
    CGFloat tabW = 200;
    if (visibleNormal > 0) {
        CGFloat need = visibleNormal * tabW + (visibleNormal - 1) * gap;
        if (need > available) tabW = MAX(90, (available - (visibleNormal - 1) * gap) / visibleNormal);
    }

    BOOL anim = self.animateTabLayout;
    void (^place)(NSView *, NSRect) = ^(NSView *v, NSRect r) {
        if (anim) v.animator.frame = r; else v.frame = r;
    };
    NSMutableDictionary<NSString *, NSNumber *> *gStart = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSNumber *> *gEnd = [NSMutableDictionary dictionary];
    NSMutableSet *chipped = [NSMutableSet set];

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
        ctx.duration = anim ? 0.22 : 0;
        ctx.allowsImplicitAnimation = anim;
        CGFloat cx = tabX;
        for (NSInteger i = 0; i < (NSInteger)order.count; i++) {
            ChromeTabView *t = order[i];
            if (!previewing) t.tabIndex = i;
            BOOL isDragged = previewing && t == dragging;
            if (t.pinned) {
                t.hidden = NO;
                if (!isDragged) place(t, NSMakeRect(cx, 6, pinW, 32));
                cx += pinW + pinGap;
                [t updateAppearance];
                continue;
            }
            NSString *gid = groupOf(t);
            if (gid && ![chipped containsObject:gid]) {
                [chipped addObject:gid];
                NSMutableDictionary *g = self.tabGroups[gid];
                GroupChipView *chip = (GroupChipView *)self.groupChips[gid];
                CGFloat cw = [self chipWidthForGroup:gid];
                NSRect cr = NSMakeRect(cx, 10, cw, 24);
                if (!chip) {
                    chip = [[GroupChipView alloc] initWithFrame:cr];
                    chip.groupID = gid;
                    chip.hostWindow = self;
                    [self.tabBar addSubview:chip];
                    self.groupChips[gid] = chip;
                }
                [chip configureWithText:[self chipTextForGroup:gid] colorIndex:[g[@"color"] integerValue] collapsed:[self isGroupCollapsed:gid]];
                place(chip, cr);
                gStart[gid] = @(cx);
                cx += cw + chipGap;
                gEnd[gid] = @(cx - chipGap);
            }
            if ([self isGroupCollapsed:gid]) { t.hidden = YES; continue; }
            t.hidden = NO;
            if (!isDragged) place(t, NSMakeRect(cx, 6, tabW, 32));
            cx += tabW + gap;
            if (gid) gEnd[gid] = @(cx - gap);
            [t updateAppearance];
        }
        // Colour underline spanning each group
        NSArray<NSColor *> *colors = YGroupColors();
        for (NSString *gid in gStart) {
            NSRect br = NSMakeRect([gStart[gid] doubleValue], 1, [gEnd[gid] doubleValue] - [gStart[gid] doubleValue], 3);
            NSView *bar = self.groupBars[gid];
            if (!bar) {
                bar = [[NSView alloc] initWithFrame:br];
                bar.wantsLayer = YES;
                bar.layer.cornerRadius = 1.5;
                [self.tabBar addSubview:bar positioned:NSWindowBelow relativeTo:nil];
                self.groupBars[gid] = bar;
            }
            NSInteger ci = [self.tabGroups[gid][@"color"] integerValue];
            bar.layer.backgroundColor = colors[MAX(0, MIN((NSInteger)colors.count - 1, ci))].CGColor;
            place(bar, br);
        }
        place(self.addTabButton, NSMakeRect(cx + 2, 6, 32, 32));
    }];
}

- (ChromeTabView *)groupDropTargetForTab:(ChromeTabView *)d {
    if (d.pinned) return nil;
    CGFloat cx = NSMidX(d.frame);
    for (ChromeTabView *t in self.tabs) {
        if (t == d || t.pinned || t.hidden) continue;
        CGFloat w = t.frame.size.width;
        if (cx > t.frame.origin.x + w * 0.25 && cx < t.frame.origin.x + w * 0.75) return t;
    }
    return nil;
}

- (void)moveTab:(ChromeTabView *)t toIndex:(NSInteger)idx {
    NSMutableArray *order = [self.tabs mutableCopy];
    NSInteger old = [order indexOfObject:t];
    [order removeObject:t];
    if (idx > old) idx--;   // index was computed with t still present
    idx = MAX(0, MIN((NSInteger)order.count, idx));
    [order insertObject:t atIndex:idx];
    [self applyTabOrder:order];
}

// Where the dragged tab would land if dropped now, and which group it would belong to.
- (NSArray<ChromeTabView *> *)orderForDrop:(ChromeTabView *)d group:(NSString **)outGroup {
    CGFloat cx = NSMidX(d.frame);
    NSMutableArray<ChromeTabView *> *others = [self.tabs mutableCopy];
    [others removeObject:d];
    NSInteger slot = others.count;
    BOOL found = NO;
    for (NSInteger i = 0; i < (NSInteger)others.count; i++) {
        ChromeTabView *t = others[i];
        if (t.hidden) continue;
        if (cx < NSMidX(t.frame)) { slot = i; found = YES; break; }
    }
    if (!found) {
        for (NSInteger i = (NSInteger)others.count - 1; i >= 0; i--) {
            if (!others[i].hidden) { slot = i + 1; break; }
        }
    }
    NSInteger pinnedCount = 0;
    for (ChromeTabView *t in others) if (t.pinned) pinnedCount++;
    slot = d.pinned ? MIN(slot, pinnedCount) : MAX(slot, pinnedCount);
    [others insertObject:d atIndex:slot];

    ChromeTabView *L = slot > 0 ? others[slot - 1] : nil;
    ChromeTabView *R = slot + 1 < (NSInteger)others.count ? others[slot + 1] : nil;
    NSString *gid = nil;
    if (!d.pinned) {
        if (L.groupID && [L.groupID isEqualToString:R.groupID]) gid = L.groupID;
        else if (d.groupID && ([d.groupID isEqualToString:L.groupID] || [d.groupID isEqualToString:R.groupID])) gid = d.groupID;
        if ([self isGroupCollapsed:gid] && ![gid isEqualToString:d.groupID]) gid = nil;
    }
    if (outGroup) *outGroup = gid;
    return others;
}

- (void)tabDragMoved:(ChromeTabView *)d {
    self.dragTab = d;
    ChromeTabView *target = [self groupDropTargetForTab:d];
    for (ChromeTabView *t in self.tabs) t.dropTarget = (t == target);

    NSArray *newOrder = nil;
    NSString *newGroup = nil;
    if (!target) newOrder = [self orderForDrop:d group:&newGroup];
    BOOL same = (!newOrder && !self.dragPreviewOrder) ||
                (newOrder && self.dragPreviewOrder && [newOrder isEqualToArray:self.dragPreviewOrder] &&
                 [(newGroup ?: @"") isEqualToString:(self.dragPreviewGroup ?: @"")]);
    if (same) return;
    self.dragPreviewOrder = newOrder;
    self.dragPreviewGroup = newGroup;
    [self relayoutAnimated];
}

- (void)tabDragEnded:(ChromeTabView *)d {
    ChromeTabView *target = [self groupDropTargetForTab:d];
    for (ChromeTabView *t in self.tabs) t.dropTarget = NO;
    [self ensureGroupStorage];
    self.dragPreviewOrder = nil;
    self.dragPreviewGroup = nil;
    self.dragTab = nil;

    if (target) {
        // Dropped on a tab: join its group, or start a new group with it
        [self moveTab:d toIndex:[self.tabs indexOfObject:target] + 1];
        NSString *gid = target.groupID;
        if (!gid) {
            gid = [NSUUID UUID].UUIDString;
            self.tabGroups[gid] = [@{@"name": @"", @"color": @(self.tabGroups.count % YGroupColors().count), @"collapsed": @NO} mutableCopy];
            target.groupID = gid;
        }
        d.groupID = gid;
    } else {
        NSString *gid = nil;
        NSArray *order = [self orderForDrop:d group:&gid];
        [self applyTabOrder:order];
        d.groupID = gid;
    }
    [self relayoutAnimated];
}

#pragma mark Group dragging

- (void)groupDragMoved:(NSView *)chip deltaX:(CGFloat)dx {
    GroupChipView *c = (GroupChipView *)chip;
    NSString *gid = c.groupID;
    if (!self.groupDragItems) {
        NSMutableArray *items = [NSMutableArray array];
        NSMutableArray<NSView *> *views = [NSMutableArray arrayWithObject:chip];
        if (self.groupBars[gid]) [views addObject:self.groupBars[gid]];
        for (ChromeTabView *t in [self membersOfGroup:gid]) if (!t.hidden) [views addObject:t];
        for (NSView *v in views) [items addObject:@{@"view": v, @"x": @(v.frame.origin.x)}];
        self.groupDragItems = items;
        for (NSView *v in views) [self.tabBar addSubview:v positioned:NSWindowAbove relativeTo:nil];
    }
    CGFloat minX = [self.groupDragItems.firstObject[@"x"] doubleValue];
    dx = MAX(dx, -minX);
    for (NSDictionary *it in self.groupDragItems) {
        NSView *v = it[@"view"];
        NSRect f = v.frame;
        f.origin.x = [it[@"x"] doubleValue] + dx;
        v.frame = f;
    }
}

- (void)groupDragEnded:(NSView *)chipView {
    GroupChipView *chip = (GroupChipView *)chipView;
    NSString *gid = chip.groupID;
    NSArray<ChromeTabView *> *members = [self membersOfGroup:gid];
    CGFloat left = chip.frame.origin.x, right = NSMaxX(chip.frame);
    for (ChromeTabView *t in members) if (!t.hidden) right = MAX(right, NSMaxX(t.frame));
    CGFloat center = (left + right) / 2;

    // Walk the other "units" (pinned/ungrouped tabs, other groups) to find the drop slot
    NSMutableArray<ChromeTabView *> *others = [self.tabs mutableCopy];
    [others removeObjectsInArray:members];
    NSInteger insertAt = others.count;
    NSMutableSet *seen = [NSMutableSet set];
    for (NSInteger i = 0; i < (NSInteger)others.count; i++) {
        ChromeTabView *t = others[i];
        CGFloat mid;
        if (t.groupID && !t.pinned) {
            if ([seen containsObject:t.groupID]) continue;
            [seen addObject:t.groupID];
            NSView *c2 = self.groupChips[t.groupID];
            CGFloat l2 = c2.frame.origin.x, r2 = NSMaxX(c2.frame);
            for (ChromeTabView *u in [self membersOfGroup:t.groupID]) if (!u.hidden) r2 = MAX(r2, NSMaxX(u.frame));
            mid = (l2 + r2) / 2;
        } else {
            mid = NSMidX(t.frame);
        }
        if (center < mid) { insertAt = i; break; }
    }
    NSInteger pinnedCount = 0;
    for (ChromeTabView *t in others) if (t.pinned) pinnedCount++;
    insertAt = MAX(insertAt, pinnedCount);
    NSMutableArray *order = others;
    for (NSInteger k = 0; k < (NSInteger)members.count; k++) [order insertObject:members[k] atIndex:insertAt + k];
    [self applyTabOrder:order];
    self.groupDragItems = nil;
    [self relayoutAnimated];
}

- (void)toggleGroupCollapse:(NSString *)gid {
    NSMutableDictionary *g = self.tabGroups[gid];
    if (!g) return;
    BOOL collapse = ![g[@"collapsed"] boolValue];
    if (collapse && [self.activeTab.groupID isEqualToString:gid]) {
        // Move off the group's tabs; with nowhere to go, keep it open
        NSInteger target = NSNotFound;
        for (NSInteger i = 0; i < (NSInteger)self.tabs.count; i++) {
            ChromeTabView *t = self.tabs[i];
            if (![t.groupID isEqualToString:gid] && ![self isGroupCollapsed:t.groupID]) { target = i; if (i > self.activeTabIndex) break; }
        }
        if (target == NSNotFound) {
            [self handleNewTab:nil];   // everything is in this group: open a fresh tab to land on
            target = self.activeTabIndex;
        } else {
            [self switchToTabAtIndex:target];
        }
    }
    g[@"collapsed"] = @(collapse);
    [[SaturnSession shared] scheduleSave];
    self.animateTabLayout = YES;
    [self layoutTabs];
    self.animateTabLayout = NO;
}

#pragma mark Tab + group menus

- (NSMenuItem *)menuItem:(NSString *)title action:(SEL)sel object:(id)obj {
    NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:title action:sel keyEquivalent:@""];
    it.target = self;
    it.representedObject = obj;
    return it;
}

- (NSMenu *)menuForTab:(ChromeTabView *)tab {
    [self ensureGroupStorage];
    NSMenu *m = [[NSMenu alloc] initWithTitle:@""];
    [m addItem:[self menuItem:tab.pinned ? @"Unpin Tab" : @"Pin Tab" action:@selector(menuTogglePin:) object:tab]];
    if (!tab.pinned) {
        NSMenu *sub = [[NSMenu alloc] initWithTitle:@""];
        [sub addItem:[self menuItem:@"New Group" action:@selector(menuNewGroup:) object:tab]];
        NSArray<NSColor *> *colors = YGroupColors();
        for (NSString *gid in self.tabGroups) {
            if ([tab.groupID isEqualToString:gid]) continue;
            NSString *name = [self.tabGroups[gid][@"name"] length] ? self.tabGroups[gid][@"name"] : YGroupColorNames()[[self.tabGroups[gid][@"color"] integerValue] % colors.count];
            [sub addItem:[self menuItem:name action:@selector(menuAddToGroup:) object:@[tab, gid]]];
        }
        NSMenuItem *parent = [[NSMenuItem alloc] initWithTitle:@"Add to Group" action:nil keyEquivalent:@""];
        parent.submenu = sub;
        [m addItem:parent];
        if (tab.groupID) [m addItem:[self menuItem:@"Remove from Group" action:@selector(menuRemoveFromGroup:) object:tab]];
    }
    [m addItem:[NSMenuItem separatorItem]];
    [m addItem:[self menuItem:@"Close Tab" action:@selector(menuCloseTab:) object:tab]];
    return m;
}

- (NSMenu *)menuForGroup:(NSString *)gid {
    NSMenu *m = [[NSMenu alloc] initWithTitle:@""];
    [m addItem:[self menuItem:@"Rename Group…" action:@selector(menuRenameGroup:) object:gid]];
    NSMenu *colorMenu = [[NSMenu alloc] initWithTitle:@""];
    NSArray<NSString *> *names = YGroupColorNames();
    NSInteger current = [self.tabGroups[gid][@"color"] integerValue];
    for (NSInteger i = 0; i < (NSInteger)names.count; i++) {
        NSMenuItem *it = [self menuItem:names[i] action:@selector(menuSetGroupColor:) object:@[gid, @(i)]];
        it.state = (i == current) ? NSControlStateValueOn : NSControlStateValueOff;
        [colorMenu addItem:it];
    }
    NSMenuItem *cm = [[NSMenuItem alloc] initWithTitle:@"Colour" action:nil keyEquivalent:@""];
    cm.submenu = colorMenu;
    [m addItem:cm];
    [m addItem:[self menuItem:[self isGroupCollapsed:gid] ? @"Reopen Group" : @"Close Group (Keep Tabs)" action:@selector(menuToggleCollapse:) object:gid]];
    [m addItem:[NSMenuItem separatorItem]];
    [m addItem:[self menuItem:@"Ungroup" action:@selector(menuUngroup:) object:gid]];
    [m addItem:[self menuItem:@"Close Group and Its Tabs" action:@selector(menuCloseGroup:) object:gid]];
    return m;
}

- (void)relayoutAnimated {
    [[SaturnSession shared] scheduleSave];
    self.animateTabLayout = YES;
    [self layoutTabs];
    self.animateTabLayout = NO;
}

- (void)menuTogglePin:(NSMenuItem *)it {
    ChromeTabView *t = it.representedObject;
    t.pinned = !t.pinned;
    if (t.pinned) t.groupID = nil;
    [self relayoutAnimated];
}
- (void)menuNewGroup:(NSMenuItem *)it {
    ChromeTabView *t = it.representedObject;
    [self ensureGroupStorage];
    NSString *gid = [NSUUID UUID].UUIDString;
    self.tabGroups[gid] = [@{@"name": @"", @"color": @(self.tabGroups.count % YGroupColors().count), @"collapsed": @NO} mutableCopy];
    t.groupID = gid;
    [self relayoutAnimated];
}
- (void)menuAddToGroup:(NSMenuItem *)it {
    ChromeTabView *t = it.representedObject[0];
    NSString *gid = it.representedObject[1];
    NSArray *members = [self membersOfGroup:gid];
    t.groupID = gid;
    if (members.count) [self moveTab:t toIndex:[self.tabs indexOfObject:members.lastObject] + 1];
    [self relayoutAnimated];
}
- (void)menuRemoveFromGroup:(NSMenuItem *)it {
    ChromeTabView *t = it.representedObject;
    NSString *gid = t.groupID;
    t.groupID = nil;
    NSArray *rest = [self membersOfGroup:gid];
    if (rest.count) [self moveTab:t toIndex:[self.tabs indexOfObject:rest.lastObject] + 1];
    [self relayoutAnimated];
}
- (void)menuCloseTab:(NSMenuItem *)it { [self closeTabView:it.representedObject]; }
- (void)menuToggleCollapse:(NSMenuItem *)it { [self toggleGroupCollapse:it.representedObject]; }
- (void)menuSetGroupColor:(NSMenuItem *)it {
    self.tabGroups[it.representedObject[0]][@"color"] = it.representedObject[1];
    [self relayoutAnimated];
}
- (void)menuUngroup:(NSMenuItem *)it {
    for (ChromeTabView *t in [self membersOfGroup:it.representedObject]) t.groupID = nil;
    [self relayoutAnimated];
}
- (void)menuCloseGroup:(NSMenuItem *)it { [self closeGroupWithID:it.representedObject]; }
- (void)closeGroupWithID:(NSString *)gid {
    for (ChromeTabView *t in [self membersOfGroup:gid]) [self closeTabView:t];
}
- (void)menuRenameGroup:(NSMenuItem *)it {
    NSString *gid = it.representedObject;
    NSMutableDictionary *g = self.tabGroups[gid];
    if (!g) return;
    [YRenameSheet presentOnWindow:self name:g[@"name"] colorIndex:[g[@"color"] integerValue] completion:^(NSString *name, NSInteger colorIndex) {
        g[@"name"] = name;
        g[@"color"] = @(colorIndex);
        [self relayoutAnimated];
    }];
}

- (void)switchToTabAtIndex:(NSInteger)idx {
    if (idx < 0 || idx >= (NSInteger)self.tabs.count) return;
    if (idx != self.activeTabIndex) { [self hideFindBar]; [self hideSuggestions]; }
    if (self.activeTabIndex >= 0 && self.activeTabIndex < (NSInteger)self.tabWebViews.count) {
        self.tabWebViews[self.activeTabIndex].hidden = YES;
        ChromeTabView *prev = self.tabs[self.activeTabIndex];
        [prev updateTitle:prev.title favicon:prev.favicon active:NO];
    }
    ChromeTabView *incoming = self.tabs[idx];
    if (incoming.groupID && [self isGroupCollapsed:incoming.groupID]) {
        self.tabGroups[incoming.groupID][@"collapsed"] = @NO;
        [self layoutTabs];
    }
    self.activeTabIndex = idx;
    WKWebView *wv = self.tabWebViews[idx];
    if (incoming.pendingURL) {   // restored tab: load it the first time it is shown
        NSURL *pu = incoming.pendingURL;
        incoming.pendingURL = nil;
        self.addressBar.stringValue = pu.absoluteString;
        [wv loadRequest:[NSURLRequest requestWithURL:pu]];
    }
    [[SaturnSession shared] scheduleSave];
    wv.hidden = NO;
    [self.contentView addSubview:wv positioned:NSWindowBelow relativeTo:self.tabBar];
    ChromeTabView *cur = self.tabs[idx];
    [cur updateTitle:cur.title favicon:cur.favicon active:YES];
    if (wv.URL) self.addressBar.stringValue = wv.URL.absoluteString;
    else if (wv.backForwardList.currentItem.URL) self.addressBar.stringValue = wv.backForwardList.currentItem.URL.absoluteString;
    [self updateNavButtons];
    [self updateShieldButtonState];
    [self updateBookmarkButton];
    [self updateBookmarkButton];
    [self updateReloadButtonLoading:wv.loading];
    if (wv.loading) { self.progress.hidden = NO; [self.progress startAnimation:nil]; }
    else { [self.progress stopAnimation:nil]; self.progress.hidden = YES; }
}

- (void)closeTabView:(ChromeTabView *)tab {
    NSInteger idx = tab.tabIndex;
    if (idx == NSNotFound) idx = [self.tabs indexOfObject:tab];
    if (idx == NSNotFound) return;
    BOOL wasActive = (idx == self.activeTabIndex);
    WKWebView *wv = self.tabWebViews[idx];
    NSURL *closingURL = wv.URL ?: tab.pendingURL;
    if (closingURL && ![closingURL.scheme isEqualToString:@"about"]) {
        if (!self.closedTabs) self.closedTabs = [NSMutableArray array];
        [self.closedTabs addObject:@{@"url": closingURL.absoluteString, @"title": tab.title ?: @"", @"pinned": @(tab.pinned)}];
        if (self.closedTabs.count > 25) [self.closedTabs removeObjectAtIndex:0];
    }
    [wv removeFromSuperview];
    [self.tabWebViews removeObjectAtIndex:idx];
    [tab removeFromSuperview];
    [self.tabs removeObjectAtIndex:idx];
    if (self.tabs.count == 0) { [self close]; return; }
    if (wasActive) {
        NSInteger newIdx = idx; if (newIdx >= (NSInteger)self.tabs.count) newIdx = self.tabs.count - 1;
        self.activeTabIndex = -1; [self layoutTabs]; [self switchToTabAtIndex:newIdx];
    } else {
        if (idx < self.activeTabIndex) self.activeTabIndex--;
        [self layoutTabs];
        for (NSInteger i=0;i<(NSInteger)self.tabs.count;i++) {
            ChromeTabView *t = self.tabs[i];
            [t updateTitle:t.title favicon:t.favicon active:(i==self.activeTabIndex)];
        }
    }
}

#pragma mark - Chrome actions
- (void)handleNewTab:(id)sender {
    NSString *home = SaturnSettings.shared.currentEngineInfo.homeURL;
    if (!home.length) home = @"https://www.google.com";
    [self createNewTabWithURL:[NSURL URLWithString:home]];
}
- (void)showAIAssistant:(id)sender {
    [self toggleAISidebar];
}
- (void)toggleAISidebar {
    self.aiSidebarVisible = !self.aiSidebarVisible;
    [self layoutFindBar];
    CGFloat W = self.contentView.bounds.size.width;
    CGFloat H = self.contentView.bounds.size.height;
    CGFloat sidebarW = 380;
    CGFloat webH = H - [self currentChromeH];
    // Floating card with 12px margin
    NSRect target = self.aiSidebarVisible ? NSMakeRect(W - sidebarW - 12, 12, sidebarW, webH - 24) : NSMakeRect(W, 12, sidebarW, webH - 24);
    if (self.aiSidebarVisible) {
        self.aiSidebar.hidden = NO;
        self.aiSidebar.alphaValue = 0;
    }
    // Highlight AI button when open
    self.aiButton.layer.backgroundColor = (self.aiSidebarVisible ? Y_blueHover() : Y_blue()).CGColor;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx){
        ctx.duration = 0.28;
        self.aiSidebar.animator.frame = target;
        self.aiSidebar.animator.alphaValue = self.aiSidebarVisible ? 1.0 : 0;
    } completionHandler:^{
        if (!self.aiSidebarVisible) self.aiSidebar.hidden = YES;
        NSLog(@"[saturn] Zarah sidebar %@", self.aiSidebarVisible?@"opened":@"closed");
    }];
}
- (void)handleHannaPan:(NSPanGestureRecognizer *)pan {
    static NSPoint startOrigin;
    static NSPoint startLocation;
    if (pan.state == NSGestureRecognizerStateBegan) {
        startOrigin = self.aiSidebar.frame.origin;
        startLocation = [pan locationInView:self.contentView];
    } else if (pan.state == NSGestureRecognizerStateChanged) {
        NSPoint loc = [pan locationInView:self.contentView];
        CGFloat dx = loc.x - startLocation.x;
        CGFloat dy = loc.y - startLocation.y;
        NSRect f = self.aiSidebar.frame;
        f.origin.x = startOrigin.x + dx;
        f.origin.y = startOrigin.y + dy;
        // Keep inside window bounds with 12px margin
        CGFloat W = self.contentView.bounds.size.width;
        CGFloat H = self.contentView.bounds.size.height;
        f.origin.x = MAX(12, MIN(W - f.size.width - 12, f.origin.x));
        f.origin.y = MAX(12, MIN(H - f.size.height - 12, f.origin.y));
        self.aiSidebar.frame = f;
    }
}
- (void)focusOmnibox:(NSGestureRecognizer *)gr {
    // Clicks on the reload / shield / star buttons are theirs, not a request to focus the field
    NSView *box = gr.view;
    if (box) {
        NSPoint p = [gr locationInView:box];
        NSView *hit = [box hitTest:[box convertPoint:p toView:box.superview]];
        for (NSView *v = hit; v && v != box; v = v.superview) if ([v isKindOfClass:[NSButton class]]) return;
    }
    if (self.addressBar.currentEditor) return;   // already typing: let clicks place the cursor
    [self makeFirstResponder:self.addressBar];
    [self addressBarDidBecomeFirstResponder:nil];
    dispatch_async(dispatch_get_main_queue(), ^{ [self.addressBar selectText:nil]; });
}

#pragma mark - Zarah Chat (OpenCode Zen) — premium bubbles + markdown + typing

- (NSView *)hannaBubbleWithText:(NSString *)text from:(NSString *)sender {
    BOOL isHanna = [sender isEqualToString:@"hanna"];
    CGFloat maxW = isHanna ? 296 : 270;
    CGFloat paddingX = isHanna ? 0 : 16;
    CGFloat paddingY = isHanna ? 2 : 10;

    NSAttributedString *attr = nil;
    if (isHanna) {
        attr = AttrForMarkdownColored(text, 14, Y_ink(), YES);
    } else {
        NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
        ps.lineSpacing = 3;
        attr = [[NSAttributedString alloc] initWithString:text attributes:@{
            NSForegroundColorAttributeName: [NSColor whiteColor],
            NSFontAttributeName: [NSFont systemFontOfSize:14 weight:NSFontWeightRegular],
            NSParagraphStyleAttributeName: ps
        }];
    }

    CGFloat maxTextW = maxW - (paddingX * 2);
    NSRect textRect = [attr boundingRectWithSize:NSMakeSize(maxTextW, CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading];
    CGFloat textW = ceil(textRect.size.width) + 2;
    if (textW < 20) textW = 20;
    if (textW > maxTextW) textW = maxTextW;
    if (isHanna) textW = maxTextW;   // plain text uses the full column so wrapping matches the measurement

    CGFloat textH = ceil(textRect.size.height);
    if (textH < 20) textH = 20;

    CGFloat bubbleW = textW + (paddingX * 2);
    CGFloat bubbleH = textH + (paddingY * 2);
    if (!isHanna && bubbleH < 40) bubbleH = 40;

    NSView *bubble = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, bubbleW, bubbleH)];
    bubble.wantsLayer = YES;
    if (!isHanna) {
        bubble.layer.cornerRadius = MIN(bubbleH / 2, 22);
        bubble.layer.backgroundColor = Y_blue().CGColor;
    }

    NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(paddingX, paddingY, textW, textH)];
    tv.editable = NO;
    tv.selectable = YES;
    tv.backgroundColor = [NSColor clearColor];
    tv.drawsBackground = NO;
    tv.textContainerInset = NSMakeSize(0, 0);
    tv.verticallyResizable = YES;
    tv.horizontallyResizable = NO;
    tv.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [tv.textContainer setWidthTracksTextView:YES];
    [tv.textContainer setContainerSize:NSMakeSize(textW, CGFLOAT_MAX)];
    tv.textContainer.lineFragmentPadding = 0;
    tv.linkTextAttributes = @{NSForegroundColorAttributeName: isHanna ? Y_blue() : [NSColor whiteColor], NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle)};
    tv.textStorage.attributedString = attr;
    [bubble addSubview:tv];

    return bubble;
}

// Types the reply out. The bubble is already sized for the whole text, so nothing reflows: the
// characters that are not typed yet are simply drawn transparent. Long replies speed up so any
// reply finishes within about 4 seconds.
- (void)typewriteInTextView:(NSTextView *)tv {
    if (![tv isKindOfClass:[NSTextView class]]) return;
    NSAttributedString *full = [tv.textStorage copy];
    NSUInteger total = full.length;
    if (total < 2 || NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) return;

    CGFloat seconds = MIN(4.0, MAX(0.5, total / 140.0));
    NSUInteger perTick = MAX((NSUInteger)1, (NSUInteger)ceil(total / (seconds * 60.0)));
    __block NSUInteger shown = 0;
    NSColor *clear = [NSColor clearColor];

    void (^render)(NSUInteger) = ^(NSUInteger n) {
        NSMutableAttributedString *a = [full mutableCopy];
        if (n < total) {
            NSRange rest = NSMakeRange(n, total - n);
            [a addAttribute:NSForegroundColorAttributeName value:clear range:rest];
            [a removeAttribute:NSBackgroundColorAttributeName range:rest];
            [a removeAttribute:NSUnderlineStyleAttributeName range:rest];
        }
        [tv.textStorage setAttributedString:a];
    };
    render(0);

    NSTimer *timer = [NSTimer timerWithTimeInterval:1.0 / 60.0 repeats:YES block:^(NSTimer *t) {
        shown = MIN(total, shown + perTick);
        if (!tv.window) { shown = total; }                     // cleared or closed: finish and stop
        render(shown);
        if (shown >= total) [t invalidate];
    }];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
}

- (void)appendHannaMessage:(NSString *)text from:(NSString *)sender {
    if (!text.length) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSScrollView *scroll = self.hannaScrollView;
        HannaChatDocView *doc = (HannaChatDocView *)scroll.documentView;
        if (![doc isKindOfClass:[HannaChatDocView class]]) return;

        for (NSView *v in [doc.messageViews copy]) {
            if ([v isKindOfClass:[HannaEmptyState class]]) [doc removeMessageView:v];
        }

        NSView *bubble = [self hannaBubbleWithText:text from:sender];
        BOOL isUser = [sender isEqualToString:@"user"];
        if (!isUser) [self typewriteInTextView:(NSTextView *)bubble.subviews.firstObject];

        if (isUser) {
            bubble.identifier = @"userRow";
            [doc addMessageView:bubble];
        } else {
            CGFloat rowW = bubble.bounds.size.width + 34;
            CGFloat rowH = MAX(28, bubble.bounds.size.height);
            NSView *row = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, rowW, rowH)];

            NSView *av = HannaAvatar(24);
            av.frame = NSMakeRect(0, 2, 24, 24);
            [row addSubview:av];

            bubble.frame = NSMakeRect(32, 0, bubble.bounds.size.width, bubble.bounds.size.height);
            [row addSubview:bubble];

            row.identifier = @"hannaRow";
            [doc addMessageView:row];
        }

        CGFloat maxY = MAX(0, doc.frame.size.height - scroll.contentView.bounds.size.height);
        [scroll.contentView scrollToPoint:NSMakePoint(0, maxY)];
        [scroll reflectScrolledClipView:scroll.contentView];
    });
}

- (void)getHannaBrowserContextWithCompletion:(void(^)(NSString *context))completion {
    // Collect current tab + all tabs + visible text for Zarah so she CAN see your browser (no more "I can't see your tabs")
    NSMutableString *ctx = [NSMutableString string];
    [ctx appendString:@"You are Zarah, an AI assistant integrated into the Saturn browser. You CAN see the user's browser and you HAVE access to their current tabs, URL, and page content. Do NOT say you can't see tabs/screens. Use the context below to answer about what's open.\n\n"];
    // All tabs
    [ctx appendFormat:@"Open tabs (%lu):\n", (unsigned long)self.tabs.count];
    for (NSInteger i=0; i<(NSInteger)self.tabs.count; i++) {
        ChromeTabView *t = self.tabs[i];
        WKWebView *wv = (i < (NSInteger)self.tabWebViews.count) ? self.tabWebViews[i] : nil;
        NSString *title = t.title ?: wv.title ?: @"Untitled";
        NSString *url = wv.URL.absoluteString ?: wv.backForwardList.currentItem.URL.absoluteString ?: @"(no URL)";
        NSString *marker = (i == self.activeTabIndex) ? @" [CURRENT]" : @"";
        [ctx appendFormat:@"%ld. %@ — %@%@\n", (long)(i+1), title, url, marker];
    }
    // Current tab details
    WKWebView *cur = self.webView;
    if (cur) {
        NSString *url = cur.URL.absoluteString ?: @"(no URL)";
        NSString *title = cur.title ?: @"Untitled";
        [ctx appendFormat:@"\nCurrent tab:\n- Title: %@\n- URL: %@\n", title, url];
        // Visible text (async)
        [cur evaluateJavaScript:@"(document.body?document.body.innerText:'').replace(/\\s+/g,' ').slice(0,4000)" completionHandler:^(id result, NSError *error){
            NSString *text = @"";
            if ([result isKindOfClass:[NSString class]]) text = result;
            if (text.length) {
                if (text.length > 3500) text = [[text substringToIndex:3500] stringByAppendingString:@" ...[truncated]"];
                [ctx appendFormat:@"- Visible text (first 3500 chars): %@\n", text];
            } else {
                [ctx appendString:@"- Visible text: (empty or not loaded)\n"];
            }
            [ctx appendString:@"\nRespond helpfully using this context. If asked about tabs, list them. If asked about page, summarize visible text."];
            if (completion) completion([ctx copy]);
        }];
    } else {
        [ctx appendString:@"\nNo current tab loaded.\n"];
        if (completion) completion([ctx copy]);
    }
}

- (void)hannaSend:(id)sender {
    NSString *text = [self.hannaInputField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!text.length) return;
    if (self.hannaActMode) { [self hannaSendAgentTask:text]; return; }
    // Add user message
    [self.hannaHistory addObject:@{@"role": @"user", @"content": text}];
    [self appendHannaMessage:text from:@"user"];
    self.hannaInputField.stringValue = @"";
    // UI busy — premium typing animation + spinner
    self.hannaSendButton.enabled = NO;
    self.hannaInputField.enabled = NO;
    [self.hannaSpinner startAnimation:nil];
    self.hannaSpinner.hidden = NO;
    [self showHannaTyping:YES];
    // Ensure sidebar visible
    if (!self.aiSidebarVisible) [self toggleAISidebar];

    __weak typeof(self) weakSelf = self;
    NSArray *historyCopy = [self.hannaHistory copy];
    NSMutableArray *histForAPI = [historyCopy mutableCopy];
    if (histForAPI.count > 0) [histForAPI removeLastObject];

    // Fetch browser context so Zarah CAN see tabs/screen
    [self getHannaBrowserContextWithCompletion:^(NSString *browserContext){
        [[HannaClient shared] sendMessage:text history:histForAPI browserContext:browserContext completion:^(NSString *reply, NSError *error){
        __strong typeof(weakSelf) s = weakSelf;
        if (!s) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            [s.hannaSpinner stopAnimation:nil];
            s.hannaSpinner.hidden = YES;
            [s showHannaTyping:NO];
            s.hannaSendButton.enabled = YES;
            s.hannaInputField.enabled = YES;
            [s.hannaInputField becomeFirstResponder];
            if (error) {
                NSString *msg = error.localizedDescription ?: @"Unknown error";
                [s appendHannaMessage:[NSString stringWithFormat:@"⚠️ %@", msg] from:@"hanna"];
                NSLog(@"[hanna] error %@", error);
                return;
            }
            NSString *clean = [reply stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (!clean.length) clean = @"(Empty reply)";
            [s.hannaHistory addObject:@{@"role": @"assistant", @"content": clean}];
            [s appendHannaMessage:clean from:@"hanna"];
        });
    }];
    }];
}
- (void)addressBarDidBecomeFirstResponder:(NSNotification *)n {
    (void)n;
    self.omniboxContainer.layer.borderColor = Y_blue().CGColor;
    self.omniboxContainer.layer.backgroundColor = [NSColor whiteColor].CGColor;
}
- (void)addressBarDidResignFirstResponder:(NSNotification *)n {
    (void)n;
    [self hideSuggestions];
    self.omniboxContainer.layer.borderColor = [NSColor clearColor].CGColor;
    self.omniboxContainer.layer.backgroundColor = Y_soft().CGColor;
    if (self.webView.URL) self.addressBar.stringValue = self.webView.URL.absoluteString;
}

#pragma mark - Actions
- (void)goBack:(id)sender { WKWebView *wv = self.webView; if (wv.canGoBack) [wv goBack]; }
- (void)goForward:(id)sender { WKWebView *wv = self.webView; if (wv.canGoForward) [wv goForward]; }
- (void)reload:(id)sender { [self.webView reload]; }
- (void)reloadOrStop:(id)sender {
    (void)sender;
    if (self.webView.loading) [self.webView stopLoading]; else [self.webView reload];
}
- (void)setLoading:(BOOL)loading forWebView:(WKWebView *)wv {
    NSInteger idx = [self indexForWebView:wv];
    if (idx != NSNotFound) self.tabs[idx].loading = loading;
    if (wv == self.webView) [self updateReloadButtonLoading:loading];
}
- (void)updateReloadButtonLoading:(BOOL)loading {
    self.reloadBtn.image = Y_symbol(loading ? @"xmark" : @"arrow.clockwise", 14, NSFontWeightMedium);
    self.reloadBtn.toolTip = loading ? @"Stop loading" : @"Reload (⌘R)";
}
- (void)goAddress:(id)sender { [self navigateToString:self.addressBar.stringValue]; }
- (void)newWindow:(id)sender {
    if ([NSApp.delegate respondsToSelector:@selector(createWindowWithURL:)]) {
        [NSApp.delegate performSelector:@selector(createWindowWithURL:) withObject:[NSURL URLWithString:@"https://www.google.com"]];
    }
}
- (void)star:(id)sender {
    (void)sender;
    NSURL *u = self.webView.URL;
    if (![SaturnBookmarks canBookmarkURL:u]) { NSBeep(); return; }
    NSString *title = self.webView.title.length ? self.webView.title : u.host;
    BOOL now = [[SaturnBookmarks shared] toggleURL:u title:title];
    [self updateBookmarkButton];
    // Small pop so the change reads even at a glance
    CALayer *l = self.bookmarkButton.layer;
    if (now && l) {
        CASpringAnimation *pop = [CASpringAnimation animationWithKeyPath:@"transform.scale"];
        pop.fromValue = @0.7; pop.toValue = @1; pop.mass = 1; pop.stiffness = 260; pop.damping = 12;
        pop.duration = pop.settlingDuration;
        [l addAnimation:pop forKey:@"pop"];
    }
}

- (void)showSecretImagePage {
    NSString *img = SaturnSecretImageURL();
    NSString *html = [NSString stringWithFormat:
        @"<html><head><meta name='viewport' content='width=device-width,initial-scale=1'>"
        @"<style>body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;"
        @"background:radial-gradient(1200px 600px at 50%% -10%%,#2b2350 0%%,#14141b 55%%,#0e0f13 100%%);"
        @"color:#fff;font-family:-apple-system,Helvetica,Arial,sans-serif;}"
        @".card{max-width:640px;width:92%%;text-align:center;background:rgba(255,255,255,.06);"
        @"border:1px solid rgba(255,255,255,.12);border-radius:20px;padding:28px;"
        @"box-shadow:0 20px 60px rgba(0,0,0,.5);backdrop-filter:blur(20px);}"
        @".badge{display:inline-block;font-size:13px;letter-spacing:.08em;text-transform:uppercase;"
        @"color:#b7a8ff;background:rgba(139,124,255,.15);border:1px solid rgba(139,124,255,.4);"
        @"padding:6px 12px;border-radius:999px;margin-bottom:14px;}"
        @"h1{font-size:24px;margin:6px 0 4px;}p{opacity:.7;font-size:14px;margin:0 0 18px;}"
        @"img{width:100%%;border-radius:14px;border:1px solid rgba(255,255,255,.15);display:block;}</style></head>"
        @"<body><div class='card'><div class='badge'>✦ Zarah</div>"
        @"<h1>✨ Here is my favorite image! 🪐</h1>"
        @"<p>You found the Saturn Easter egg</p>"
        @"<img src='%@' alt='Zarah favorite image'></div></body></html>", img];
    ChromeTabView *tab = self.activeTab;
    if (tab) [tab updateTitle:@"✨ Zarah's Favorite Image" favicon:nil active:YES];
    [self.webView loadHTMLString:html baseURL:nil];
    [self updateNavButtons];
}

- (void)navigateToString:(NSString *)urlString {
    NSString *s = [urlString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (s.length == 0) return;
    if (SaturnIsSecretImageQuery(s)) {
        self.addressBar.stringValue = s;
        [self showSecretImagePage];
        [self makeFirstResponder:nil];
        return;
    }
    if (![s containsString:@"://"]) {
        BOOL hasDot = [s containsString:@"."];
        BOOL hasSpace = [s containsString:@" "];
        if (hasDot && !hasSpace) s = [@"https://" stringByAppendingString:s];
        else {
            s = [[SaturnSettings shared] searchURLForQuery:s];
        }
    }
    NSURL *u = [NSURL URLWithString:s]; if (!u) return;
    self.addressBar.stringValue = u.absoluteString;
    ChromeTabView *tab = self.activeTab; if (tab) [tab updateTitle:@"Loading…" favicon:nil active:YES];
    [self.webView loadRequest:[NSURLRequest requestWithURL:u]];
}

- (void)updateNavButtons {
    WKWebView *wv = self.webView;
    self.backBtn.enabled = wv.canGoBack;
    self.forwardBtn.enabled = wv.canGoForward;
    self.backBtn.contentTintColor = self.backBtn.enabled ? Y_ink() : [NSColor colorWithWhite:0 alpha:0.28];
    self.forwardBtn.contentTintColor = self.forwardBtn.enabled ? Y_ink() : [NSColor colorWithWhite:0 alpha:0.28];
}

#pragma mark - NSTextFieldDelegate
- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
    if (control == self.addressBar) {
        BOOL showing = [self suggestionsVisible];
        if (commandSelector == @selector(insertNewline:)) {
            NSDictionary *pick = showing ? [self.suggestView selectedItem] : nil;
            if (pick) { [self pickSuggestion:pick]; return YES; }
            [self hideSuggestions];
            [self navigateToString:self.addressBar.stringValue];
            [self makeFirstResponder:nil];
            return YES;
        }
        if (commandSelector == @selector(cancelOperation:)) {
            if (showing) { [self hideSuggestions]; return YES; }   // first Esc closes the list
            [self makeFirstResponder:nil];
            [self addressBarDidResignFirstResponder:nil];
            return YES;
        }
        if (commandSelector == @selector(moveDown:) && showing) { [self.suggestView moveSelection:1]; return YES; }
        if (commandSelector == @selector(moveUp:) && showing) { [self.suggestView moveSelection:-1]; return YES; }
    }
    if (control == self.hannaInputField) {
        if (commandSelector == @selector(insertNewline:)) {
            [self hannaSend:nil];
            return YES;
        }
        if (commandSelector == @selector(cancelOperation:)) {
            if (self.aiSidebarVisible) [self toggleAISidebar];
            return YES;
        }
    }
    return NO;
}
- (void)controlTextDidChange:(NSNotification *)obj {
    if (obj.object == self.addressBar) [self updateSuggestions];
}
- (void)controlTextDidEndEditing:(NSNotification *)obj {
    if (obj.object == self.addressBar) {
        [self hideSuggestions];
        NSInteger reason = [[[obj userInfo] objectForKey:@"NSTextMovement"] integerValue];
        if (reason == NSReturnTextMovement) [self navigateToString:self.addressBar.stringValue];
        else [self addressBarDidResignFirstResponder:obj];
    }
}

#pragma mark - Helpers
- (NSInteger)indexForWebView:(WKWebView *)wv { return [self.tabWebViews indexOfObject:wv]; }

- (void)fetchFaviconForWebView:(WKWebView *)webView {
    if ([webView.URL.scheme isEqualToString:@"saturn"]) return;   // built-in pages have no site icon
    NSString *host = webView.URL.host;
    if (!host.length) return;
    NSImage *cached = self.faviconCache[host];
    if (cached) {
        NSInteger idx = [self indexForWebView:webView];
        if (idx != NSNotFound) {
            ChromeTabView *t = self.tabs[idx];
            dispatch_async(dispatch_get_main_queue(), ^{
                [t updateTitle:t.title favicon:cached active:(idx==self.activeTabIndex)];
            });
        }
        return;
    }
    // Try JS to find <link rel="icon">
    NSString *js = @"(function(){var l=document.querySelector('link[rel*=\"icon\"]'); return l?l.href:null;})()";
    [webView evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
        NSString *href = nil;
        if ([result isKindOfClass:[NSString class]] && [(NSString*)result length] > 0) href = result;
        NSString *tryURL = href;
        if (!tryURL.length) {
            NSString *scheme = webView.URL.scheme ?: @"https";
            tryURL = [NSString stringWithFormat:@"%@://%@/favicon.ico", scheme, host];
        }
        NSURL *u = [NSURL URLWithString:tryURL];
        if (!u) {
            u = [NSURL URLWithString:[NSString stringWithFormat:@"https://www.google.com/s2/favicons?domain=%@&sz=32", host]];
        }
        NSURLSession *session = [NSURLSession sharedSession];
        NSURLSessionDataTask *task = [session dataTaskWithURL:u completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
            NSImage *img = nil;
            if (data && !err && ((NSHTTPURLResponse*)resp).statusCode == 200) {
                img = [[NSImage alloc] initWithData:data];
                // Validate image has content
                if (img && img.size.width < 4) img = nil;
            }
            if (!img) {
                // Fallback to Google S2
                NSURL *g = [NSURL URLWithString:[NSString stringWithFormat:@"https://www.google.com/s2/favicons?domain=%@&sz=32", host]];
                NSData *d2 = [NSData dataWithContentsOfURL:g];
                if (d2) img = [[NSImage alloc] initWithData:d2];
            }
            if (!img) {
                img = [NSImage imageWithSystemSymbolName:@"globe" accessibilityDescription:nil];
            } else {
                // Resize to 16x16 for tab
                NSImage *resized = [[NSImage alloc] initWithSize:NSMakeSize(16, 16)];
                [resized lockFocus];
                [NSGraphicsContext currentContext].imageInterpolation = NSImageInterpolationHigh;
                [img drawInRect:NSMakeRect(0,0,16,16) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
                [resized unlockFocus];
                [resized setTemplate:NO];
                img = resized;
            }
            if (img) {
                self.faviconCache[host] = img;
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSInteger idx2 = [self indexForWebView:webView];
                    if (idx2 != NSNotFound) {
                        ChromeTabView *t2 = self.tabs[idx2];
                        [t2 updateTitle:t2.title favicon:img active:(idx2==self.activeTabIndex)];
                    }
                });
            }
        }];
        [task resume];
    }];
}

#pragma mark - WKNavigationDelegate
- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    NSLog(@"[saturn] didStart %@", webView.URL ?: @"(nil)");
    [[SaturnShield shared] resetBlockedCountForWebView:webView];
    [self setLoading:YES forWebView:webView];
    if (webView == self.webView) {
        self.progress.hidden = NO; [self.progress startAnimation:nil];
        ChromeTabView *tab = self.activeTab; if (tab) [tab updateTitle:@"Loading…" favicon:nil active:YES];
        [self updateShieldButtonState];
    } else {
        NSInteger idx = [self indexForWebView:webView];
        if (idx != NSNotFound) { ChromeTabView *t = self.tabs[idx]; [t updateTitle:@"Loading…" favicon:nil active:NO]; }
    }
}
- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation {
    NSLog(@"[saturn] didCommit %@", webView.URL);
    NSInteger idx = [self indexForWebView:webView];
    if (idx != NSNotFound) { ChromeTabView *t = self.tabs[idx]; NSString *host = webView.URL.host ?: @"New Tab"; [t updateTitle:host favicon:nil active:(idx==self.activeTabIndex)]; }
    if (webView == self.webView) {
        if (webView.URL && !self.addressBar.currentEditor) self.addressBar.stringValue = webView.URL.absoluteString;
        [self updateNavButtons];
        [self updateShieldButtonState];
        [self updateBookmarkButton];
    }
}
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    NSLog(@"[saturn] didFinish %@ title=%@", webView.URL, webView.title);
    [self setLoading:NO forWebView:webView];
    if (!self.isPrivate) [[SaturnHistory shared] recordURL:webView.URL title:webView.title];
    NSInteger idx = [self indexForWebView:webView];
    NSString *title = webView.title; if (title.length == 0) title = webView.URL.host ?: @"New Tab";
    if (idx != NSNotFound) {
        ChromeTabView *t = self.tabs[idx];
        // keep existing favicon until fetch completes
        NSImage *keep = t.favicon ?: [NSImage imageWithSystemSymbolName:@"globe" accessibilityDescription:nil];
        if ([webView.URL.scheme isEqualToString:@"saturn"]) keep = Y_symbol(@"clock.arrow.circlepath", 14, NSFontWeightMedium);
        [t updateTitle:title favicon:keep active:(idx==self.activeTabIndex)];
        [[SaturnSession shared] scheduleSave];
        [self fetchFaviconForWebView:webView];
    }
    if (webView == self.webView) {
        [self.progress stopAnimation:nil];
        self.progress.hidden = YES;
        if (webView.URL && !self.addressBar.currentEditor) self.addressBar.stringValue = webView.URL.absoluteString;
        [self updateNavButtons];
        [self updateShieldButtonState];
        [self updateBookmarkButton];
    }
}
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self setLoading:NO forWebView:webView];
    if (webView == self.webView) { [self.progress stopAnimation:nil]; self.progress.hidden = YES; }
    if (error.code == NSURLErrorCancelled) return;
    NSLog(@"[saturn] fail: %@", error);
}
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self setLoading:NO forWebView:webView];
    if (webView == self.webView) { [self.progress stopAnimation:nil]; self.progress.hidden = YES; }
    if (error.code == NSURLErrorCancelled) return;
    NSString *html = [NSString stringWithFormat:@"<html><body style='font-family:sans-serif;padding:40px;background:#fff;color:#1C2B33'><h2>Can't reach this page</h2><p>%@</p><p>%@</p></body></html>", error.localizedDescription, webView.URL.absoluteString ?: @""];
    [webView loadHTMLString:html baseURL:nil];
}

#pragma mark - WKUIDelegate
- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures {
    if (navigationAction.targetFrame == nil) { [self createNewTabWithURL:navigationAction.request.URL]; return nil; }
    return nil;
}
- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completionHandler {
    NSAlert *a = [self jsDialogForFrame:frame message:message]; [a addButtonWithTitle:@"OK"]; [a runModal]; completionHandler();
}
- (void)webView:(WKWebView *)webView runJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(BOOL))completionHandler {
    NSAlert *a = [self jsDialogForFrame:frame message:message]; [a addButtonWithTitle:@"OK"]; [a addButtonWithTitle:@"Cancel"]; completionHandler([a runModal]==NSAlertFirstButtonReturn);
}

- (void)webView:(WKWebView *)webView runOpenPanelWithParameters:(WKOpenPanelParameters *)parameters initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(NSArray<NSURL *> * _Nullable))completionHandler {
    (void)frame;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = parameters.allowsDirectories;
    panel.allowsMultipleSelection = parameters.allowsMultipleSelection;
    void (^done)(NSModalResponse) = ^(NSModalResponse result) {
        completionHandler(result == NSModalResponseOK ? panel.URLs : nil);
    };
    if (webView.window) {
        [panel beginSheetModalForWindow:webView.window completionHandler:done];
    } else {
        done([panel runModal]);
    }
}

#pragma mark - WKScriptMessageHandler
- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    (void)userContentController;
    if ([message.name isEqualToString:@"saturnHistory"]) { [self handleHistoryMessage:message]; return; }
    if ([message.name isEqualToString:@"contextMenuInfo"]) {
        if ([message.body isKindOfClass:[NSDictionary class]]) {
            self.lastContextMenuInfo = [message.body mutableCopy];
            self.lastContextMenuInfo[@"webView"] = message.webView;
        }
    } else if ([message.name isEqualToString:@"shieldBlocked"]) {
        if ([message.body isKindOfClass:[NSDictionary class]]) {
            NSString *category = message.body[@"category"] ?: @"ads";
            NSInteger count = [message.body[@"count"] integerValue];
            if (count > 0 && [message.webView isKindOfClass:[WKWebView class]]) {
                [[SaturnShield shared] recordBlockedCategory:category count:count forWebView:message.webView];
                if (message.webView == self.webView) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self updateShieldButtonState];
                    });
                }
            }
        }
    }
}

#pragma mark - Custom Context Menu (Replaces default WebKit/Google menu)
- (void)webView:(WKWebView *)webView getContextMenuFromProposedMenu:(NSMenu *)menu forElement:(id)elementInfo completionHandler:(void (^)(NSMenu * _Nullable))completionHandler {
    (void)menu;
    (void)elementInfo;
    completionHandler([self buildCustomContextMenuForEvent:nil webView:webView]);
}

- (NSMenu *)buildCustomContextMenuForEvent:(NSEvent *)event webView:(WKWebView *)webView {
    (void)event;
    // Use captured context menu info
    NSDictionary *info = self.lastContextMenuInfo;
    NSString *selectedText = [info[@"text"] isKindOfClass:[NSString class]] ? [info[@"text"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] : @"";
    NSString *linkUrl = [info[@"linkUrl"] isKindOfClass:[NSString class]] ? [info[@"linkUrl"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] : @"";
    NSString *imgUrl = [info[@"imgUrl"] isKindOfClass:[NSString class]] ? [info[@"imgUrl"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] : @"";

    NSMenu *customMenu = [[NSMenu alloc] initWithTitle:@""];

    if (selectedText.length > 0) {
        // === 1. HIGHLIGHTED TEXT MENU ===
        NSMenuItem *explainItem = [[NSMenuItem alloc] initWithTitle:@"✦ Explain with Zarah" action:@selector(handleExplainWithHanna:) keyEquivalent:@""];
        explainItem.target = self;
        explainItem.representedObject = info;
        [customMenu addItem:explainItem];

        [customMenu addItem:[NSMenuItem separatorItem]];

        NSMenuItem *copyItem = [[NSMenuItem alloc] initWithTitle:@"Copy" action:@selector(handleCopySelection:) keyEquivalent:@"c"];
        copyItem.target = self;
        copyItem.representedObject = selectedText;
        [customMenu addItem:copyItem];

        NSString *truncatedSearch = selectedText.length > 30 ? [NSString stringWithFormat:@"%@…", [selectedText substringToIndex:28]] : selectedText;
        truncatedSearch = [truncatedSearch stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
        NSMenuItem *searchItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Search Web for “%@”", truncatedSearch] action:@selector(handleSearchSelection:) keyEquivalent:@""];
        searchItem.target = self;
        searchItem.representedObject = selectedText;
        [customMenu addItem:searchItem];

        [customMenu addItem:[NSMenuItem separatorItem]];

        NSMenuItem *selectAllItem = [[NSMenuItem alloc] initWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
        [customMenu addItem:selectAllItem];

    } else if (linkUrl.length > 0) {
        // === 2. LINK MENU ===
        NSMenuItem *openTabItem = [[NSMenuItem alloc] initWithTitle:@"Open Link in New Tab" action:@selector(handleOpenLinkInNewTab:) keyEquivalent:@""];
        openTabItem.target = self;
        openTabItem.representedObject = linkUrl;
        [customMenu addItem:openTabItem];

        NSMenuItem *copyLinkItem = [[NSMenuItem alloc] initWithTitle:@"Copy Link Address" action:@selector(handleCopyLinkAddress:) keyEquivalent:@""];
        copyLinkItem.target = self;
        copyLinkItem.representedObject = linkUrl;
        [customMenu addItem:copyLinkItem];

        [customMenu addItem:[NSMenuItem separatorItem]];

        NSMenuItem *backItem = [[NSMenuItem alloc] initWithTitle:@"Back" action:@selector(goBack:) keyEquivalent:@"["];
        backItem.target = self;
        backItem.enabled = webView.canGoBack;
        [customMenu addItem:backItem];

        NSMenuItem *forwardItem = [[NSMenuItem alloc] initWithTitle:@"Forward" action:@selector(goForward:) keyEquivalent:@"]"];
        forwardItem.target = self;
        forwardItem.enabled = webView.canGoForward;
        [customMenu addItem:forwardItem];

        NSMenuItem *reloadItem = [[NSMenuItem alloc] initWithTitle:@"Reload" action:@selector(handleReloadPage:) keyEquivalent:@"r"];
        reloadItem.target = self;
        [customMenu addItem:reloadItem];

    } else if (imgUrl.length > 0) {
        // === 3. IMAGE MENU ===
        NSMenuItem *openImgItem = [[NSMenuItem alloc] initWithTitle:@"Open Image in New Tab" action:@selector(handleOpenLinkInNewTab:) keyEquivalent:@""];
        openImgItem.target = self;
        openImgItem.representedObject = imgUrl;
        [customMenu addItem:openImgItem];

        NSMenuItem *copyImgItem = [[NSMenuItem alloc] initWithTitle:@"Copy Image Address" action:@selector(handleCopyLinkAddress:) keyEquivalent:@""];
        copyImgItem.target = self;
        copyImgItem.representedObject = imgUrl;
        [customMenu addItem:copyImgItem];

    } else {
        // === 4. GENERAL PAGE MENU ===
        NSMenuItem *backItem = [[NSMenuItem alloc] initWithTitle:@"Back" action:@selector(goBack:) keyEquivalent:@"["];
        backItem.target = self;
        backItem.enabled = webView.canGoBack;
        [customMenu addItem:backItem];

        NSMenuItem *forwardItem = [[NSMenuItem alloc] initWithTitle:@"Forward" action:@selector(goForward:) keyEquivalent:@"]"];
        forwardItem.target = self;
        forwardItem.enabled = webView.canGoForward;
        [customMenu addItem:forwardItem];

        NSMenuItem *reloadItem = [[NSMenuItem alloc] initWithTitle:@"Reload" action:@selector(handleReloadPage:) keyEquivalent:@"r"];
        reloadItem.target = self;
        [customMenu addItem:reloadItem];

        [customMenu addItem:[NSMenuItem separatorItem]];

        NSMenuItem *copyUrlItem = [[NSMenuItem alloc] initWithTitle:@"Copy Page URL" action:@selector(handleCopyPageURL:) keyEquivalent:@""];
        copyUrlItem.target = self;
        [customMenu addItem:copyUrlItem];
    }

    [customMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *inspectItem = [[NSMenuItem alloc] initWithTitle:@"Inspect Element" action:@selector(handleInspectElement:) keyEquivalent:@"i"];
    inspectItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    inspectItem.target = self;
    [customMenu addItem:inspectItem];

    return customMenu;
}

#pragma mark - Context Menu Action Handlers

- (void)handleExplainWithHanna:(NSMenuItem *)sender {
    NSDictionary *info = [sender.representedObject isKindOfClass:[NSDictionary class]] ? sender.representedObject : self.lastContextMenuInfo;
    NSString *text = [info[@"text"] isKindOfClass:[NSString class]] ? info[@"text"] : @"";
    if (!text.length) return;

    CGFloat x = [info[@"x"] doubleValue];
    CGFloat y = [info[@"y"] doubleValue];
    CGFloat w = [info[@"w"] doubleValue];
    CGFloat h = [info[@"h"] doubleValue];
    WKWebView *wv = info[@"webView"];
    if (![wv isKindOfClass:[WKWebView class]]) wv = self.webView;

    NSRect targetRect;
    if (w > 0 && h > 0) {
        targetRect = NSMakeRect(x, y, w, h);
    } else {
        NSPoint mouseWindow = [self mouseLocationOutsideOfEventStream];
        NSPoint mouseView = [wv convertPoint:mouseWindow fromView:nil];
        targetRect = NSMakeRect(mouseView.x - 10, mouseView.y - 10, 20, 20);
    }

    [self explainSelectionWithHannaText:text targetRect:targetRect webView:wv];
}

- (void)handleCopySelection:(NSMenuItem *)sender {
    NSString *text = [sender.representedObject isKindOfClass:[NSString class]] ? sender.representedObject : @"";
    if (text.length) {
        [[NSPasteboard generalPasteboard] clearContents];
        [[NSPasteboard generalPasteboard] setString:text forType:NSPasteboardTypeString];
    }
}

- (void)handleSearchSelection:(NSMenuItem *)sender {
    NSString *text = [sender.representedObject isKindOfClass:[NSString class]] ? sender.representedObject : @"";
    if (!text.length) return;
    NSString *urlStr = [SaturnSettings.shared searchURLForQuery:text];
    if (urlStr.length) {
        [self createNewTabWithURL:[NSURL URLWithString:urlStr]];
    }
}

- (void)handleOpenLinkInNewTab:(NSMenuItem *)sender {
    NSString *urlStr = [sender.representedObject isKindOfClass:[NSString class]] ? sender.representedObject : @"";
    if (urlStr.length) {
        [self createNewTabWithURL:[NSURL URLWithString:urlStr]];
    }
}

- (void)handleCopyLinkAddress:(NSMenuItem *)sender {
    NSString *url = [sender.representedObject isKindOfClass:[NSString class]] ? sender.representedObject : @"";
    if (url.length) {
        [[NSPasteboard generalPasteboard] clearContents];
        [[NSPasteboard generalPasteboard] setString:url forType:NSPasteboardTypeString];
    }
}

- (void)handleCopyPageURL:(id)sender {
    (void)sender;
    NSString *url = self.webView.URL.absoluteString;
    if (url.length) {
        [[NSPasteboard generalPasteboard] clearContents];
        [[NSPasteboard generalPasteboard] setString:url forType:NSPasteboardTypeString];
    }
}

- (void)handleReloadPage:(id)sender {
    (void)sender;
    [self.webView reload];
}

- (void)handleInspectElement:(id)sender {
    (void)sender;
    WKWebView *wv = self.webView;
    [wv.configuration.preferences setValue:@YES forKey:@"developerExtrasEnabled"];
    SEL sel = NSSelectorFromString(@"_showInspector");
    if ([wv respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [wv performSelector:sel];
#pragma clang diagnostic pop
    }
}

- (void)explainSelectionWithHannaText:(NSString *)text targetRect:(NSRect)rect webView:(WKWebView *)wv {
    if (!text.length) return;

    if (self.explainPopover) {
        [self.explainPopover close];
        self.explainPopover = nil;
    }

    HannaExplainBubbleController *vc = [[HannaExplainBubbleController alloc] initWithSelectedText:text];

    NSPopover *popover = [[NSPopover alloc] init];
    popover.contentViewController = vc;
    popover.behavior = NSPopoverBehaviorTransient;
    popover.animates = YES;
    popover.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    self.explainPopover = popover;

    __weak typeof(popover) weakPopover = popover;
    vc.onClose = ^{
        [weakPopover close];
    };

    // Show popover pointing to selection rect on webView
    [popover showRelativeToRect:rect ofView:wv preferredEdge:NSRectEdgeMaxY];

    // Secret Easter Egg check (shared with address-bar search)
    BOOL isSecret = SaturnIsSecretImageQuery(text);

    if (isSecret) {
        NSString *secretURL = SaturnSecretImageURL();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [vc showSecretImageURL:secretURL caption:@"✨ Here is my favorite image! 🪐"];
        });
        return;
    }

    // Query Zarah
    NSString *prompt = [NSString stringWithFormat:@"Please explain the following highlighted text clearly and concisely using formatting/markdown where helpful (bold terms, bullet points if multiple points):\n\n\"%@\"", text];
    NSString *context = [NSString stringWithFormat:@"Current Page: %@\nURL: %@", wv.title ?: @"", wv.URL.absoluteString ?: @""];

    [[HannaClient shared] sendMessage:prompt history:@[] browserContext:context completion:^(NSString *reply, NSError *error) {
        if (error) {
            NSString *msg = error.localizedDescription ?: @"Could not generate explanation.";
            [vc showExplanation:msg isError:YES];
        } else {
            [vc showExplanation:reply isError:NO];
        }
    }];
}

#pragma mark - Saturn Shield Popover & State
- (void)showShieldPopover:(id)sender {
    if (self.shieldPopover) {
        [self.shieldPopover close];
        self.shieldPopover = nil;
    }

    NSString *host = self.webView.URL.host ?: @"This Page";
    SaturnShieldPopoverController *vc = [[SaturnShieldPopoverController alloc] initWithHost:host webView:self.webView];

    NSPopover *popover = [[NSPopover alloc] init];
    popover.contentViewController = vc;
    popover.behavior = NSPopoverBehaviorTransient;
    popover.animates = YES;
    popover.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    self.shieldPopover = popover;

    __weak typeof(self) weakSelf = self;
    vc.onToggleShield = ^(BOOL enabled) {
        (void)enabled;
        [weakSelf updateShieldButtonState];
    };

    [popover showRelativeToRect:self.shieldButton.bounds ofView:self.shieldButton preferredEdge:NSRectEdgeMaxY];
}

- (void)updateShieldButtonState {
    NSString *host = self.webView.URL.host;
    BOOL enabled = [[SaturnShield shared] isShieldEnabledForHost:host];
    NSInteger count = [[SaturnShield shared] blockedCountForWebView:self.webView];

    self.shieldButton.image = Y_symbol(enabled ? @"checkmark.shield.fill" : @"shield.slash", 14, NSFontWeightMedium);
    if (enabled) {
        self.shieldButton.contentTintColor = Y_positive();
        if (count > 0) {
            self.shieldButton.toolTip = [NSString stringWithFormat:@"Saturn Shield: %ld ads & trackers blocked", (long)count];
        } else {
            self.shieldButton.toolTip = @"Saturn Shield Active";
        }
    } else {
        self.shieldButton.contentTintColor = Y_muted2();
        self.shieldButton.toolTip = @"Saturn Shield Paused for this site";
    }
}

#pragma mark - Saturn Voice Agent Delegate

- (void)hannaSetVoiceVisualState:(int)state {
    NSColor *bg = Y_soft(), *tint = Y_ink();
    if (state == 1) { bg = Y_negative(); tint = [NSColor whiteColor]; }
    else if (state == 2) { bg = Y_blue(); tint = [NSColor whiteColor]; }
    else if (state == 3) { bg = Y_positive(); tint = [NSColor whiteColor]; }
    for (NSButton *b in @[self.hannaVoiceButton, self.hannaHeaderVoiceButton]) {
        b.layer.backgroundColor = bg.CGColor;
        b.contentTintColor = tint;
    }
}

- (void)toggleVoiceAgent:(id)sender {
    (void)sender;
    SaturnVoiceAgent *agent = [SaturnVoiceAgent shared];
    agent.delegate = self;

    if (agent.isListening || agent.isSpeaking) {
        [agent cancel];
        self.hannaVoiceHUD.hidden = YES;
        [self hannaSetVoiceVisualState:0];
        return;
    }

    if (!self.aiSidebarVisible) {
        [self toggleAISidebar];
    }

    self.hannaVoiceHUD.hidden = NO;
    self.hannaVoiceStatusLabel.stringValue = @"● Initializing mic & glm-5.3-flash…";
    self.hannaVoiceTranscriptLabel.stringValue = @"Say something to Zarah…";
    [self hannaSetVoiceVisualState:1];

    [self getHannaBrowserContextWithCompletion:^(NSString *context) {
        [[SaturnVoiceAgent shared] startListeningWithBrowserContext:context];
    }];
}

- (void)voiceAgentDidChangeState:(SaturnVoiceAgentState)state statusMessage:(NSString *)status {
    self.hannaVoiceStatusLabel.stringValue = [NSString stringWithFormat:@"● %@", status ?: @"Voice Active"];
    if (state == SaturnVoiceAgentStateIdle) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx){
            ctx.duration = 0.25;
            self.hannaVoiceHUD.animator.alphaValue = 0;
        } completionHandler:^{
            self.hannaVoiceHUD.hidden = YES;
            self.hannaVoiceHUD.alphaValue = 1.0;
        }];
        [self hannaSetVoiceVisualState:0];
    } else if (state == SaturnVoiceAgentStateListening) {
        self.hannaVoiceHUD.hidden = NO;
        self.hannaVoiceHUD.alphaValue = 1.0;
        [self hannaSetVoiceVisualState:1];
    } else if (state == SaturnVoiceAgentStateProcessing) {
        [self hannaSetVoiceVisualState:2];
    } else if (state == SaturnVoiceAgentStateSpeaking) {
        [self hannaSetVoiceVisualState:3];
    }
}

- (void)voiceAgentDidUpdateLiveTranscript:(NSString *)transcript {
    if (transcript.length) {
        self.hannaVoiceTranscriptLabel.stringValue = [NSString stringWithFormat:@"“%@”", transcript];
    }
}

- (void)voiceAgentDidUpdateAudioLevel:(CGFloat)level {
    NSArray<NSNumber *> *multipliers = @[@0.6, @1.0, @1.4, @1.0, @0.7];
    for (NSInteger i = 0; i < (NSInteger)self.hannaVoiceWaveBars.count; i++) {
        NSView *bar = self.hannaVoiceWaveBars[i];
        CGFloat mult = [multipliers[i] doubleValue];
        CGFloat h = MAX(4.0, MIN(30.0, level * 28.0 * mult + (arc4random_uniform(5))));
        NSRect f = bar.frame;
        f.origin.y = (34.0 - h) / 2.0;
        f.size.height = h;
        bar.frame = f;
    }
}

- (void)voiceAgentDidFinishWithUserText:(NSString *)userText replyText:(NSString *)replyText {
    if (userText.length) {
        [self appendHannaMessage:userText from:@"user"];
        [self.hannaHistory addObject:@{@"role": @"user", @"content": userText}];
    }
    if (replyText.length) {
        [self appendHannaMessage:replyText from:@"hanna"];
        [self.hannaHistory addObject:@{@"role": @"assistant", @"content": replyText}];
    }
}

- (void)voiceAgentDidFailWithError:(NSError *)error {
    self.hannaVoiceStatusLabel.stringValue = [NSString stringWithFormat:@"● %@", error.localizedDescription];
}

@end
