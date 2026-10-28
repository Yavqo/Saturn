#pragma once
#import <Cocoa/Cocoa.h>

// Create / unlock panel for Yavqo Vault. Shows "create a master password" when there is no vault yet,
// otherwise a single master-password field. Used in the vault window and in the browser popovers.
@interface SaturnVaultGate : NSView
- (instancetype)initWithWidth:(CGFloat)width message:(NSString *)message;
@property (nonatomic, copy) void (^onUnlocked)(void);
@property (nonatomic, readonly) CGFloat height;
- (void)focus;
@end

// The Yavqo Vault manager window: browse, add, edit and generate logins.
@interface SaturnVaultWindow : NSWindow
+ (instancetype)shared;
- (void)showVault;
- (void)showNewLoginWithURL:(NSString *)url;   // opens the editor on a blank login for this site
@end
