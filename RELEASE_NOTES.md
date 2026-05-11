# MacBon 1.3.0

## 🔒 Security patch

This release tightens device identity to prevent UI-spoofing if a user copies their preferences plist to another Mac.

### What changed

- **Hardware-bound device identity**: On every launch, the app re-reads the Mac's `IOPlatformUUID` and verifies it matches the cached `device_id`. If they don't match (e.g., preferences plist copied from another Mac), **all local state is wiped** and the device starts fresh. This prevents a stale UI from displaying another Mac's balance.

### Why this matters

In v1.2.0, if someone copied `~/Library/Preferences/tech.macbon.app.plist` from a friend's Mac, they would see the friend's BON balance in the app — even though no actual rewards or signing keys were transferred, the displayed number was misleading. v1.3.0 now detects this and resets cleanly.

### What it doesn't change

- Server-side balances are unaffected (those have always been keyed by hardware device_id)
- Secure Enclave / CryptoKit signing keys remain the strongest barrier
- Solana address binding is still permanent per device

---

## Install

1. Download `MacBon.dmg`
2. Open the DMG, drag MacBon to Applications
3. Launch from Applications

Existing v1.2.0 users: balance and progress are preserved through the update (your hardware identity stays the same).

---

🌐 https://macbon.tech · 📊 https://macbon.tech/tokenomics.html
