# Saturn for Android

Android preview of Saturn 0.7.1. Requires Android 8.0 or newer.

- Mars search and homepage by default.
- Up to 30 tabs, with tab switching, closing, tab search and saved URLs.
- Back, forward, reload, stop and home controls.
- Find in page, reader mode, bookmarks and history.
- Downloads through the system download manager, and camera/microphone permission prompts.
- Alisa, Saturn's assistant, in a bottom sheet — ask about the page you are on.
- Settings for Mars, Google or DuckDuckGo search and clearing browsing data.
- Silver and graphite browser chrome, drawn icons, a bottom address bar, and custom tab and settings panels.

Uses Android's installed WebView. The desktop automation tools are not included in this preview. Tab URLs are restored on launch; navigation history is retained while the app is open.

## Build

Install JDK 17 and the Android SDK (platform 35 and build tools 35.0.0). Set `sdk.dir` in an untracked `local.properties` file or set `ANDROID_HOME`.

```sh
./gradlew assembleDebug
```

The installable debug-signed APK is generated at `app/build/outputs/apk/debug/app-debug.apk`. A production release requires a private release signing key. This preview has not been tested on an Android device.

## Bundled API key

Alisa talks to `https://api.apinex.bond/v1` with the `free/muse-spark-1.3` model. Release builds embed the key from `../secrets/apinex.key` (git-ignored, local only) through `BuildConfig`. Without that file the app still builds, but Alisa has no key to use. Set `APINEX_API_KEY` in the environment or `local.properties` to override it on your own builds.
