cmake_minimum_required(VERSION 3.20)
# Release builds pass -DSATURN_VERSION=x.y.z (see scripts/release.sh); it becomes the app version the updater compares.
set(SATURN_VERSION "0.2.0" CACHE STRING "Saturn version")
project(SaturnBrowser VERSION ${SATURN_VERSION} LANGUAGES CXX OBJCXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OBJCXX_STANDARD 20)
set(CMAKE_OSX_DEPLOYMENT_TARGET "13.0")

# Sources — pure native macOS browser using WKWebView (no Qt/CEF needed)
set(SATURN_SOURCES
    src/main.mm
    src/SaturnWindow.mm
    src/SaturnAppDelegate.mm
    src/Supabase/SupabaseClient.mm
    src/AuthWindow.mm
    src/Settings.mm
    src/SettingsWindow.mm
    src/SetupWindow.mm
    src/SaturnShield.mm
    src/HannaClient.mm
    src/SaturnVoiceAgent.mm
    src/SaturnDownloads.mm
    src/SaturnBookmarks.mm
    src/SaturnHistory.mm
    src/SaturnSession.mm
    src/SaturnPermissions.mm
    src/HannaAgent.mm
    src/SaturnUpdater.mm
    src/SaturnReporter.mm
    src/SaturnDefaultBrowser.mm
)

add_executable(saturn ${SATURN_SOURCES})

# Frameworks: Cocoa + WebKit + AVFoundation + Speech
target_link_libraries(saturn PRIVATE
    "-framework Cocoa"
    "-framework WebKit"
    "-framework UniformTypeIdentifiers"
    "-framework QuartzCore"
    "-framework AVFoundation"
    "-framework Speech"
)

target_include_directories(saturn PRIVATE src)

# ARC + warnings + optimization
target_compile_options(saturn PRIVATE
    -Wall -Wextra -Wno-deprecated-declarations
    -O2
    -fobjc-arc
)

# Resources — SVG icons for AI assistant etc.
set(SATURN_RESOURCES
    ${CMAKE_SOURCE_DIR}/resources/ai-assistant.svg
    ${CMAKE_SOURCE_DIR}/resources/Saturn.icns
    ${CMAKE_SOURCE_DIR}/resources/saturn-logo.png
)
set_source_files_properties(${SATURN_RESOURCES} PROPERTIES MACOSX_PACKAGE_LOCATION Resources)

# App bundle (optional) — creates Saturn.app for double-click use
set_target_properties(saturn PROPERTIES
    MACOSX_BUNDLE TRUE
    MACOSX_BUNDLE_GUI_IDENTIFIER "com.saturn.browser"
    MACOSX_BUNDLE_BUNDLE_NAME "Saturn"
    MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION}
    MACOSX_BUNDLE_INFO_PLIST ${CMAKE_SOURCE_DIR}/src/Info.plist.in
    RESOURCE "${SATURN_RESOURCES}"
)

# CLI wrapper: also build non-bundle binary for `build/saturn` terminal launch
add_executable(saturn-cli ${SATURN_SOURCES})
target_link_libraries(saturn-cli PRIVATE "-framework Cocoa" "-framework WebKit" "-framework UniformTypeIdentifiers" "-framework QuartzCore" "-framework AVFoundation" "-framework Speech")
target_include_directories(saturn-cli PRIVATE src)
target_compile_options(saturn-cli PRIVATE -Wall -Wextra -Wno-deprecated-declarations -O2 -fobjc-arc)
target_compile_definitions(saturn-cli PRIVATE SATURN_CLI=1)

# Attach resources to bundle (ensures ai-assistant.svg in Resources)
target_sources(saturn PRIVATE ${SATURN_RESOURCES})
# Fallback copy for CLI/build folder
add_custom_command(TARGET saturn POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory $<TARGET_BUNDLE_CONTENT_DIR:saturn>/Resources
    COMMAND ${CMAKE_COMMAND} -E copy_if_different ${SATURN_RESOURCES} $<TARGET_BUNDLE_CONTENT_DIR:saturn>/Resources
)
add_custom_command(TARGET saturn-cli POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different ${SATURN_RESOURCES} $<TARGET_FILE_DIR:saturn-cli>
)

# Build type
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()
