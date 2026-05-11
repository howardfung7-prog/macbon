# MacBon 1.2.0

## 🎉 BON Token Mining is now live

The big update — every MacBook tap now earns you **BON** (formerly TAP), the work-focused token. Network state and your earnings sync in real time.

## What's new

### Mining
- 🪙 **Token rename**: `TAP` → **`BON`**
- 🌍 **Live network stats** in the Mining tab — Active Macs, BON Paid, Locked Reserve, Today's Pool — refresh every 30 s
- 🔒 **Pre-Mining Reserve**: 50% of rewards locked until network reaches 50,000 Macs (unlocks retroactively to early miners)
- 📅 **Daily 6-hour quota** with proper UTC handling
- 🛡️ **Hardware-signed reports** via Secure Enclave (anti-curl / anti-replay)

### Setup & UX
- Confirmation alert before binding Solana wallet — one-time, immutable
- One free address modification before TGE (visible "修改" button)
- Mining tab now scrollable; UI shifted to BON brand purple throughout
- Improved character-level Solana address validation with specific error hints

### Localization
- All 6 languages (zh-Hans / zh-Hant / en / ja / de / fr) brought to 93 keys parity
- English encouragement phrases added (previously silent)
- Headline updated: **"6 hrs = Daily Work Goal in the AI Age"**

### Anti-cheat
- Single-instance enforcement (running twice gets blocked)
- Device ID strictly bound to hardware UUID
- 10-device cap per Solana address
- Tap count sanity limits

## Hardware requirement

**Apple Silicon MacBook only** — M1 / M2 / M3 / M4 / M5. Intel Macs and desktop Macs (Mac mini / Studio / Pro) lack the chassis accelerometer.

## Install

1. Download `MacBon.dmg`
2. Open the DMG, drag MacBon to Applications
3. Launch from Applications (first time: right-click → Open to bypass Gatekeeper warning)
4. Grant accessibility permissions when asked

Want to mine? Switch to the **挖矿 / Mining** tab and bind your Solana wallet.

---

🌐 https://macbon.tech · 📊 https://macbon.tech/tokenomics.html
