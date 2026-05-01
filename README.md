# SlapForce

SlapForce is a macOS menu bar app built with Swift + SwiftUI for Apple Silicon MacBooks. It listens to the built-in accelerometer, detects slap or impact events on the machine body, and turns them into dynamic sound feedback with mode-aware layering.

The project is designed around real hardware testing on Apple Silicon laptops, not mouse or trackpad gestures.

## What It Does

- Reads Apple Silicon built-in accelerometer data through `IOKit` / `AppleSPUHIDDevice`
- Detects slap peaks with filtering, peak locking, and duplicate suppression
- Plays dynamic feedback based on impact strength
- Supports four sound modes:
  - `性感`
  - `经典`
  - `动物`
  - `惊喜`
- Supports ordered multi-clip mapping and single-clip derivation
- Keeps a menu bar workflow and can continue listening in the background

## Current State

The project is already in a usable, mature prototype state:

- slap detection is working on Apple Silicon hardware
- duplicate triggers are largely controlled
- the `性感` mode supports ordered clip progression and state-based escalation
- the UI has been compacted for smaller windows and keeps all key controls reachable
- runtime sound assets can be restored and synced back into the repository

## Project Structure

```text
SlapForce/
├── Assets/
│   ├── SoundsSeed/          # repository backup of runtime sound files
│   ├── ThemesSeed/          # reserved backup folder
│   └── ModeLibrarySeed/     # reserved backup folder
├── SlapForce/
│   ├── App/                 # app entry, menu bar, window behavior
│   ├── Models/              # data models
│   ├── Services/            # sensor, detection, playback, mode logic
│   ├── Views/               # SwiftUI interface
│   └── Resources/           # plist, entitlements, bundled resources
├── docs/
│   └── CONTINUE_WITH_CODEX.md
└── scripts/
    ├── print_resume_context.sh
    ├── restore_runtime_sounds.sh
    └── sync_runtime_sounds_to_seed.sh
```

## Key Files

- `SlapForce/Services/HIDAccelerometerService.swift`
  - AppleSPU accelerometer access and sample decoding
- `SlapForce/Services/SlapMonitor.swift`
  - slap detection, filtering, peak locking, rearm, dedupe
- `SlapForce/Services/SoundModeManager.swift`
  - sound mode routing, clip scanning, layered selection, playback
- `SlapForce/Views/ContentView.swift`
  - compact SwiftUI dashboard and tuning UI
- `SlapForce/App/SlapForceApp.swift`
  - menu bar app wiring and main window

## Runtime Sound Directory

At runtime, SlapForce primarily reads audio from:

```text
~/Library/Application Support/SlapForce/Sounds
```

Other app support folders currently used or reserved:

```text
~/Library/Application Support/SlapForce/Themes
~/Library/Application Support/SlapForce/ModeLibrary
```

## Sound Asset Workflow

This project uses a double-save strategy:

1. Runtime audio lives in:
   `~/Library/Application Support/SlapForce/Sounds`
2. Repository backup lives in:
   `Assets/SoundsSeed`

Recommended workflow:

1. Drop new clips into the runtime `Sounds` folder
2. Launch the app and click `重新扫描`
3. Test the result on real hardware
4. If the clips are worth keeping, sync them into the repo backup

Sync command:

```bash
cd "/Users/84471753qq.com/Documents/Codex/mac 声音拍打管理器/SlapForce"
./scripts/sync_runtime_sounds_to_seed.sh
```

## Naming Rules

### Mode classification

Files are auto-classified by filename keywords, case-insensitive:

- `性感` / `sexy`
- `经典` / `classic`
- `动物` / `animal`
- `惊喜` / `surprise`

### Ordered clip mapping

If a mode has numbered clips, the app prefers the numeric order.

Examples:

```text
audio_sexy_01.mp3
audio_sexy_02.mp3
audio_animal_01.wav
audio_surprise_12.m4a
经典-01.wav
动物-03.mp3
```

### Sexy mode layering

`性感` mode supports both:

- ordered numbered progression like `audio_sexy_01 ... audio_sexy_059`
- keyword hints like:
  - `soft / gentle / light / calm / 温柔 / 轻 / 柔`
  - `warm / tease / close / 暖 / 贴近 / 投入`
  - `hot / intense / moan / breath / 热 / 炽热 / 浓`

If keyword hints are missing, SlapForce falls back to ordering and signal analysis.

## Running the App

Open the project in Xcode:

```bash
open "/Users/84471753qq.com/Documents/Codex/mac 声音拍打管理器/SlapForce/SlapForce.xcodeproj"
```

Then:

1. Run the app on a real Apple Silicon MacBook
2. Open the main window
3. Click `重新扫描`
4. Click `开始监听`
5. Test light hits, heavy hits, and repeated hits on the machine body

## Development Notes

- This project is intended for real Apple Silicon hardware
- It should not be validated only with simulator behavior
- Detection tuning lives in the UI and in `AppSettings`
- The compact UI is intentionally optimized for smaller windows
- The menu bar flow remains the primary background workflow

## Restore and Resume

If the runtime sound folder is missing, restore it from the repository backup:

```bash
cd "/Users/84471753qq.com/Documents/Codex/mac 声音拍打管理器/SlapForce"
./scripts/restore_runtime_sounds.sh
```

If you want to continue development later or in a new Codex thread:

```bash
cd "/Users/84471753qq.com/Documents/Codex/mac 声音拍打管理器/SlapForce"
./scripts/print_resume_context.sh
```

Additional resume notes:

- `docs/CONTINUE_WITH_CODEX.md`
- `docs/RELEASE.md`

## Git Workflow

This project uses its own dedicated Git repository rooted at:

```text
/Users/84471753qq.com/Documents/Codex/mac 声音拍打管理器/SlapForce
```

Typical update flow:

```bash
git add .
git commit -m "your message"
git push
```

## Testing Checklist

When validating a new change, check:

- light hit response
- heavy hit response
- repeated hit continuity
- duplicate suppression
- mode switching
- sound remapping after `重新扫描`
- menu bar background listening
- compact window usability

## Repository Status

The repository already contains:

- code for the current mature interaction prototype
- restore and sync scripts
- repository-backed sound seeds
- the first large `性感` mode ordered sound set snapshot

## Release Notes

For release cleanup, signing, packaging, and notarization guidance specific to the current project state, see:

- `docs/RELEASE.md`
