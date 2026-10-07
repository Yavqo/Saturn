#import "YavqoTheme.h"
#import "SettingsWindow.h"
#import "SaturnImporter.h"
#import "Settings.h"
#import "SaturnDefaultBrowser.h"
#import "SaturnAppDelegate.h"

// Settings: search engine (applies as soon as you pick one), default browser, and a full reset.

static const CGFloat kW = 560, kH = 800, kPad = 28, kCardPad = 22;

static NSView *SettingsCard(void) {
    NSView *v = [[NSView alloc] initWithFrame:NSZeroRect];
    v.wantsLayer = YES;
    v.layer.cornerRadius = 24;
    v.layer.backgroundColor = Y_soft().CGColor;
    return v;
}
static NSTextField *SettingsLabel(NSString *text, CGFloat size, NSFontWeight weight, NSColor *color) {
    NSTextField *l = [NSTextField labelWithString:text];
    l.font = [NSFont systemFontOfSize:size weight:weight];
    l.textColor = color;
    return l;
}

@interface SettingsWindow () <NSTextFieldDelegate>
@property (nonatomic, strong) NSView *engineCard, *browserCard, *importCard, *resetCard;
@property (nonatomic, strong) NSTextField *importTitle, *importDesc;
@property (nonatomic, strong) NSButton *importButton;
@property (nonatomic, strong) NSTextField *engineTitle, *engineDesc, *previewLabel, *errorLabel;
@property (nonatomic, strong) NSPopUpButton *enginePopup;
@property (nonatomic, strong) NSView *customBox;
@property (nonatomic, strong) NSTextField *customField;
@property (nonatomic, strong) NSTextField *browserTitle, *browserStatus;
@property (nonatomic, strong) NSImageView *browserIcon;
@property (nonatomic, strong) NSButton *browserButton;
@property (nonatomic, strong) NSTextField *resetTitle, *resetDesc, *versionLabel;
@property (nonatomic, strong) NSButton *resetButton, *doneButton;
@end

@implementation SettingsWindow

+ (instancetype)shared {
    static SettingsWindow *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[SettingsWindow alloc] initWithSettingsUI]; });
    return s;
}

- (instancetype)initWithSettingsUI {
    self = [super initWithContentRect:NSMakeRect(0, 0, kW, kH) styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable) backing:NSBackingStoreBuffered defer:NO];
    if (self) {
        self.title = @"Settings";
        self.releasedWhenClosed = NO;
        self.backgroundColor = [NSColor whiteColor];
        self.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
        [self buildUI];
        [self loadCurrent];
    }
    return self;
}

#pragma mark Build

- (void)buildUI {
    NSView *c = self.contentView;
    c.wantsLayer = YES;
    c.layer.backgroundColor = [NSColor whiteColor].CGColor;

    // --- Search engine
    _engineCard = SettingsCard();
    _engineTitle = SettingsLabel(@"Search engine", 17, NSFontWeightMedium, Y_ink());
    _engineDesc = SettingsLabel(@"Used when you type a search in the address bar.", 13, NSFontWeightRegular, Y_muted());
    _enginePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (SaturnSearchEngineInfo *info in SaturnSearchEngineInfo.allEngines) {
        [_enginePopup addItemWithTitle:info.name];
        NSMenuItem *item = [_enginePopup itemWithTitle:info.name];
        if (info.iconSymbol.length) {
            NSImage *img = [NSImage imageWithSystemSymbolName:info.iconSymbol accessibilityDescription:nil];
            if (img) { img.size = NSMakeSize(14, 14); item.image = img; }
        }
    }
    _enginePopup.target = self;
    _enginePopup.action = @selector(engineChanged:);
    _enginePopup.font = [NSFont systemFontOfSize:14];

    _customBox = [[NSView alloc] initWithFrame:NSZeroRect];
    _customBox.wantsLayer = YES;
    _customBox.layer.cornerRadius = 12;
    _customBox.layer.backgroundColor = [NSColor whiteColor].CGColor;
    _customBox.layer.borderColor = Y_border().CGColor;
    _customBox.layer.borderWidth = 1;
    _customField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _customField.bezeled = NO;
    _customField.drawsBackground = NO;
    _customField.focusRingType = NSFocusRingTypeNone;
    _customField.font = [NSFont systemFontOfSize:13];
    _customField.textColor = Y_ink();
    _customField.placeholderAttributedString = [[NSAttributedString alloc] initWithString:@"https://example.com/search?q=%s" attributes:@{NSForegroundColorAttributeName: Y_muted2(), NSFontAttributeName: [NSFont systemFontOfSize:13]}];
    _customField.delegate = self;
    [_customBox addSubview:_customField];

    _errorLabel = SettingsLabel(@"", 12, NSFontWeightRegular, Y_negative());
    _previewLabel = SettingsLabel(@"", 12, NSFontWeightRegular, Y_muted());
    _previewLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    for (NSView *v in @[_engineTitle, _engineDesc, _enginePopup, _customBox, _errorLabel, _previewLabel]) [_engineCard addSubview:v];
    [c addSubview:_engineCard];

    // --- Default browser
    _browserCard = SettingsCard();
    _browserIcon = [[NSImageView alloc] initWithFrame:NSZeroRect];
    _browserIcon.contentTintColor = Y_blue();
    _browserTitle = SettingsLabel(@"Default browser", 17, NSFontWeightMedium, Y_ink());
    _browserStatus = SettingsLabel(@"", 13, NSFontWeightRegular, Y_muted());
    _browserButton = [NSButton buttonWithTitle:@"Make default" target:self action:@selector(makeDefaultBrowser:)];
    _browserButton.bezelStyle = NSBezelStyleRounded;
    _browserButton.frame = NSMakeRect(0, 0, 140, 40);
    YT_pill(_browserButton, YES);
    for (NSView *v in @[_browserIcon, _browserTitle, _browserStatus, _browserButton]) [_browserCard addSubview:v];
    [c addSubview:_browserCard];

    // --- Import
    _importCard = SettingsCard();
    _importTitle = SettingsLabel(@"Import from another browser", 17, NSFontWeightMedium, Y_ink());
    _importDesc = SettingsLabel(@"Bring in bookmarks and history from Chrome, Safari, Firefox and others.", 13, NSFontWeightRegular, Y_muted());
    _importButton = [NSButton buttonWithTitle:@"Import…" target:self action:@selector(importFromBrowser:)];
    _importButton.bezelStyle = NSBezelStyleRounded;
    _importButton.frame = NSMakeRect(0, 0, 140, 40);
    YT_pill(_importButton, NO);
    for (NSView *v in @[_importTitle, _importDesc, _importButton]) [_importCard addSubview:v];
    [c addSubview:_importCard];

    // --- Reset
    _resetCard = SettingsCard();
    _resetTitle = SettingsLabel(@"Reset Saturn", 17, NSFontWeightMedium, Y_ink());
    _resetDesc = [NSTextField wrappingLabelWithString:@"Clears your history, bookmarks, cookies and site data, saved settings and your sign-in, then starts setup again. Files you downloaded are kept."];
    _resetDesc.font = [NSFont systemFontOfSize:13];
    _resetDesc.textColor = Y_muted();
    _resetButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    _resetButton.bordered = NO;
    _resetButton.wantsLayer = YES;
    _resetButton.layer.cornerRadius = 22;
    _resetButton.layer.backgroundColor = [NSColor whiteColor].CGColor;
    _resetButton.layer.borderColor = Y_negative().CGColor;
    _resetButton.layer.borderWidth = 2;
    NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
    ps.alignment = NSTextAlignmentCenter;
    _resetButton.attributedTitle = [[NSAttributedString alloc] initWithString:@"Reset Saturn…" attributes:@{NSForegroundColorAttributeName: Y_negative(), NSFontAttributeName: [NSFont systemFontOfSize:14 weight:NSFontWeightBold], NSParagraphStyleAttributeName: ps}];
    _resetButton.target = self;
    _resetButton.action = @selector(resetTapped:);
    for (NSView *v in @[_resetTitle, _resetDesc, _resetButton]) [_resetCard addSubview:v];
    [c addSubview:_resetCard];

    // --- Footer
    NSString *ver = [NSBundle mainBundle].infoDictionary[@"CFBundleShortVersionString"] ?: @"";
    _versionLabel = SettingsLabel([NSString stringWithFormat:@"Saturn %@", ver], 12, NSFontWeightRegular, Y_muted());
    [c addSubview:_versionLabel];
    _doneButton = [NSButton buttonWithTitle:@"Done" target:self action:@selector(close:)];
    _doneButton.bezelStyle = NSBezelStyleRounded;
    _doneButton.frame = NSMakeRect(0, 0, 120, 40);
    YT_pill(_doneButton, YES);
    _doneButton.keyEquivalent = @"\r";
    [c addSubview:_doneButton];

    // The macOS confirmation dialog takes focus away; refresh when we get it back
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshDefaultBrowserRow) name:NSWindowDidBecomeKeyNotification object:self];
    [self relayout];
}

// Cards stack top-down; the search card grows when "Custom" is chosen or an error is showing.
- (void)relayout {
    NSView *c = self.contentView;
    const CGFloat cw = kW - 2 * kPad, inner = cw - 2 * kCardPad;
    BOOL custom = !_customBox.hidden, err = _errorLabel.stringValue.length > 0;

    CGFloat y = c.bounds.size.height - 32;
    NSTextField *title = [c viewWithTag:900];
    if (!title) {
        title = SettingsLabel(@"Settings", 28, NSFontWeightMedium, Y_ink());
        title.tag = 900;
        [c addSubview:title];
    }
    title.frame = NSMakeRect(kPad, y - 36, cw, 36);
    y -= 36 + 22;

    // Search engine card
    CGFloat h = kCardPad + 22 + 4 + 18 + 14 + 32 + (custom ? 10 + 40 : 0) + (err ? 8 + 16 : 0) + 12 + 16 + kCardPad;
    _engineCard.frame = NSMakeRect(kPad, y - h, cw, h);
    CGFloat iy = h - kCardPad;
    _engineTitle.frame = NSMakeRect(kCardPad, iy - 22, inner, 22); iy -= 22 + 4;
    _engineDesc.frame = NSMakeRect(kCardPad, iy - 18, inner, 18); iy -= 18 + 14;
    _enginePopup.frame = NSMakeRect(kCardPad - 4, iy - 32, inner + 8, 32); iy -= 32;
    if (custom) {
        iy -= 10;
        _customBox.frame = NSMakeRect(kCardPad, iy - 40, inner, 40);
        _customField.frame = NSMakeRect(14, 10, inner - 28, 20);
        iy -= 40;
    }
    if (err) { iy -= 8; _errorLabel.frame = NSMakeRect(kCardPad, iy - 16, inner, 16); iy -= 16; }
    iy -= 12;
    _previewLabel.frame = NSMakeRect(kCardPad, iy - 16, inner, 16);
    y -= h + 14;

    // Default browser card
    h = 84;
    _browserCard.frame = NSMakeRect(kPad, y - h, cw, h);
    _browserIcon.frame = NSMakeRect(kCardPad, (h - 24) / 2, 24, 24);
    _browserTitle.frame = NSMakeRect(kCardPad + 38, h / 2 + 2, inner - 38 - 150, 22);
    _browserStatus.frame = NSMakeRect(kCardPad + 38, h / 2 - 20, inner - 38 - 150, 18);
    _browserButton.frame = NSMakeRect(cw - kCardPad - 140, (h - 40) / 2, 140, 40);
    y -= h + 14;

    // Import card
    h = 84;
    _importCard.frame = NSMakeRect(kPad, y - h, cw, h);
    _importTitle.frame = NSMakeRect(kCardPad, h / 2 + 2, inner - 150, 22);
    _importDesc.frame = NSMakeRect(kCardPad, h / 2 - 20, inner - 150, 18);
    _importButton.frame = NSMakeRect(cw - kCardPad - 120, (h - 40) / 2, 120, 40);
    y -= h + 14;

    // Reset card
    h = kCardPad + 22 + 6 + 52 + 16 + 44 + kCardPad;
    _resetCard.frame = NSMakeRect(kPad, y - h, cw, h);
    CGFloat ry = h - kCardPad;
    _resetTitle.frame = NSMakeRect(kCardPad, ry - 22, inner, 22); ry -= 22 + 6;
    _resetDesc.frame = NSMakeRect(kCardPad, ry - 52, inner, 52); ry -= 52 + 16;
    _resetButton.frame = NSMakeRect(kCardPad, ry - 44, 170, 44);

    _versionLabel.frame = NSMakeRect(kPad, 38, 200, 16);
    _doneButton.frame = NSMakeRect(kW - kPad - 120, 28, 120, 40);
}

#pragma mark Import

- (void)importFromBrowser:(id)sender {
    (void)sender;
    [SaturnImporter presentImportDialogFromWindow:self];
}

#pragma mark Default browser

- (void)refreshDefaultBrowserRow {
    BOOL isDefault = [SaturnDefaultBrowser isDefault];
    NSString *other = [SaturnDefaultBrowser currentDefaultName];
    _browserStatus.stringValue = isDefault ? @"Saturn opens the links you click in other apps."
                                           : (other.length ? [NSString stringWithFormat:@"%@ is your default browser.", other] : @"Saturn isn't your default browser.");
    NSImage *img = [NSImage imageWithSystemSymbolName:isDefault ? @"checkmark.circle.fill" : @"globe" accessibilityDescription:nil];
    _browserIcon.image = img;
    _browserButton.hidden = isDefault;
}

- (void)makeDefaultBrowser:(id)sender {
    (void)sender;
    [SaturnDefaultBrowser makeDefaultWithCompletion:^(BOOL now, NSError *error) { (void)now; (void)error; [self refreshDefaultBrowserRow]; }];
}

#pragma mark Search engine

- (void)loadCurrent {
    SaturnSettings *s = SaturnSettings.shared;
    NSInteger idx = 0;
    NSArray<SaturnSearchEngineInfo *> *all = SaturnSearchEngineInfo.allEngines;
    for (NSInteger i = 0; i < (NSInteger)all.count; i++) if (all[i].engine == s.defaultEngine) { idx = i; break; }
    [_enginePopup selectItemAtIndex:idx];
    _customField.stringValue = s.customTemplate ?: @"";
    _customBox.hidden = (s.defaultEngine != SaturnSearchEngineCustom);
    _errorLabel.stringValue = @"";
    [self updatePreview];
    [self refreshDefaultBrowserRow];
    [self relayout];
}

- (SaturnSearchEngineInfo *)selectedInfo { return SaturnSearchEngineInfo.allEngines[_enginePopup.indexOfSelectedItem]; }

- (void)updatePreview {
    SaturnSearchEngineInfo *info = [self selectedInfo];
    NSString *tmpl = info.templateURL;
    if (info.engine == SaturnSearchEngineCustom) tmpl = _customField.stringValue.length ? _customField.stringValue : @"https://example.com/search?q=%s";
    NSString *sample = [[tmpl stringByReplacingOccurrencesOfString:@"%s" withString:@"hello%20saturn"] stringByReplacingOccurrencesOfString:@"%q" withString:@"hello%20saturn"];
    _previewLabel.stringValue = [@"Example: " stringByAppendingString:sample];
}

// Picking an engine applies it straight away. A custom address is only saved once it is valid.
- (void)applyEngine {
    SaturnSearchEngineInfo *info = [self selectedInfo];
    SaturnSettings *s = SaturnSettings.shared;
    NSString *error = @"";
    if (info.engine == SaturnSearchEngineCustom) {
        NSString *t = [_customField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!t.length) error = @"Enter a web address for your search.";
        else if (![t containsString:@"%s"] && ![t containsString:@"%q"]) error = @"Put %s where your search should go, like https://example.com/search?q=%s";
        if (error.length) { _errorLabel.stringValue = error; [self relayout]; return; }
        s.customTemplate = t;
    }
    s.defaultEngine = info.engine;
    [s save];
    if (_errorLabel.stringValue.length) { _errorLabel.stringValue = @""; [self relayout]; }
}

- (void)engineChanged:(id)sender {
    (void)sender;
    _customBox.hidden = ([self selectedInfo].engine != SaturnSearchEngineCustom);
    _errorLabel.stringValue = @"";
    [self updatePreview];
    [self relayout];
    if (!_customBox.hidden) { [self makeFirstResponder:_customField]; }
    [self applyEngine];
}

- (void)controlTextDidChange:(NSNotification *)obj {
    if (obj.object != _customField) return;
    [self updatePreview];
    [self applyEngine];
}

#pragma mark Reset

- (void)resetTapped:(id)sender {
    (void)sender;
    NSAlert *a = [[NSAlert alloc] init];
    a.alertStyle = NSAlertStyleWarning;
    a.messageText = @"Reset Saturn?";
    a.informativeText = @"This clears your history, bookmarks, cookies and site data, saved settings and your sign-in, closes all windows, and starts setup again. Files you downloaded are not deleted. It can't be undone.";
    NSButton *go = [a addButtonWithTitle:@"Reset Saturn"];
    go.hasDestructiveAction = YES;
    [a addButtonWithTitle:@"Cancel"];
    if ([a runModal] != NSAlertFirstButtonReturn) return;
    [self close:nil];
    [(SaturnAppDelegate *)NSApp.delegate resetBrowserAndRestartSetup];
}

#pragma mark Showing

- (void)showForWindow:(NSWindow *)parent {
    [self loadCurrent];
    if (parent) [parent beginSheet:self completionHandler:nil];
    else { [self center]; [self makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES]; }
}

- (void)showStandalone {
    [self loadCurrent];
    [self center];
    [self makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (IBAction)close:(id)sender {
    (void)sender;
    if (self.sheetParent) [self.sheetParent endSheet:self];
    else [self orderOut:nil];
}

@end
