#import "SaturnShieldLists.h"

NSArray<NSString *> *SaturnShieldAdHosts(void) {
    static NSArray *a;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ a = @[
        // Google
        @"doubleclick.net", @"googlesyndication.com", @"googleadservices.com", @"googletagservices.com", @"2mdn.net", @"admob.com",
        @"adservice.google.com", @"pagead2.googlesyndication.com", @"afs.googlesyndication.com", @"ads.youtube.com", @"adsense.google.com",
        @"googleads.g.doubleclick.net", @"partner.googleadservices.com", @"imasdk.googleapis.com", @"securepubads.g.doubleclick.net",
        // Amazon
        @"amazon-adsystem.com", @"adtago.s3.amazonaws.com", @"advice-ads.s3.amazonaws.com", @"aax.amazon-adsystem.com",
        // Microsoft / Yahoo / Verizon
        @"ads.msn.com", @"a.ads1.msn.com", @"bat.bing.com", @"ads.yahoo.com", @"advertising.yahoo.com", @"gemini.yahoo.com",
        @"partnerads.ysm.yahoo.com", @"adtech.yahooinc.com", @"adtechus.com", @"adtech.de", @"advertising.com", @"aol.advertising.com",
        @"ads.aol.com", @"adsonar.com", @"atwola.com", @"yieldmanager.com", @"ysm.yahoo.com",
        // Social ad endpoints
        @"an.facebook.com", @"pixel.facebook.com", @"ads-api.twitter.com", @"ads.twitter.com", @"static.ads-twitter.com", @"ads-twitter.com",
        @"ads.linkedin.com", @"ads.pinterest.com", @"ads.tiktok.com", @"ads-api.tiktok.com", @"ads-sg.tiktok.com", @"business-api.tiktok.com",
        @"ads.snapchat.com", @"adsapi.snapchat.com", @"ads-api.reddit.com", @"ads.vk.com", @"ads.yandex.ru",
        // Exchanges, SSPs, DSPs
        @"adnxs.com", @"adnxs.net", @"adsrvr.org", @"adform.net", @"adform.com", @"criteo.com", @"criteo.net", @"rubiconproject.com",
        @"pubmatic.com", @"openx.net", @"openx.com", @"casalemedia.com", @"indexexchange.com", @"33across.com", @"contextweb.com",
        @"lijit.com", @"sovrn.com", @"spotxchange.com", @"spotx.tv", @"springserve.com", @"tremorhub.com", @"tremormedia.com", @"fwmrm.net",
        @"bidswitch.net", @"smartadserver.com", @"sharethrough.com", @"triplelift.com", @"teads.tv", @"yieldmo.com", @"yieldlab.net",
        @"gumgum.com", @"districtm.io", @"conversantmedia.com", @"mediavine.com", @"adthrive.com", @"ezoic.net", @"adsafeprotected.com",
        @"moatads.com", @"moatpixel.com", @"doubleverify.com", @"dvtps.com", @"integralads.com", @"iasds01.com", @"serving-sys.com",
        @"flashtalking.com", @"adition.com", @"adscale.de", @"admixer.net", @"adkernel.com", @"adspirit.de", @"simpli.fi", @"dotomi.com",
        @"mathtag.com", @"mookie1.com", @"turn.com", @"tapad.com", @"bidr.io", @"adgrx.com", @"adlightning.com", @"adsymptotic.com",
        @"onetag-sys.com", @"improvedigital.com", @"richaudience.com", @"rhythmone.com", @"1rx.io", @"ads.stickyadstv.com", @"stickyadstv.com",
        @"360yield.com", @"adnuntius.com", @"adzerk.net", @"carbonads.net", @"carbonads.com", @"buysellads.com", @"adbrite.com",
        @"bidtheatre.com", @"emxdgt.com", @"loopme.me", @"nativo.com", @"nativo.net", @"kargo.com", @"rfihub.com", @"w55c.net",
        @"sitescout.com", @"semasio.net", @"turn.com", @"undertone.com", @"videologygroup.com", @"vidoomy.com", @"unruly.co", @"unrulymedia.com",
        // Native / content recommendation
        @"taboola.com", @"outbrain.com", @"revcontent.com", @"mgid.com", @"zemanta.com", @"content-ad.net", @"adblade.com", @"plista.com",
        @"zergnet.com", @"dianomi.com", @"engageya.com", @"nend.net",
        // Push, pop, adult and low-quality networks
        @"popads.net", @"popcash.net", @"propellerads.com", @"propellerclick.com", @"adcash.com", @"exoclick.com", @"exosrv.com", @"juicyads.com",
        @"trafficjunky.net", @"trafficfactory.biz", @"clickadu.com", @"hilltopads.net", @"adsterra.com", @"adskeeper.com", @"onclickads.net",
        @"a-ads.com", @"bidvertiser.com", @"infolinks.com", @"intellitxt.com", @"kontera.com", @"chitika.net", @"chitika.com", @"yllix.com",
        @"ero-advertising.com", @"plugrush.com", @"adxxx.com", @"adtng.com", @"tsyndicate.com", @"realsrv.com", @"adsco.re", 
        @"richpush.co", @"mondiad.com", @"monetag.com", @"ad-maven.com", @"admaven.com",
        @"adsession.com", @"clickaine.com", @"popunderjs.com", @"go.oclasrv.com", @"oclaserver.com", @"syndication.exoclick.com",
        // Mobile ad SDKs
        @"adcolony.com", @"applovin.com", @"applvn.com", @"unityads.unity3d.com", @"vungle.com", @"chartboost.com", @"ironsrc.com",
        @"supersonicads.com", @"inmobi.com", @"mopub.com", @"startappservice.com", @"startapp.com", @"tapjoy.com", @"fyber.com", @"smaato.net",
        @"smaato.com", @"mobfox.com", @"millennialmedia.com", @"leadbolt.net", @"airpush.com", @"ads.mp.mydas.mobi", @"mydas.mobi", @"pangleglobal.com",
        @"pangle.io", @"byteoversea.com", @"mintegral.com", @"mintegral.net", @"adjust.io",
        // Data management, identity graphs and audience sellers
        @"bluekai.com", @"krxd.net", @"demdex.net", @"everesttech.net", @"exelator.com", @"eyeota.net", @"rlcdn.com", @"agkn.com",
        @"crwdcntrl.net", @"liveramp.com", @"adsrvr.org", @"id5-sync.com", @"permutive.com", @"permutive.app", @"lotame.com", @"thetradedesk.com",
        @"360yield.com", @"audiencemanager.de", @"owneriq.net", @"acuityads.com", @"adroll.com", @"perfectaudience.com", @"retargeter.com",
        @"media.net", @"static.media.net", @"adservetx.media.net", @"hb.adtelligent.com", @"adtelligent.com", @"appnexus.com",
        @"adition.com", @"zedo.com", @"zqtk.net", @"adspeed.net", @"clickbooth.com", 
        @"tradedoubler.com", @"awin1.com", @"zanox.com", @"linksynergy.com", @"cj.com", @"dpbolvw.net", @"jdoqocy.com",
        @"anrdoezrs.net", @"tkqlhce.com", @"kqzyfj.com", @"commission-junction.com", @"impactradius-event.com", @"7eer.net", @"partnerize.com",
        @"prf.hn", @"pepperjam.com", @"ojrq.net", @"rakutenmarketing.com", @"avantlink.com", @"admitad.com", @"ad.admitad.com",
        @"smartyads.com", @"adhigh.net", @"admedo.com", @"adsbookie.com", @"pubnation.com", @"setupad.com", @"snigel.com", @"vidazoo.com",
    ]; });
    return a;
}

NSArray<NSString *> *SaturnShieldTrackerHosts(void) {
    static NSArray *a;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ a = @[
        // Google
        @"google-analytics.com", @"analytics.google.com", @"click.googleanalytics.com", @"ssl.google-analytics.com", @"googleanalytics.com",
        @"stats.g.doubleclick.net", @"app-measurement.com", @"firebaselogging.googleapis.com", @"firebase-settings.crashlytics.com",
        @"crashlytics.com", @"data.crashlytics.com", @"reports.crashlytics.com",
        // Session replay and behaviour analytics
        @"hotjar.com", @"hotjar.io", @"mouseflow.com", @"luckyorange.com", @"luckyorange.net", @"crazyegg.com", @"fullstory.com", @"logrocket.com",
        @"logrocket.io", @"lr-ingest.io", @"smartlook.com", @"smartlook.cloud", @"inspectlet.com", @"clicktale.net", @"clicktale.com", @"contentsquare.net",
        @"contentsquare.com/tag", @"heapanalytics.com", @"decibelinsight.net", @"quantummetric.com", @"sessioncam.com", @"userreplay.net",
        @"mousestats.com", @"seevolution.com", @"visualwebsiteoptimizer.com", @"dev.visualwebsiteoptimizer.com",
        // Product analytics
        @"mixpanel.com", @"mxpnl.com", @"api.segment.io", @"cdn.segment.com", @"segment.io", @"api.amplitude.com", @"api2.amplitude.com",
        @"cdn.amplitude.com", @"api.eu.amplitude.com", @"i.kissmetrics.com", @"scripts.kissmetrics.com", @"kissmetrics.io", @"logx.optimizely.com",
        @"cdn.optimizely.com", @"posthog.com/e", @"app.posthog.com", @"us.i.posthog.com", @"eu.i.posthog.com", @"api.june.so", @"rudderstack.com/v1",
        @"cdp.customer.io", @"track.customer.io", @"api.intercom.io/messenger/metrics", @"pendo.io", @"data.pendo.io", @"cdn.pendo.io", @"gainsight.com/px",
        @"api.mparticle.com", @"jssdkcdns.mparticle.com", @"snowplow.io", @"clearbit.com/v1/tracking", @"tag.clearbitscripts.com", @"clearbitjs.com",
        @"analyticsengine.s3.amazonaws.com", @"analytics.s3.amazonaws.com", @"freshmarketer.com", @"claritybt.freshmarketer.com", @"fwtracks.freshmarketer.com", @"stats.wp.com", @"pixel.wp.com", @"pixel.wordpress.com",
        // Web traffic and audience measurement
        @"quantserve.com", @"quantcount.com", @"scorecardresearch.com", @"imrworldwide.com", @"chartbeat.com", @"chartbeat.net", @"pixel.parsely.com",
        @"srv.pixel.parsely.com", @"c.statcounter.com", @"secure.statcounter.com", @"histats.com", @"in.getclicky.com", @"static.getclicky.com",
        @"clicky.com/stats", @"statcounter.com/counter", @"counter.yadro.ru", @"top-fwz1.mail.ru", @"top.mail.ru", @"cnzz.com", @"umeng.com",
        @"hm.baidu.com", @"hmcdn.baidu.com", @"pingdom.net", @"rum-static.pingdom.net", @"gemius.pl", @"gemius.com", @"hit.gemius.pl", @"alexametrics.com",
        @"estat.com", @"xiti.com", @"at-o.net", @"atinternet.com", @"webtrekk.net", @"mapp.com/tracking", @"etracker.com", @"etracker.de", @"sitemeter.com",
        @"bluecava.com", @"effectivemeasure.net", @"nr-data.net", @"js-agent.newrelic.com", @"bam.nr-data.net", @"bam-cell.nr-data.net",
        @"rum.browser-intake-datadoghq.com", @"browser-intake-datadoghq.com", @"rum-http-intake.logs.datadoghq.com", 
        @"mc.yandex.ru", @"mc.yandex.com", @"metrika.yandex.ru", @"appmetrica.yandex.ru", @"adfstat.yandex.ru", @"adfox.yandex.ru", @"extmaps-api.yandex.net",
        @"offerwall.yandex.net", @"an.yandex.ru", @"yandexadexchange.net", @"mc.webvisor.com", 
        // Social tracking
        @"clarity.ms", @"c.clarity.ms", @"analytics.twitter.com", @"analytics.pointdrive.linkedin.com", @"px.ads.linkedin.com", @"snap.licdn.com",
        @"dc.ads.linkedin.com", @"log.pinterest.com", @"analytics.pinterest.com", @"trk.pinterest.com", @"ct.pinterest.com", @"events.reddit.com",
        @"events.redditmedia.com", @"alb.reddit.com", @"pixel-config.reddit.com", @"analytics.tiktok.com", @"analytics-sg.tiktok.com",
        @"analytics.us.tiktok.com", @"log.byteoversea.com", @"mon.musical.ly", @"sc-static.net", @"tr.snapchat.com", @"analytics.snapchat.com",
        @"pixel.quantcount.com", @"px.owneriq.net", @"analytics.yahoo.com", @"geo.yahoo.com", @"udc.yahoo.com", @"udcm.yahoo.com",
        @"analytics.query.yahoo.com", @"log.fc.yahoo.com", @"sp.analytics.yahoo.com", @"analytics-api.samsunghealthcn.com",
        // Marketing automation pixels
        @"hs-analytics.net", @"hsadspixel.net", @"hs-banner.com", @"track.hubspot.com", @"forms.hubspot.com/embed/v3/counters", @"munchkin.marketo.net",
        @"pi.pardot.com", @"cdn.pardot.com", @"b2bjsdelivr.com", @"omtrdc.net", @"2o7.net", @"sc.omtrdc.net", @"adobedc.net", @"tt.omtrdc.net",
        @"trk.klclick.com", @"a.klaviyo.com/api/track", @"trc.taboola.com", @"cdn.taboola.com",
        @"track.adform.net", @"cm.g.doubleclick.net", @"ib.adnxs.com", @"sync.outbrain.com", @"tracking.outbrain.com", @"beacon.krxd.net",
        @"ping.chartbeat.net", @"facebook.com/tr/", @"facebook.com/tr?", @"facebook.com/tr.php", @"connect.facebook.net/signals", @"tracking.miui.com",
        // Error and crash reporting
        @"notify.bugsnag.com", @"sessions.bugsnag.com", @"api.bugsnag.com", @"app.bugsnag.com", @"browser.sentry-cdn.com", @"app.getsentry.com",
        @"ingest.sentry.io", @"js.sentry-cdn.com", @"api.rollbar.com", @"api.raygun.io", @"usage.trackjs.com", @"capture.trackjs.com", @"api.honeybadger.io",
        @"errors.airbrake.io", @"api.airbrake.io", @"sentry.io/api/embed/error-page", 
        // Attribution
        @"appsflyersdk.com", @"t.appsflyer.com", @"events.appsflyer.com", @"launches.appsflyer.com", @"sdk-services.appsflyer.com", @"wa.appsflyer.com",
        @"app.adjust.com", @"app.adjust.io", @"adjust.net.in", @"branch.io/v1", @"api2.branch.io", @"api.branch.io", @"kochava.com", @"singular.net",
        @"tenjin.io", @"api.mixpanel.com", @"decide.mixpanel.com", @"apptimize.com", @"leanplum.com", @"swrve.com", @"localytics.com", @"flurry.com",
        @"data.flurry.com", @"mobileapptracking.com", @"tune.com/tracking", @"trackcmp.net", @"tracking.crazyegg.com",
        // Device-maker and OS telemetry
        @"iot-eu-logser.realme.com", @"iot-logser.realme.com", @"bdapi-ads.realmemobile.com", @"bdapi-in-ads.realmemobile.com", @"api.ad.xiaomi.com",
        @"data.mistat.xiaomi.com", @"data.mistat.india.xiaomi.com", @"data.mistat.rus.xiaomi.com", @"sdkconfig.ad.xiaomi.com",
        @"sdkconfig.ad.intl.xiaomi.com", @"globalapi.ad.xiaomi.com", @"tracking.rus.miui.com", @"adsfs.oppomobile.com", @"adx.ads.oppomobile.com",
        @"ck.ads.oppomobile.com", @"data.ads.oppomobile.com", @"bdapi.ads.oppomobile.com", @"metrics.data.hicloud.com", @"metrics2.data.hicloud.com",
        @"grs.hicloud.com", @"logservice.hicloud.com", @"logservice1.hicloud.com", @"logbak.hicloud.com", @"click.oneplus.cn", @"open.oneplus.net",
        @"samsungads.com", @"smetrics.samsung.com", @"nmetrics.samsung.com", @"samsungacr.com", @"samsungcloudsolution.com", @"iadsdk.apple.com",
        @"metrics.icloud.com", @"metrics.mzstatic.com", @"api-adservices.apple.com", @"books-analytics-events.apple.com", @"weather-analytics-events.apple.com",
        @"notes-analytics-events.apple.com", @"xp.apple.com", @"stocks-analytics-events.apple.com", @"news-events.apple.com", @"securemetrics.apple.com",
        @"analytics.analytics-egain.com", @"telemetry.microsoft.com", @"vortex.data.microsoft.com", @"watson.telemetry.microsoft.com",
        @"settings-win.data.microsoft.com", @"telemetry.dropbox.com", @"telemetry.mozilla.org", @"incoming.telemetry.mozilla.org", @"telemetry.vercel.com",
        @"analytics.vercel.com", @"vitals.vercel-insights.com", @"vercel-insights.com", @"va.vercel-scripts.com", @"o.alicdn.com", @"log.alipay.com",
    ]; });
    return a;
}

NSArray<NSString *> *SaturnShieldMinerHosts(void) {
    return @[@"coinhive.com", @"coin-hive.com", @"crypto-loot.com", @"cryptoloot.pro", @"webminerpool.com", @"minr.pw", @"coin-have.com", @"authedmine.com",
             @"jsecoin.com", @"minero.cc", @"webmine.cz", @"coinimp.com", @"ppoi.org", @"monerominer.rocks", @"miner.pr0gramm.com", @"coinerra.com",
             @"2giga.link", @"mataharirama.xyz", @"hashing.win"];
}

NSArray<NSString *> *SaturnShieldCosmeticSelectors(void) {
    return @[
        @".adsbygoogle", @"ins.adsbygoogle", @".adsbox", @"#ad-wrapper", @".ad-container", @".ad_unit", @".ad-slot", @".ad-wrapper", @".ad-unit",
        @".ad-banner", @".ad_banner", @".ad-box", @".ad-block", @".ad-placeholder", @".ad-placement", @".ad-holder", @".ad-leaderboard",
        @".advert", @".advertisement", @".advertisement-container", @".advertising", @".advertorial", @".sponsored-post", @".sponsored-content",
        @".sponsored-links", @".sponsor-box", @".native-ad", @".nativead", @".native-ads", @".text-ad", @".textad", @".banner-ad", @".banner_ad",
        @".bannerAd", @".bannerads", @".top-ad", @".sidebar-ad", @".footer-ad", @".sticky-ad", @".sticky-ads", @".leaderboard-ad", @".dfp-ad",
        @".dfp-ad-container", @".gpt-ad", @".google-ad", @".google-ads", @".google_ad", @".googleAd", @".googlead", @".taboola", @".taboola-widget",
        @".outbrain", @".OUTBRAIN", @".ob-widget", @".trc_rbox", @".trc_related_container", @".mgid", @".mgbox", @".revcontent",
        @"#carbonads", @".carbon-ads", @"#carbon-block", @"[id^=\"div-gpt-ad\"]", @"[id^=\"google_ads_\"]", @"[id*=\"google_ads_iframe\"]",
        @"[id^=\"ad-slot\"]", @"[id^=\"ad_slot\"]", @"[id*=\"-ad-slot\"]", @"[id^=\"adsbygoogle\"]", @"[id^=\"dfp-\"]",
        @"[id^=\"taboola-\"]", @"[id^=\"outbrain\"]", @"[id^=\"adv-\"]", @"[id^=\"advert\"]", @"[id*=\"advertisement\"]",
        @"[class*=\"ad-banner\"]", @"[class*=\"ad_banner\"]", @"[class*=\"google-ad\"]", @"[class*=\"google_ad\"]", @"[class*=\"advertisement\"]",
        @"[class^=\"adv-\"]", @"[class*=\" adv-\"]",
        @"[class*=\"sponsored\"]", @"[data-ad-slot]", @"[data-ad-client]", @"[data-ad-unit]", @"[data-ad-unit-path]", @"[data-google-query-id]",
        @"[data-adunit]", @"[data-advertisement]", @"[data-native-ad]", @"[aria-label=\"Advertisement\"]", @"[aria-label=\"advertisement\"]",
        @"[aria-label=\"Ads\"]", @"[title=\"Advertisement\"]", @"[data-testid=\"ad\"]", @"[data-testid=\"advertisement\"]",
        @"iframe[src*=\"doubleclick.net\"]", @"iframe[src*=\"googlesyndication.com\"]", @"iframe[src*=\"adservice.google\"]", @"iframe[src*=\"adnxs.com\"]",
        @"iframe[src*=\"criteo.\"]", @"iframe[src*=\"taboola.com\"]", @"iframe[src*=\"outbrain.com\"]", @"iframe[src*=\"amazon-adsystem.com\"]",
        @"iframe[src*=\"pubmatic.com\"]", @"iframe[src*=\"rubiconproject.com\"]", @"iframe[src*=\"openx.net\"]", @"iframe[src*=\"adform.net\"]",
        @"iframe[id^=\"google_ads\"]", @"iframe[name^=\"google_ads\"]", @"iframe[id^=\"aswift\"]", @"iframe[src*=\"/ads/\"]", @"iframe[src*=\"adserver\"]",
        @"a[href*=\"doubleclick.net/\"]", @"a[href*=\"googleadservices.com/\"]", @"a[href*=\"/aclk?\"]", @"a[href^=\"https://adclick.\"]", @"a[href*=\"adfarm.\"]",
        @"ytd-display-ad-renderer", @"ytd-promoted-sparkles-web-renderer", @"ytd-promoted-video-renderer", @"ytd-banner-promo-renderer",
        @"ytd-in-feed-ad-layout-renderer", @"ytd-ad-slot-renderer", @"ytd-statement-banner-renderer", @"ytd-companion-slot-renderer", @"#player-ads",
        @"#masthead-ad", @".ytp-ad-module", @".ytp-ad-overlay-container", @".ytp-ad-message-container", @".ytp-ad-image-overlay", @".ytd-merch-shelf-renderer",
        @".cookie-banner", @"#onetrust-banner-sdk", @"#onetrust-consent-sdk", @".qc-cmp2-container", @"[class*=\"cookie-notice\"]", @".didomi-popup-container",
        @"#CybotCookiebotDialog", @".cc-window", @"#cookie-law-info-bar", @".cmp-container", @"[id^=\"sp_message_container\"]", @".truste_overlay", @"#truste-consent-track",
    ];
}
