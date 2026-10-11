# Saturn for Android

Android preview of Saturn 0.4.0. Requires Android 8.0 or newer.

- Mars search and homepage by default.
- Up to 30 tabs, with tab switching, closing and saved URLs.
- Back, forward, reload, stop and home controls.
- Settings for Mars, Google or DuckDuckGo search and clearing browsing data.

Uses Android's installed WebView. Elaine and the desktop automation tools are not included in this preview. Tab URLs are restored on launch; navigation history is retained while the app is open. Downloads, file uploads and site camera/microphone permissions are not implemented.

## Build

Install JDK 17 and the Android SDK (platform 35 and build tools 35.0.0). Set `sdk.dir` in an untracked `local.properties` file or set `ANDROID_HOME`.

```sh
./gradlew assembleDebug
```

The installable debug-signed APK is generated at `app/build/outputs/apk/debug/app-debug.apk`. A production release requires a private release signing key. This preview has not been tested on an Android device.
