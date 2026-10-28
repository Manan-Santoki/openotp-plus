# Changelog

## v0.2.0 — 2026-10-27

First release of **openotp-plus**, a fork of [jeninh/OpenOTP](https://github.com/jeninh/OpenOTP) v0.1.1.

### Added
- **Verification links.** Besides codes, OpenOTP now detects sign-in, magic, confirm-email and password-reset links. A new link pops up in the screen corner as "Open sign-in link · github.com · from GitHub"; click to open it in your browser, or press Esc to dismiss. Links are also listed under "Recent links" in the menu bar (click to open, hold ⌥ to copy).
  - Precision-first detector (`LinkDetector` in `OpenOTPCore`): it scores anchor text, the surrounding text, the subject and the URL shape, and needs two independent signals to agree. Unsubscribe, footer, social, app-store and "Not you?" links are rejected outright.
  - Links that point somewhere other than the sender's own domain, or that score below the confidence bar, are shown as **Unverified** (orange).
  - Only the host is ever shown. The full URL (which carries a live token) stays in memory only, and is never opened without a click.
  - New setting: **Verification links** (on by default).
- **Esc** dismisses an offered code or link.

### Changed
- **Native AutoFill popup** ([#1](https://github.com/jeninh/OpenOTP/issues/1)). The floating pill is redesigned after macOS's own "Fill code … From Messages" suggestion: a menu-material card with a single highlighted row ("Fill code 123456 / From GitHub"), placed directly under the focused field and flipped above it near the bottom of the screen. Click anywhere on the row to fill.
- **The popup now follows your focus.** A new code stays on offer for 5 minutes: the popup appears under whichever empty text field you focus, hides when you click away or start typing, and comes back when you return. Previously it disappeared after 15 seconds or the first outside click.
- Low-confidence codes are now shown with a distinct **Unverified** treatment and always show the sender, as the detector's contract requires.
- `CodeStore` is now a generic `DetectionStore`, shared by codes and links (`CodeStore` / `LinkStore` typealiases). Its `onNewCode` callback is renamed `onNewItem`.

### Fixed
- Universal (arm64 + x86_64) release builds on newer SwiftPM, which writes both slices to the same output folder.
- Accessibility lookups of the focused field time out after 0.25 s instead of stalling on an app that has stopped responding.

### Notes
- The DMG is signed with a self-signed certificate, not an Apple Developer ID, and isn't notarized. Install with the one-line script (curl downloads aren't quarantined), or right-click → Open the first time.
- Installing over the original OpenOTP keeps your accounts and settings (same bundle ID), but you'll need to re-grant Accessibility access and click "Always Allow" on the Keychain prompt once.
