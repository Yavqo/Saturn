#pragma once
#import <Foundation/Foundation.h>

// Saturn Shield's built-in lists. Each host entry blocks that host and every subdomain of it
// ("hotjar.com" also covers "script.hotjar.com"); specific subdomains are listed where the parent
// domain is a normal site people visit (for example "ads.linkedin.com", never "linkedin.com").
NSArray<NSString *> *SaturnShieldAdHosts(void);        // ad networks, exchanges, ad servers, mobile ad SDKs, ad verification
NSArray<NSString *> *SaturnShieldTrackerHosts(void);   // analytics, session replay, pixels, error trackers, OEM telemetry
NSArray<NSString *> *SaturnShieldMinerHosts(void);     // in-browser crypto miners
NSArray<NSString *> *SaturnShieldCosmeticSelectors(void);   // elements hidden on every page (safe CSS only)
