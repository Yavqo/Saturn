#pragma once
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

// Posted on the main thread whenever history changes.
extern NSNotificationName const SaturnHistoryChangedNotification;

// Browsing history: one entry per visit, newest first. Each entry is {u: url, t: title, d: seconds since 1970}.
// Stored as JSON in ~/Library/Application Support/Saturn/history.json.
@interface SaturnHistory : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) NSArray<NSDictionary *> *entries;
- (void)recordURL:(NSURL *)url title:(NSString *)title;
- (void)removeURLString:(NSString *)url visitedAt:(double)seconds;
- (void)clearSince:(NSDate *)date;      // nil clears everything
- (NSUInteger)importEntries:(NSArray<NSDictionary *> *)entries;   // merge visits from another browser; returns how many were new
- (void)flush;                           // write to disk now
- (NSString *)historyPageHTML;
// Address bar suggestions from history and bookmarks. Each item is {kind: "history"|"bookmark", title, url}.
- (NSArray<NSDictionary *> *)suggestionsForQuery:(NSString *)query limit:(NSUInteger)limit;
@end

// Serves the built-in pages (saturn://history) to a web view.
@interface SaturnSchemeHandler : NSObject <WKURLSchemeHandler>
+ (instancetype)shared;
@end
