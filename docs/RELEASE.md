# SlapForce Release Guide

This guide is for taking the current SlapForce prototype and turning it into a distributable macOS app.

It is written for the current repository state, not an imaginary clean-room release build.

## Current Project State

Before packaging, it helps to be clear about what the app looks like today:

- it is built for real Apple Silicon MacBook hardware
- it reads the built-in accelerometer through `AppleSPUHIDDevice`
- it currently runs with **App Sandbox disabled**
- it currently launches in a **debug-friendly regular app mode** with a Dock icon and auto-front behavior
- it already has a menu bar workflow, but it is not yet configured as a pure release-only menu bar app

That means:

- **direct distribution is realistic**
- **Mac App Store distribution is not the current target**

If you want App Store distribution later, the first major question will be whether the accelerometer access path can still work under the required sandbox model.

## Recommended Release Target

For the current implementation, the recommended target is:

- **signed Developer ID app**
- **notarized by Apple**
- distributed directly as:
  - a zipped `.app`
  - or a `.dmg` later if desired

## Pre-Release Cleanup Checklist

Before cutting a release build, go through these items.

### 1. Switch from debug launch behavior to release launch behavior

The current `AppDelegate` is intentionally debug-oriented:

- it sets activation policy to `.regular`
- it brings the app forward automatically
- it tries to open the main window on launch

That is useful in Xcode, but for release it is worth deciding between:

1. **regular app with Dock icon**
2. **true menu bar utility**

If you want the cleaner menu bar experience for release:

- change `AppDelegate.swift`
- remove the forced `activate(...)`
- remove the delayed `newWindowForTab` / window fronting logic
- set launch behavior to a menu bar-first flow

If you want a more approachable first public build, keeping the Dock icon is also acceptable.

### 2. Decide whether release should hide the Dock icon

`Info.plist` currently contains:

```xml
<key>LSUIElement</key>
<false/>
```

That means SlapForce currently behaves like a normal app, not a background-only menu bar app.

For release:

- set `LSUIElement` to `true` if you want a pure menu bar utility
- keep it `false` if you want a more standard macOS app experience

Recommendation:

- for wider testing: keep `false`
- for a polished utility release: move to `true` after you are happy with the menu bar workflow

### 3. Version the build properly

Update these values in `SlapForce/Resources/Info.plist` before each release:

- `CFBundleShortVersionString`
- `CFBundleVersion`

Suggested pattern:

- `CFBundleShortVersionString`: user-facing version like `1.0.0`
- `CFBundleVersion`: build number like `100`, `101`, `102`

### 4. Review entitlements

Current entitlements include:

- sandbox disabled
- user-selected read-only file access
- music asset read-only access
- `mach-lookup` exception for `com.apple.audioanalyticsd`

This is fine for direct distribution if it works on hardware, but before release you should confirm:

- no unnecessary entitlement remains from debugging
- imported sounds still load correctly
- hardware accelerometer access still works after signing

### 5. Clean presentation details

Before shipping, it is worth checking:

- app icon
- app name
- About panel text
- default window size
- whether debug-heavy controls should remain visible by default
- whether the advanced tuning panel should start collapsed

## Release Validation Checklist

Run this checklist on a real Apple Silicon MacBook:

- launch app outside Xcode
- confirm menu bar icon appears
- confirm main window opens correctly
- test `重新扫描`
- test light hits
- test heavy hits
- test repeated hits
- test all four modes
- test runtime sounds loaded from `~/Library/Application Support/SlapForce/Sounds`
- test if imported files still play after signing
- test background listening
- test `阻止休眠` behavior
- test relaunch after quitting

Also verify on a second machine if possible.

## Signing in Xcode

In Xcode:

1. Select the `SlapForce` target
2. Open **Signing & Capabilities**
3. Select your Apple Developer Team
4. Use a unique bundle identifier, for example:

```text
com.yourname.SlapForce
```

5. Build and run once outside pure debug assumptions

For direct distribution, you generally want a **Developer ID Application** certificate, not just local development signing.

## Build and Archive

Recommended archive flow:

1. Open:

```text
SlapForce.xcodeproj
```

2. Set the scheme to `SlapForce`
3. Choose **Any Mac (Apple Silicon)** or the appropriate Mac destination
4. Select:

```text
Product > Archive
```

5. When Organizer opens:
   - validate the archive
   - export the app

For early direct testing, you can export a signed `.app`.

## Recommended Distribution Flow

The simplest reliable release flow for the current app is:

1. archive in Xcode
2. export signed `.app`
3. zip the `.app`
4. notarize the zip
5. staple if needed
6. test the notarized artifact on another Mac

## Zip for Notarization

After export, create a zip with `ditto`:

```bash
ditto -c -k --keepParent "SlapForce.app" "SlapForce.zip"
```

Using `ditto` is the normal macOS-friendly way to prepare an app bundle archive.

## Notarization

Apple's current notarization tooling uses `notarytool`.

High-level flow:

1. create a notarization profile or use Apple ID / App Store Connect credentials
2. submit the zip
3. wait for acceptance
4. staple the ticket if needed
5. verify the result

Example pattern:

```bash
xcrun notarytool submit "SlapForce.zip" --keychain-profile "AC_PROFILE" --wait
```

Then, if you are distributing the `.app` directly after notarization:

```bash
xcrun stapler staple "SlapForce.app"
```

If you distribute in a DMG later, you would staple the final distributable container as appropriate.

## Gatekeeper Verification

After signing and notarization, test with:

```bash
spctl -a -vv "SlapForce.app"
```

And optionally:

```bash
xcrun stapler validate "SlapForce.app"
```

What you want to confirm:

- Gatekeeper accepts the app
- the notarization ticket is valid
- the app launches outside Xcode without hardware regressions

## Known Release Risk for This Project

The main release risk is not generic signing. It is this:

- SlapForce depends on Apple Silicon accelerometer access through a hardware-specific path
- the app currently works in its present non-sandbox direct-distribution shape
- signing, hardened runtime, and notarization should still be tested carefully on real hardware

So the most important post-archive test is:

- does the signed, exported, standalone app still receive accelerometer data and trigger sound correctly?

## Suggested Release Sequence

This is the most sensible order from the current repo state:

1. keep this prototype branch stable
2. do a small “release cleanup” commit
   - launch behavior
   - icon
   - versioning
   - default collapsed debug sections
3. archive from Xcode
4. export signed app
5. notarize
6. test on a second Apple Silicon Mac if possible
7. only then call it `v1.0`

## Apple References

These official Apple pages are the key references for the release path:

- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing_the_notarization_workflow)
- [App Sandbox](https://developer.apple.com/documentation/security/app_sandbox)
