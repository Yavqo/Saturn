#pragma once
#import <Foundation/Foundation.h>

// Posted on the main thread whenever bookmarks are added or removed.
extern NSNotificationName const SaturnBookmarksChangedNotification;

// Saved pages, kept in NSUserDefaults. Each item is {title, url}.
@interface SaturnBookmarks : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) NSArray<NSDictionary<NSString *, NSString *> *> *items;
+ (NSString *)keyForURL:(NSURL *)url;      // normalised: no fragment, no bare trailing slash
+ (BOOL)canBookmarkURL:(NSURL *)url;       // http(s) pages only
- (BOOL)containsURL:(NSURL *)url;
- (void)addURL:(NSURL *)url title:(NSString *)title;
- (void)removeURLString:(NSString *)urlString;
- (BOOL)toggleURL:(NSURL *)url title:(NSString *)title;
- (void)resetToDefaults;                                  // factory reset: back to the starter bookmarks   // returns YES if it is bookmarked afterwards
@end
