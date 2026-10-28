#import "SaturnVaultWindow.h"
#import "SaturnVault.h"
#import "YavqoTheme.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// Yavqo Vault UI: the gate (create / unlock) and the manager window. Flat, pills, 12px fields, one blue.

static NSColor *VWarning(void) { return YT_rgb(0xF7, 0xB9, 0x28, 1); }

@interface VFlippedView : NSView
@end
@implementation VFlippedView
- (BOOL)isFlipped { return YES; }
@end

static NSTextField *VLabel(NSString *text, CGFloat size, NSFontWeight weight, NSColor *color) {
    NSTextField *l = [NSTextField labelWithString:text];
    l.font = [NSFont systemFontOfSize:size weight:weight];
    l.textColor = color;
    return l;
}

// A 44px rounded field: container with hairline border, the text field inset inside it.
static NSView *VFieldBox(NSTextField *f, NSRect frame, NSString *placeholder) {
    NSView *box = [[VFlippedView alloc] initWithFrame:frame];
    box.wantsLayer = YES;
    box.layer.cornerRadius = 12;
    box.layer.borderWidth = 1;
    box.layer.borderColor = YT_rgb(10, 19, 23, 0.45).CGColor;
    box.layer.backgroundColor = [NSColor whiteColor].CGColor;
    f.frame = NSMakeRect(14, (frame.size.height - 20) / 2, frame.size.width - 28, 20);
    f.bezeled = NO;
    f.drawsBackground = NO;
    f.focusRingType = NSFocusRingTypeNone;
    f.font = [NSFont systemFontOfSize:14];
    f.textColor = Y_ink();
    f.usesSingleLineMode = YES;
    f.cell.scrollable = YES;
    if (placeholder.length) ((NSTextFieldCell *)f.cell).placeholderAttributedString = [[NSAttributedString alloc] initWithString:placeholder attributes:@{NSForegroundColorAttributeName: Y_muted2(), NSFontAttributeName: [NSFont systemFontOfSize:14]}];
    [box addSubview:f];
    return box;
}

static NSButton *VPill(NSString *title, BOOL primary, id target, SEL action, NSRect frame) {
    NSButton *b = [NSButton buttonWithTitle:title target:target action:action];
    b.frame = frame;
    YT_pill(b, primary);
    return b;
}

static NSButton *VIconButton(NSString *symbol, NSString *tip, id target, SEL action, NSRect frame) {
    NSButton *b = [NSButton buttonWithTitle:@"" target:target action:action];
    b.frame = frame;
    b.bordered = NO;
    b.wantsLayer = YES;
    b.layer.cornerRadius = frame.size.height / 2;
    b.layer.backgroundColor = Y_soft().CGColor;
    NSImage *img = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:tip];
    img = [img imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:14 weight:NSFontWeightMedium]] ?: img;
    b.image = img;
    b.imagePosition = NSImageOnly;
    b.contentTintColor = Y_ink();
    b.toolTip = tip;
    [b setAccessibilityLabel:tip];
    return b;
}

static void VSetStrength(NSArray<NSView *> *segments, NSTextField *label, NSString *password) {
    if (!password.length) {
        for (NSView *s in segments) s.layer.backgroundColor = Y_soft().CGColor;
        label.stringValue = @"";
        return;
    }
    NSString *name = nil;
    NSInteger score = [SaturnVault strengthOfPassword:password label:&name];
    NSColor *c = score <= 1 ? Y_negative() : score == 2 ? VWarning() : Y_positive();
    for (NSUInteger i = 0; i < segments.count; i++) segments[i].layer.backgroundColor = (i < (NSUInteger)MAX(score, 1) ? c : Y_soft()).CGColor;
    label.stringValue = name ?: @"";
}

static NSArray<NSView *> *VStrengthSegments(NSView *parent, CGFloat x, CGFloat y, CGFloat totalW) {
    NSMutableArray *segs = [NSMutableArray array];
    CGFloat w = (totalW - 3 * 6) / 4;
    for (int i = 0; i < 4; i++) {
        NSView *s = [[NSView alloc] initWithFrame:NSMakeRect(x + i * (w + 6), y, w, 4)];
        s.wantsLayer = YES;
        s.layer.cornerRadius = 2;
        s.layer.backgroundColor = Y_soft().CGColor;
        [parent addSubview:s];
        [segs addObject:s];
    }
    return segs;
}

#pragma mark - Gate

@interface SaturnVaultGate () <NSTextFieldDelegate>
@end

@implementation SaturnVaultGate {
    CGFloat _w;
    NSString *_message;
    NSSecureTextField *_pw, *_confirm;
    NSTextField *_error;
    NSButton *_go;
    NSArray<NSView *> *_segs;
    NSTextField *_strengthLabel;
    BOOL _creating, _working;
    CGFloat _height;
}

- (BOOL)isFlipped { return YES; }
- (CGFloat)height { return _height; }

- (instancetype)initWithWidth:(CGFloat)width message:(NSString *)message {
    self = [super initWithFrame:NSMakeRect(0, 0, width, 100)];
    if (!self) return nil;
    _w = width; _message = [message copy];
    [self rebuild];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(vaultChanged:) name:SaturnVaultChangedNotification object:nil];
    return self;
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)vaultChanged:(NSNotification *)n {
    (void)n;
    BOOL creating = ![SaturnVault shared].exists;
    if (creating != _creating) [self rebuild];
}

- (void)rebuild {
    for (NSView *v in [self.subviews copy]) [v removeFromSuperview];
    _creating = ![SaturnVault shared].exists;
    CGFloat y = 0;
    NSString *msg = _message.length ? _message : (_creating ? @"Create a master password to start your vault." : @"Enter your master password.");
    NSTextField *m = [NSTextField wrappingLabelWithString:msg];
    m.font = [NSFont systemFontOfSize:14]; m.textColor = Y_muted();
    m.frame = NSMakeRect(0, y, _w, 40);
    NSSize fit = [m.cell cellSizeForBounds:NSMakeRect(0, 0, _w, 1000)];
    m.frame = NSMakeRect(0, y, _w, ceil(fit.height));
    [self addSubview:m];
    y += NSHeight(m.frame) + 14;

    _pw = [[NSSecureTextField alloc] init];
    _pw.delegate = self; _pw.target = self; _pw.action = @selector(submit:);
    [self addSubview:VFieldBox(_pw, NSMakeRect(0, y, _w, 44), _creating ? @"Master password" : @"Master password")];
    y += 44 + 10;

    _confirm = nil; _segs = nil; _strengthLabel = nil;
    if (_creating) {
        _confirm = [[NSSecureTextField alloc] init];
        _confirm.delegate = self; _confirm.target = self; _confirm.action = @selector(submit:);
        [self addSubview:VFieldBox(_confirm, NSMakeRect(0, y, _w, 44), @"Confirm master password")];
        y += 44 + 12;
        _segs = VStrengthSegments(self, 0, y, _w - 90);
        _strengthLabel = VLabel(@"", 12, NSFontWeightRegular, Y_muted());
        _strengthLabel.frame = NSMakeRect(_w - 80, y - 7, 80, 16);
        _strengthLabel.alignment = NSTextAlignmentRight;
        [self addSubview:_strengthLabel];
        y += 4 + 12;
        NSTextField *note = [NSTextField wrappingLabelWithString:@"At least 8 characters; a few random words works well. Your vault stays on this Mac and Yavqo cannot recover this password, so keep it safe."];
        note.font = [NSFont systemFontOfSize:12]; note.textColor = Y_muted();
        NSSize nf = [note.cell cellSizeForBounds:NSMakeRect(0, 0, _w, 1000)];
        note.frame = NSMakeRect(0, y, _w, ceil(nf.height));
        [self addSubview:note];
        y += NSHeight(note.frame) + 12;
    }

    _error = VLabel(@"", 12, NSFontWeightRegular, Y_negative());
    _error.frame = NSMakeRect(0, y, _w, 16);
    [self addSubview:_error];
    y += 20;

    _go = VPill(_creating ? @"Create vault" : @"Unlock", YES, self, @selector(submit:), NSMakeRect(0, y, _w, 44));
    _go.keyEquivalent = @"\r";
    [self addSubview:_go];
    y += 44;
    _height = y;
    self.frame = NSMakeRect(NSMinX(self.frame), NSMinY(self.frame), _w, _height);
}

- (void)focus { [self.window makeFirstResponder:_pw]; }

- (void)controlTextDidChange:(NSNotification *)n {
    if (n.object == _pw && _creating && _segs) VSetStrength(_segs, _strengthLabel, _pw.stringValue);
    _error.stringValue = @"";
}

- (void)setWorking:(BOOL)w {
    _working = w;
    _go.enabled = !w;
    NSString *t = w ? (_creating ? @"Creating…" : @"Unlocking…") : (_creating ? @"Create vault" : @"Unlock");
    _go.title = t;
    YT_pill(_go, YES);
}

- (void)submit:(id)sender {
    (void)sender;
    if (_working) return;
    NSString *pw = _pw.stringValue;
    __weak typeof(self) weakSelf = self;
    if (_creating) {
        if (pw.length < 8) { _error.stringValue = @"Use at least 8 characters."; return; }
        if (![pw isEqualToString:_confirm.stringValue]) { _error.stringValue = @"The two passwords don't match."; return; }
        [self setWorking:YES];
        [[SaturnVault shared] createWithMasterPassword:pw completion:^(BOOL ok) {
            __strong typeof(weakSelf) s = weakSelf; if (!s) return;
            [s setWorking:NO];
            if (!ok) { s->_error.stringValue = @"Couldn't create the vault."; return; }
            if (s.onUnlocked) s.onUnlocked();
        }];
    } else {
        if (!pw.length) { _error.stringValue = @"Enter your master password."; return; }
        [self setWorking:YES];
        [[SaturnVault shared] unlockWithMasterPassword:pw completion:^(BOOL ok) {
            __strong typeof(weakSelf) s = weakSelf; if (!s) return;
            [s setWorking:NO];
            if (!ok) { s->_error.stringValue = @"That isn't the right master password."; s->_pw.stringValue = @""; [s focus]; return; }
            if (s.onUnlocked) s.onUnlocked();
        }];
    }
}
@end

#pragma mark - Manager window

static const CGFloat kWinW = 900, kWinH = 640, kSideW = 300;

@interface SaturnVaultWindow () <NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSTextViewDelegate, NSSearchFieldDelegate>
@end

@implementation SaturnVaultWindow {
    NSView *_gateScreen, *_managerScreen;
    SaturnVaultGate *_gate;
    // manager
    NSSearchField *_search;
    NSTableView *_table;
    NSArray<NSDictionary *> *_rows;
    NSView *_detail, *_emptyDetail, *_form;
    NSTextField *_formTitle, *_name, *_site, *_user;
    NSSecureTextField *_passSecure;
    NSTextField *_passPlain, *_strengthLabel, *_notice, *_status;
    NSTextView *_notes;
    NSButton *_reveal, *_save, *_delete, *_breach;
    NSArray<NSView *> *_segs;
    NSString *_currentID;
    BOOL _loading;
}

+ (instancetype)shared {
    static SaturnVaultWindow *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[SaturnVaultWindow alloc] initVault]; });
    return s;
}

- (instancetype)initVault {
    self = [super initWithContentRect:NSMakeRect(0, 0, kWinW, kWinH) styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable) backing:NSBackingStoreBuffered defer:NO];
    if (!self) return nil;
    self.title = @"Yavqo Vault";
    self.releasedWhenClosed = NO;
    self.backgroundColor = [NSColor whiteColor];
    self.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    NSView *c = [[VFlippedView alloc] initWithFrame:NSMakeRect(0, 0, kWinW, kWinH)];
    c.wantsLayer = YES;
    c.layer.backgroundColor = [NSColor whiteColor].CGColor;
    self.contentView = c;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(vaultChanged:) name:SaturnVaultChangedNotification object:nil];
    return self;
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)showVault {
    [self refreshScreens];
    if (!self.isVisible) [self center];
    [NSApp activateIgnoringOtherApps:YES];
    [self makeKeyAndOrderFront:nil];
    if (![SaturnVault shared].unlocked) [_gate focus];
}

- (void)showNewLoginWithURL:(NSString *)url {
    [self showVault];
    if (![SaturnVault shared].unlocked) return;
    [self startNewLoginWithURL:url];
}

- (void)vaultChanged:(NSNotification *)n {
    (void)n;
    BOOL wantManager = [SaturnVault shared].unlocked;
    BOOL haveManager = _managerScreen && _managerScreen.superview;
    if (wantManager != haveManager || !_gateScreen) [self refreshScreens];
    else [self reloadRowsKeepingSelection];
}

- (void)refreshScreens {
    BOOL unlocked = [SaturnVault shared].unlocked;
    [_gateScreen removeFromSuperview];
    [_managerScreen removeFromSuperview];
    if (unlocked) {
        if (!_managerScreen) [self buildManager];
        [self.contentView addSubview:_managerScreen];
        [self reloadRowsKeepingSelection];
        if (!_currentID) [self showEmptyDetail];
    } else {
        [self buildGate];
        [self.contentView addSubview:_gateScreen];
        _managerScreen = nil;   // rebuilt fresh next unlock so no plaintext lingers in controls
        _passSecure.stringValue = @""; _passPlain.stringValue = @"";
        _currentID = nil;
    }
}

#pragma mark Gate screen

- (void)buildGate {
    _gateScreen = [[VFlippedView alloc] initWithFrame:NSMakeRect(0, 0, kWinW, kWinH)];
    CGFloat cw = 360;
    BOOL creating = ![SaturnVault shared].exists;
    NSImageView *icon = [[NSImageView alloc] initWithFrame:NSMakeRect((kWinW - 64) / 2, 120, 64, 64)];
    NSImage *img = [NSImage imageWithSystemSymbolName:@"lock.shield.fill" accessibilityDescription:nil];
    img = [img imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:44 weight:NSFontWeightRegular]] ?: img;
    icon.image = img; icon.contentTintColor = Y_blue();
    [_gateScreen addSubview:icon];
    NSTextField *t = VLabel(@"Yavqo Vault", 28, NSFontWeightLight, Y_ink());
    t.alignment = NSTextAlignmentCenter;
    t.frame = NSMakeRect(0, 196, kWinW, 36);
    [_gateScreen addSubview:t];
    NSTextField *s = VLabel(creating ? @"Your passwords, encrypted on this Mac" : @"Locked", 14, NSFontWeightRegular, Y_muted());
    s.alignment = NSTextAlignmentCenter;
    s.frame = NSMakeRect(0, 236, kWinW, 20);
    [_gateScreen addSubview:s];

    _gate = [[SaturnVaultGate alloc] initWithWidth:cw message:creating ? @"Create a master password to start your vault." : @"Enter your master password to open your logins."];
    _gate.frame = NSMakeRect((kWinW - cw) / 2, 280, cw, _gate.height);
    __weak typeof(self) weakSelf = self;
    _gate.onUnlocked = ^{ [weakSelf refreshScreens]; };
    [_gateScreen addSubview:_gate];
}

#pragma mark Manager screen

- (void)buildManager {
    _managerScreen = [[VFlippedView alloc] initWithFrame:NSMakeRect(0, 0, kWinW, kWinH)];
    NSView *m = _managerScreen;

    NSTextField *title = VLabel(@"Yavqo Vault", 22, NSFontWeightLight, Y_ink());
    title.frame = NSMakeRect(24, 18, 300, 28);
    [m addSubview:title];
    NSButton *lock = VPill(@"Lock", NO, self, @selector(lockTapped:), NSMakeRect(kWinW - 24 - 90, 12, 90, 40));
    [m addSubview:lock];
    NSView *hair = [[NSView alloc] initWithFrame:NSMakeRect(0, 64, kWinW, 1)];
    hair.wantsLayer = YES; hair.layer.backgroundColor = Y_hairline().CGColor;
    [m addSubview:hair];

    // Sidebar
    _search = [[NSSearchField alloc] initWithFrame:NSMakeRect(16, 78, kSideW - 32, 32)];
    _search.placeholderString = @"Search logins";
    _search.delegate = self;
    _search.focusRingType = NSFocusRingTypeNone;
    [m addSubview:_search];

    NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 122, kSideW, kWinH - 122 - 72)];
    sv.hasVerticalScroller = YES; sv.drawsBackground = NO; sv.borderType = NSNoBorder;
    _table = [[NSTableView alloc] initWithFrame:sv.bounds];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"login"];
    col.width = kSideW; col.resizingMask = NSTableColumnAutoresizingMask;
    [_table addTableColumn:col];
    _table.headerView = nil;
    _table.rowHeight = 56;
    _table.intercellSpacing = NSMakeSize(0, 0);
    _table.backgroundColor = [NSColor whiteColor];
    _table.selectionHighlightStyle = NSTableViewSelectionHighlightStyleNone;
    _table.dataSource = self; _table.delegate = self;
    sv.documentView = _table;
    [m addSubview:sv];

    NSView *bottomHair = [[NSView alloc] initWithFrame:NSMakeRect(0, kWinH - 72, kSideW, 1)];
    bottomHair.wantsLayer = YES; bottomHair.layer.backgroundColor = Y_hairline().CGColor;
    [m addSubview:bottomHair];
    [m addSubview:VPill(@"New login", YES, self, @selector(newLoginTapped:), NSMakeRect(16, kWinH - 56, 150, 40))];
    [m addSubview:VPill(@"Import…", NO, self, @selector(importTapped:), NSMakeRect(174, kWinH - 56, 110, 40))];

    NSView *vhair = [[NSView alloc] initWithFrame:NSMakeRect(kSideW, 65, 1, kWinH - 65)];
    vhair.wantsLayer = YES; vhair.layer.backgroundColor = Y_hairline().CGColor;
    [m addSubview:vhair];

    // Detail
    _detail = [[VFlippedView alloc] initWithFrame:NSMakeRect(kSideW + 1, 65, kWinW - kSideW - 1, kWinH - 65)];
    [m addSubview:_detail];
    [self buildEmptyDetail];
    [self buildForm];
}

- (void)buildEmptyDetail {
    NSRect b = _detail.bounds;
    _emptyDetail = [[VFlippedView alloc] initWithFrame:b];
    NSTextField *t = VLabel(@"Select a login or create a new one", 16, NSFontWeightRegular, Y_muted());
    t.alignment = NSTextAlignmentCenter;
    t.frame = NSMakeRect(0, b.size.height / 2 - 24, b.size.width, 22);
    [_emptyDetail addSubview:t];
    NSTextField *u = VLabel(@"Tip: Yavqo Vault fills logins only when you choose, and clears copied passwords after 30 seconds.", 12, NSFontWeightRegular, Y_muted2());
    u.alignment = NSTextAlignmentCenter;
    u.frame = NSMakeRect(0, b.size.height / 2 + 6, b.size.width, 18);
    [_emptyDetail addSubview:u];
    [_detail addSubview:_emptyDetail];
}

- (void)buildForm {
    CGFloat x = 32, fw = 470, bx = x + fw + 8;
    _form = [[VFlippedView alloc] initWithFrame:_detail.bounds];
    _form.hidden = YES;

    _formTitle = VLabel(@"Login", 20, NSFontWeightLight, Y_ink());
    _formTitle.frame = NSMakeRect(x, 18, 400, 26);
    [_form addSubview:_formTitle];

    NSTextField *(^lbl)(NSString *, CGFloat) = ^NSTextField *(NSString *t, CGFloat y) {
        NSTextField *l = VLabel(t, 12, NSFontWeightBold, Y_ink());
        l.frame = NSMakeRect(x, y, 300, 16);
        [self->_form addSubview:l];
        return l;
    };
    lbl(@"Name", 56);
    _name = [[NSTextField alloc] init]; _name.delegate = self;
    [_form addSubview:VFieldBox(_name, NSMakeRect(x, 74, fw, 40), @"For example, Yavqo")];

    lbl(@"Website", 122);
    _site = [[NSTextField alloc] init]; _site.delegate = self;
    [_form addSubview:VFieldBox(_site, NSMakeRect(x, 140, fw, 40), @"https://example.com")];

    lbl(@"Username or email", 188);
    _user = [[NSTextField alloc] init]; _user.delegate = self;
    [_form addSubview:VFieldBox(_user, NSMakeRect(x, 206, fw, 40), @"")];
    [_form addSubview:VIconButton(@"doc.on.doc", @"Copy username", self, @selector(copyUser:), NSMakeRect(bx, 209, 34, 34))];

    lbl(@"Password", 254);
    _passSecure = [[NSSecureTextField alloc] init]; _passSecure.delegate = self;
    _passPlain = [[NSTextField alloc] init]; _passPlain.delegate = self;
    NSView *pbox = VFieldBox(_passSecure, NSMakeRect(x, 272, fw, 40), @"");
    _passPlain.frame = _passSecure.frame;
    _passPlain.bezeled = NO; _passPlain.drawsBackground = NO; _passPlain.focusRingType = NSFocusRingTypeNone;
    _passPlain.font = [NSFont monospacedSystemFontOfSize:14 weight:NSFontWeightRegular];
    _passPlain.textColor = Y_ink(); _passPlain.hidden = YES;
    [pbox addSubview:_passPlain];
    [_form addSubview:pbox];
    _reveal = VIconButton(@"eye", @"Show password", self, @selector(toggleReveal:), NSMakeRect(bx, 275, 34, 34));
    [_form addSubview:_reveal];
    [_form addSubview:VIconButton(@"doc.on.doc", @"Copy password", self, @selector(copyPass:), NSMakeRect(bx + 40, 275, 34, 34))];

    _segs = VStrengthSegments(_form, x, 326, fw - 150);
    _strengthLabel = VLabel(@"", 12, NSFontWeightRegular, Y_muted());
    _strengthLabel.frame = NSMakeRect(x + fw - 140, 320, 70, 16);
    [_form addSubview:_strengthLabel];
    NSButton *gen = VPill(@"Generate", NO, self, @selector(generateTapped:), NSMakeRect(x + fw - 76, 316, 76, 32));
    gen.frame = NSMakeRect(x + fw - 76, 314, 76, 32);
    [_form addSubview:gen];

    _notice = [NSTextField wrappingLabelWithString:@""];
    _notice.font = [NSFont systemFontOfSize:12]; _notice.textColor = Y_muted();
    _notice.frame = NSMakeRect(x, 354, fw, 32);
    [_form addSubview:_notice];

    lbl(@"Notes", 394);
    NSScrollView *ns = [[NSScrollView alloc] initWithFrame:NSMakeRect(x + 1, 413, fw - 2, 70)];
    ns.hasVerticalScroller = YES; ns.borderType = NSNoBorder; ns.drawsBackground = NO;
    _notes = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, fw - 2, 70)];
    _notes.font = [NSFont systemFontOfSize:14]; _notes.textColor = Y_ink();
    _notes.textContainerInset = NSMakeSize(10, 8);
    _notes.autoresizingMask = NSViewWidthSizable;
    _notes.delegate = self;
    ns.documentView = _notes;
    NSView *nbox = [[NSView alloc] initWithFrame:NSMakeRect(x, 412, fw, 72)];
    nbox.wantsLayer = YES; nbox.layer.cornerRadius = 12; nbox.layer.borderWidth = 1;
    nbox.layer.borderColor = YT_rgb(10, 19, 23, 0.45).CGColor;
    [_form addSubview:nbox];
    [_form addSubview:ns];

    _save = VPill(@"Save", YES, self, @selector(saveTapped:), NSMakeRect(x, 502, 100, 40));
    [_form addSubview:_save];
    _breach = VPill(@"Check for breaches", NO, self, @selector(breachTapped:), NSMakeRect(x + 108, 502, 180, 40));
    [_form addSubview:_breach];
    _delete = VPill(@"Delete", NO, self, @selector(deleteTapped:), NSMakeRect(x + fw - 90, 502, 90, 40));
    [_form addSubview:_delete];
    NSMutableAttributedString *del = [[NSMutableAttributedString alloc] initWithAttributedString:_delete.attributedTitle];
    [del addAttribute:NSForegroundColorAttributeName value:Y_negative() range:NSMakeRange(0, del.length)];
    _delete.attributedTitle = del;

    _status = VLabel(@"", 12, NSFontWeightRegular, Y_muted());
    _status.frame = NSMakeRect(x, 550, fw, 16);
    [_form addSubview:_status];

    [_detail addSubview:_form];
}

#pragma mark Table

- (void)reloadRowsKeepingSelection {
    if (!_table) return;
    NSString *q = [_search.stringValue.lowercaseString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *e in [SaturnVault shared].entries) {
        if (q.length) {
            NSString *hay = [[NSString stringWithFormat:@"%@ %@ %@", e[@"title"], e[@"url"], e[@"username"]] lowercaseString];
            if (![hay containsString:q]) continue;
        }
        [rows addObject:e];
    }
    _rows = rows;
    [_table reloadData];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv { (void)tv; return _rows.count; }

- (NSView *)tableView:(NSTableView *)tv viewForTableColumn:(NSTableColumn *)col row:(NSInteger)row {
    (void)tv; (void)col;
    NSDictionary *e = _rows[row];
    BOOL selected = [e[@"id"] isEqualToString:_currentID];
    NSView *cell = [[VFlippedView alloc] initWithFrame:NSMakeRect(0, 0, kSideW, 56)];
    cell.wantsLayer = YES;
    NSView *bg = [[NSView alloc] initWithFrame:NSMakeRect(8, 3, kSideW - 16, 50)];
    bg.wantsLayer = YES; bg.layer.cornerRadius = 14;
    bg.layer.backgroundColor = (selected ? Y_soft() : [NSColor clearColor]).CGColor;
    [cell addSubview:bg];
    NSTextField *letter = VLabel([[e[@"title"] substringToIndex:MIN(1, [e[@"title"] length])] uppercaseString], 14, NSFontWeightBold, Y_ink());
    letter.alignment = NSTextAlignmentCenter;
    NSView *badge = [[NSView alloc] initWithFrame:NSMakeRect(18, 12, 32, 32)];
    badge.wantsLayer = YES; badge.layer.cornerRadius = 16; badge.layer.backgroundColor = (selected ? [NSColor whiteColor] : Y_soft()).CGColor;
    letter.frame = NSMakeRect(0, 7, 32, 18);
    [badge addSubview:letter];
    [cell addSubview:badge];
    NSTextField *t = VLabel(e[@"title"], 14, NSFontWeightMedium, Y_ink());
    t.lineBreakMode = NSLineBreakByTruncatingTail;
    t.frame = NSMakeRect(60, 10, kSideW - 80, 18);
    [cell addSubview:t];
    NSString *sub = [e[@"username"] length] ? e[@"username"] : ([SaturnVault hostForURLString:e[@"url"]] ?: @"");
    NSTextField *s = VLabel(sub, 12, NSFontWeightRegular, Y_muted());
    s.lineBreakMode = NSLineBreakByTruncatingTail;
    s.frame = NSMakeRect(60, 29, kSideW - 80, 16);
    [cell addSubview:s];
    return cell;
}

- (BOOL)tableView:(NSTableView *)tv shouldSelectRow:(NSInteger)row {
    (void)tv;
    [self loadEntry:_rows[row]];
    return YES;
}

- (void)controlTextDidChange:(NSNotification *)n {
    if (n.object == _search) { [self reloadRowsKeepingSelection]; return; }
    if (_loading) return;
    if (n.object == _passSecure) _passPlain.stringValue = _passSecure.stringValue;
    if (n.object == _passPlain) _passSecure.stringValue = _passPlain.stringValue;
    if (n.object == _passSecure || n.object == _passPlain) [self passwordEdited];
    _status.stringValue = @"";
}
- (void)textDidChange:(NSNotification *)n { (void)n; if (!_loading) _status.stringValue = @""; }

#pragma mark Detail

- (void)showEmptyDetail {
    _emptyDetail.hidden = NO; _form.hidden = YES;
    _currentID = nil;
    [_table deselectAll:nil];
}

- (void)loadEntry:(NSDictionary *)e {
    _loading = YES;
    _currentID = e[@"id"];
    _emptyDetail.hidden = YES; _form.hidden = NO;
    _formTitle.stringValue = e[@"title"] ?: @"Login";
    _name.stringValue = e[@"title"] ?: @"";
    _site.stringValue = e[@"url"] ?: @"";
    _user.stringValue = e[@"username"] ?: @"";
    _passSecure.stringValue = e[@"password"] ?: @"";
    _passPlain.stringValue = e[@"password"] ?: @"";
    _notes.string = e[@"notes"] ?: @"";
    _delete.hidden = NO;
    _status.stringValue = @"";
    [self setRevealed:NO];
    _loading = NO;
    [self passwordEdited];
    [_table reloadData];
}

- (void)startNewLoginWithURL:(NSString *)url {
    _loading = YES;
    _currentID = nil;
    [_table deselectAll:nil];
    _emptyDetail.hidden = YES; _form.hidden = NO;
    _formTitle.stringValue = @"New login";
    NSString *host = [SaturnVault hostForURLString:url];
    _name.stringValue = host ?: @"";
    _site.stringValue = url ?: @"";
    _user.stringValue = @""; _passSecure.stringValue = @""; _passPlain.stringValue = @""; _notes.string = @"";
    _delete.hidden = YES;
    _status.stringValue = @"";
    [self setRevealed:NO];
    _loading = NO;
    [self passwordEdited];
    [_table reloadData];
    [self makeFirstResponder:_name];
}

- (void)passwordEdited {
    NSString *p = _passSecure.stringValue;
    VSetStrength(_segs, _strengthLabel, p);
    NSInteger reuse = [[SaturnVault shared] reuseCountForPassword:p excludingID:_currentID];
    if (reuse > 0) {
        _notice.stringValue = [NSString stringWithFormat:@"This password is also used for %ld other login%@. Use a different one for each site.", (long)reuse, reuse == 1 ? @"" : @"s"];
        _notice.textColor = Y_negative();
    } else {
        _notice.stringValue = @"";
    }
}

- (void)setRevealed:(BOOL)on {
    _passPlain.hidden = !on; _passSecure.hidden = on;
    NSString *sym = on ? @"eye.slash" : @"eye";
    NSImage *img = [NSImage imageWithSystemSymbolName:sym accessibilityDescription:nil];
    _reveal.image = [img imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:14 weight:NSFontWeightMedium]] ?: img;
    _reveal.toolTip = on ? @"Hide password" : @"Show password";
}

#pragma mark Actions

- (void)lockTapped:(id)sender { (void)sender; [[SaturnVault shared] lock]; }

- (void)newLoginTapped:(id)sender { (void)sender; [self startNewLoginWithURL:nil]; }

- (void)toggleReveal:(id)sender { (void)sender; [self setRevealed:_passPlain.hidden]; }

- (void)copyUser:(id)sender {
    (void)sender;
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents]; [pb setString:_user.stringValue forType:NSPasteboardTypeString];
    _status.textColor = Y_muted(); _status.stringValue = @"Username copied.";
}
- (void)copyPass:(id)sender {
    (void)sender;
    if (!_passSecure.stringValue.length) return;
    [SaturnVault copySecret:_passSecure.stringValue];
    _status.textColor = Y_muted(); _status.stringValue = @"Password copied. It clears from the clipboard in 30 seconds.";
}

- (void)generateTapped:(id)sender {
    (void)sender;
    NSString *p = [SaturnVault generatePasswordWithLength:20 digits:YES symbols:YES];
    _passSecure.stringValue = p; _passPlain.stringValue = p;
    [self setRevealed:YES];
    [self passwordEdited];
    _status.textColor = Y_muted(); _status.stringValue = @"Generated a 20-character password. Save to keep it.";
}

- (void)saveTapped:(id)sender {
    (void)sender;
    NSString *pass = _passSecure.stringValue;
    if (!pass.length) { _status.textColor = Y_negative(); _status.stringValue = @"Add a password first."; return; }
    NSMutableDictionary *e = [@{@"title": _name.stringValue, @"url": _site.stringValue, @"username": _user.stringValue, @"password": pass, @"notes": _notes.string} mutableCopy];
    SaturnVault *v = [SaturnVault shared];
    if (_currentID) { e[@"id"] = _currentID; [v updateEntry:e]; }
    else _currentID = [v addEntry:e];
    [self reloadRowsKeepingSelection];
    NSDictionary *saved = [v entryWithID:_currentID];
    if (saved) [self loadEntry:saved];
    NSUInteger idx = [_rows indexOfObjectPassingTest:^BOOL(NSDictionary *r, NSUInteger i, BOOL *stop) { (void)i; (void)stop; return [r[@"id"] isEqualToString:self->_currentID]; }];
    if (idx != NSNotFound) [_table scrollRowToVisible:idx];
    _status.textColor = Y_positive(); _status.stringValue = @"Saved.";
}

- (void)deleteTapped:(id)sender {
    (void)sender;
    if (!_currentID) return;
    NSAlert *a = [[NSAlert alloc] init];
    a.messageText = [NSString stringWithFormat:@"Delete “%@”?", _name.stringValue];
    a.informativeText = @"This removes the login from Yavqo Vault. It can't be undone.";
    [a addButtonWithTitle:@"Delete"];
    [a addButtonWithTitle:@"Cancel"];
    [a beginSheetModalForWindow:self completionHandler:^(NSModalResponse r) {
        if (r != NSAlertFirstButtonReturn) return;
        [[SaturnVault shared] deleteEntryID:self->_currentID];
        [self showEmptyDetail];
        [self reloadRowsKeepingSelection];
    }];
}

- (void)breachTapped:(id)sender {
    (void)sender;
    NSString *p = _passSecure.stringValue;
    if (!p.length) return;
    _breach.enabled = NO;
    _status.textColor = Y_muted(); _status.stringValue = @"Checking…";
    [SaturnVault checkBreachCountForPassword:p completion:^(NSInteger count, NSError *err) {
        self->_breach.enabled = YES;
        if (err) { self->_status.textColor = Y_muted(); self->_status.stringValue = err.localizedDescription; return; }
        if (count > 0) {
            self->_status.textColor = Y_negative();
            self->_status.stringValue = [NSString stringWithFormat:@"This password appears in %@ known data breaches. Change it.", [NSNumberFormatter localizedStringFromNumber:@(count) numberStyle:NSNumberFormatterDecimalStyle]];
        } else {
            self->_status.textColor = Y_positive();
            self->_status.stringValue = @"Not found in known data breaches.";
        }
    }];
}

- (void)importTapped:(id)sender {
    (void)sender;
    NSOpenPanel *p = [NSOpenPanel openPanel];
    p.allowedContentTypes = @[[UTType typeWithIdentifier:@"public.comma-separated-values-text"] ?: UTTypeText, UTTypePlainText];
    p.message = @"Choose a passwords .csv exported from Chrome, Safari or another manager.";
    p.prompt = @"Import";
    [p beginSheetModalForWindow:self completionHandler:^(NSModalResponse r) {
        if (r != NSModalResponseOK || !p.URL) return;
        NSString *text = [NSString stringWithContentsOfURL:p.URL encoding:NSUTF8StringEncoding error:nil];
        NSInteger n = text ? [[SaturnVault shared] importCSVText:text] : 0;
        NSAlert *a = [[NSAlert alloc] init];
        if (n > 0) {
            a.messageText = [NSString stringWithFormat:@"Imported %ld login%@", (long)n, n == 1 ? @"" : @"s"];
            a.informativeText = @"That CSV file holds your passwords in plain text. Delete it now, and empty the Trash.";
        } else {
            a.messageText = @"Nothing to import";
            a.informativeText = @"No new logins were found. The file needs columns for the website, username and password.";
        }
        [a addButtonWithTitle:@"OK"];
        [a beginSheetModalForWindow:self completionHandler:nil];
    }];
}

- (void)close {
    // Don't leave a revealed password on screen once the window is gone.
    [self setRevealed:NO];
    [super close];
}

@end
