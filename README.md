# MacBon — Tap Your Mac

<p align="center">
  <img src="TapMac/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="MacBon Icon">
</p>

<p align="center">
  <strong>Turn your MacBook's body into a gesture controller.</strong><br>
  Tap the chassis to mute, lock the screen, play audio, and more.
</p>

<p align="center">
  <a href="https://github.com/howardfung7-prog/macbon/releases/latest"><img src="https://img.shields.io/github/v/release/howardfung7-prog/macbon?style=flat-square" alt="Release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/howardfung7-prog/macbon?style=flat-square" alt="License"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/chip-Apple%20Silicon-orange?style=flat-square" alt="Apple Silicon">
</p>

---

## What is MacBon?

Every Apple Silicon MacBook has a built-in accelerometer sitting idle. **MacBon wakes it up.**

Tap the side of your MacBook — not the keyboard, not the trackpad, the actual metal body — and trigger actions instantly. No mouse. No shortcuts. Just tap.

## Features

| | Feature | Description |
|---|---------|-------------|
| 1x | **Single Tap** | Mute/unmute system audio |
| 2x | **Double Tap** | Lock screen instantly |
| 3x | **Triple Tap** | Quick memo, custom audio, or any action you choose |

### 6 Built-in Actions

**Productivity**
- **Mute Toggle** — Silence everything with one tap
- **Lock Screen** — Walk away securely
- **Quick Memo** — Open Notes instantly

**Fun**
- **Custom Audio** — Drop MP3s into `~/MacBon/Sounds/` and tap to play
- **Random Encouragement** — Hear a motivational message when you need it
- **Voice Clock** — Tap to hear the current time

### More

- **800Hz accelerometer sampling** with smart filtering — won't mistake typing for tapping
- **< 50ms response time** from tap to action
- **6 languages** — English, Chinese (Simplified & Traditional), Japanese, German, French
- **100% offline** — Zero internet, zero tracking, zero microphone access
- **Auto-sleep** — Pauses when screen is off or lid is closed
- **Menu bar app** — Lives quietly in your menu bar

## Requirements

- macOS 14 Ventura or later
- Apple Silicon MacBook (M1/M2/M3/M4)
- Accessibility permission (for actions like lock screen)

> Desktop Macs (Mac Mini, Mac Studio, Mac Pro) don't have the accelerometer sensor.

## Installation

### Homebrew (Recommended)

```bash
brew tap howardfung7-prog/tap
brew install --cask macbon
```

### Download DMG

1. Download the latest `.dmg` from [Releases](https://github.com/howardfung7-prog/macbon/releases/latest)
2. Drag `MacBon.app` into `/Applications`
3. Right-click → Open (first time only, to bypass Gatekeeper)
4. Grant permissions when prompted:
   - **System Settings → Privacy → Accessibility → Allow MacBon**

### Build from Source

```bash
git clone https://github.com/howardfung7-prog/macbon.git
cd macbon
xcodebuild -project MacBon.xcodeproj -scheme MacBon -configuration Release build
```

## Project Structure

```
TapMac/
├── App/
│   ├── main.swift              # Entry point
│   └── AppDelegate.swift       # App lifecycle & menu bar
├── Core/
│   ├── AccelerometerReader.swift  # 800Hz accelerometer sampling
│   └── TapDetector.swift          # Tap pattern recognition
├── Actions/
│   ├── ActionType.swift        # Action definitions
│   └── ActionManager.swift     # Action execution
├── Models/
│   └── AppSettings.swift       # UserDefaults persistence
├── Views/
│   └── SettingsView.swift      # SwiftUI settings panel
└── Resources/
    ├── Assets.xcassets/        # App icons
    ├── Info.plist
    └── *.lproj/                # Localization (6 languages)
```

## How It Works

1. **AccelerometerReader** accesses the MacBook's built-in Bosch BMI286 accelerometer at ~800Hz
2. **TapDetector** analyzes acceleration spikes, filtering out keyboard typing and normal movement
3. When a tap pattern (1x, 2x, or 3x) is recognized, the configured action fires via **ActionManager**

The entire pipeline runs locally with no network access.

## Configuration

| Setting | Default | Range |
|---------|---------|-------|
| Sensitivity | 0.5 | 0.0 (firm tap) – 1.0 (light touch) |
| Tap Gap | 0.8s | 0.5s – 1.5s |
| Cooldown | 0.8s | 0.3s – 2.0s |
| Volume | 0.7 | 0.0 – 1.0 |

## Website

Visit [macbon.tech](https://macbon.tech) for more info.

## License

[MIT](LICENSE) — Use it, fork it, tap it.

## Contributing

Contributions are welcome! Feel free to open issues or submit pull requests.

Ideas for contributions:
- New action types (screenshot, app launcher, Shortcuts integration)
- Additional language translations
- Homebrew Cask formula
- Tap pattern visualization
