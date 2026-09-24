# Build Validation Guide

## ✅ Pre-Build Checklist

### 1. Package Dependencies
Add these via Xcode > File > Add Packages:

```
https://github.com/sindresorhus/Defaults
```

**Optional:**
```
https://github.com/airbnb/lottie-ios
```

### 2. Required Frameworks
Ensure these are linked in Build Phases > Link Binary With Libraries:

- ✅ SwiftUI.framework
- ✅ AppKit.framework
- ✅ Combine.framework
- ✅ IOKit.framework
- ✅ EventKit.framework
- ✅ AVFoundation.framework
- ✅ CoreAudio.framework
- ✅ CoreImage.framework
- ✅ QuickLook.framework
- ✅ PDFKit.framework
- ✅ Security.framework
- ✅ UserNotifications.framework
- ✅ UniformTypeIdentifiers.framework

### 3. Build Settings

**Swift Language Version:** Swift 5.9  
**Deployment Target:** macOS 13.0+  
**Build Active Architecture Only:** No (for Release)

### 4. Info.plist Permissions

Add these privacy descriptions:

```xml
<key>NSCalendarsUsageDescription</key>
<string>Mac灵动岛 needs calendar access to display your events.</string>

<key>NSRemindersUsageDescription</key>
<string>Mac灵动岛 needs reminders access.</string>

<key>NSCameraUsageDescription</key>
<string>Mac灵动岛 can use your camera for capturing moments.</string>

<key>NSMicrophoneUsageDescription</key>
<string>Mac灵动岛 needs microphone access for audio features.</string>
```

### 5. Entitlements

Enable in Signing & Capabilities:

- ✅ App Sandbox (with read/write access to User Selected Files)
- ✅ Hardened Runtime
- ✅ Outgoing Network Connections
- ✅ Calendar
- ✅ Music Folder (read-only)
- ✅ Downloads Folder (read/write)

## 🔧 Build Steps

### Clean Build
```bash
# Clean derived data
rm -rf ~/Library/Developer/Xcode/DerivedData/Mac灵动岛-*

# Clean build folder in Xcode
Product > Clean Build Folder (⇧⌘K)
```

### Build
```bash
# Via Xcode
Product > Build (⌘B)

# Via command line
xcodebuild -project Mac灵动岛.xcodeproj \
  -scheme Mac灵动岛 \
  -configuration Debug \
  clean build
```

### Run
```bash
# Via Xcode
Product > Run (⌘R)
```

## 🐛 Common Issues & Fixes

### Issue 1: "Cannot find type 'X' in scope"

**Fix:** Ensure all files are added to target membership
- Select file in Project Navigator
- Check "Mac灵动岛" target in File Inspector

### Issue 2: Missing package dependencies

**Fix:** Resolve packages
```
File > Packages > Resolve Package Versions
```

### Issue 3: Compilation errors in generated files

**Fix:** Delete derived data
```bash
rm -rf ~/Library/Developer/Xcode/DerivedData
```

### Issue 4: Namespace conflicts

**Fix:** Use explicit imports and full type names where needed

### Issue 5: "Command SwiftCompile failed"

**Fix:** 
1. Check Swift version compatibility
2. Verify all syntax is Swift 5.9 compatible
3. Check for circular dependencies

## 📊 Build Success Criteria

✅ Zero errors  
✅ Zero warnings (or documented exceptions)  
✅ All tests pass (when added)  
✅ App launches successfully  
✅ No runtime crashes on launch  
✅ All managers initialize correctly  
✅ UI renders properly  

## 🚀 Post-Build Validation

### 1. Launch Test
- App icon appears in Applications
- App opens without crash
- Menu bar item appears
- Notch overlay shows correctly

### 2. Feature Test
- Music integration works
- Battery monitoring active
- Calendar events load
- Shelf accepts drag & drop
- Settings open correctly
- Hotkeys respond

### 3. Performance Test
- Memory usage < 100MB idle
- CPU usage < 5% idle
- No memory leaks detected
- Smooth animations (60fps)

## 📝 Final Notes

- Build time: ~2-3 minutes on modern Mac
- Total file count: 224 Swift files
- Total lines: ~22,000+
- Target size: ~15-20 MB

**Status:** ✅ READY FOR BUILD
