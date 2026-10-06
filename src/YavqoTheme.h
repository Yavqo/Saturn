// Yavqo design tokens for AppKit (see the Yavqo design language: white canvas, one blue, flat).
#import <Cocoa/Cocoa.h>

static inline NSColor *YT_rgb(CGFloat r, CGFloat g, CGFloat b, CGFloat a) { return [NSColor colorWithSRGBRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:a]; }
#define Y_blue()     YT_rgb(0x00, 0x64, 0xE0, 1)
#define Y_blueHover() YT_rgb(0x04, 0x57, 0xCB, 1)
#define Y_ink()      YT_rgb(0x1C, 0x2B, 0x33, 1)
#define Y_muted()    YT_rgb(0x5D, 0x6C, 0x7B, 1)
#define Y_muted2()   YT_rgb(0x64, 0x76, 0x85, 1)
#define Y_soft()     YT_rgb(0xF1, 0xF4, 0xF7, 1)
#define Y_border()   YT_rgb(0xDE, 0xE3, 0xE9, 1)
#define Y_hairline() YT_rgb(10, 19, 23, 0.12)
#define Y_positive() YT_rgb(0x31, 0xA2, 0x4C, 1)
#define Y_negative() YT_rgb(0xE4, 0x1E, 0x3F, 1)

// Full pill button: primary = blue/white, otherwise soft grey/ink. Grows a 32px button to the 40px pill height.
static inline void YT_pill(NSButton *b, BOOL primary) {
    NSRect f = b.frame;
    if (f.size.height < 40) { f.origin.y -= (40 - f.size.height) / 2; f.size.height = 40; b.frame = f; }
    b.bordered = NO;
    b.wantsLayer = YES;
    b.layer.backgroundColor = (primary ? Y_blue() : Y_soft()).CGColor;
    b.layer.cornerRadius = f.size.height / 2;
    NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
    ps.alignment = NSTextAlignmentCenter;
    b.attributedTitle = [[NSAttributedString alloc] initWithString:b.title attributes:@{
        NSForegroundColorAttributeName: primary ? [NSColor whiteColor] : Y_ink(),
        NSFontAttributeName: [NSFont systemFontOfSize:14 weight:NSFontWeightBold],
        NSParagraphStyleAttributeName: ps }];
}
