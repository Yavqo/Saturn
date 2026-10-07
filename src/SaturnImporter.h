#pragma once
#import <Cocoa/Cocoa.h>

// One browser profile found on this Mac that Saturn can read.
@interface SaturnImportSource : NSObject
@property (nonatomic, copy) NSString *name;        // "Google Chrome", "Chrome – Work", "Safari"
@property (nonatomic, copy) NSString *kind;        // chromium | firefox | safari
@property (nonatomic, copy) NSString *path;        // profile folder (Safari: ~/Library/Safari)
@end

// Brings bookmarks and history in from other browsers. Passwords and cookies are deliberately not imported:
// other browsers keep them encrypted with keys Saturn has no business reading.
@interface SaturnImporter : NSObject
+ (NSArray<SaturnImportSource *> *)availableSources;
// Runs off the main thread, merges on the main thread. `note` carries a hint when something could not be read
// (for example Safari needs Full Disk Access).
+ (void)importFromSource:(SaturnImportSource *)source bookmarks:(BOOL)bookmarks history:(BOOL)history
              completion:(void (^)(NSUInteger bookmarksAdded, NSUInteger historyAdded, NSString *note))completion;
// A bookmarks file exported from any browser (Netscape HTML format).
+ (void)importBookmarksHTMLAtPath:(NSString *)path completion:(void (^)(NSUInteger bookmarksAdded, NSString *note))completion;
// Shows the picker (source, what to import) and runs the import.
+ (void)presentImportDialogFromWindow:(NSWindow *)window;
@end
