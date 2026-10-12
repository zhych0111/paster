# Screenshot and Pinning Implementation Plan

> **For agentic workers:** Implement tasks in order in this session, checking each deliverable before moving on.

**Goal:** Add region screenshots, pinned images, and vertical scrolling screenshots with automatic scrolling and immediate manual takeover.

**Architecture:** Keep the current SwiftUI history UI. AppKit owns overlay and floating windows; a screenshot controller coordinates hidden windows, capture, stitching, preview, and cleanup. ScreenCaptureKit supplies scrolling frames; a read-only event tap watches for manual input.

**Tech Stack:** Swift 6 in Swift 5 mode, SwiftPM, AppKit, ScreenCaptureKit, CoreGraphics, Carbon.

## Global Constraints

- Minimum macOS version: 13.
- Preserve the existing application name, bundle ID, clipboard database, and opt-in recording policy.
- No automatic copy to the pasteboard; user-initiated screenshot copy uses the existing self-write marker.
- Keep the user’s existing history shortcut; region screenshot defaults to `⌃B` and is configurable.
- Never run automatic scrolling when manual-input observation is unavailable.
- Cap output at 25 million pixels, 60 samples, or 120 seconds.

---

### Task 1: Region capture and hotkey

- [x] Add a separately persisted screenshot shortcut and route Carbon hotkey IDs to either history or region capture.
- [x] Add asynchronous `screencapture` capture with cancellation, temporary-file cleanup, and explicit success/error outcomes.
- [x] Build and run existing self-tests.

### Task 2: Pinned images

- [x] Add floating image windows with move, resize, close, copy, and save actions; support long-image scrolling.
- [x] Limit window count and image pixels; restore previously visible windows after capture.
- [x] Exercise pin count limits and cleanup in the application self-test; drag, resize, and ordering still need GUI validation.

### Task 3: Scrolling capture

- [x] Add an AppKit selection overlay and fixed-region ScreenCaptureKit stream excluding Paster windows.
- [x] Add one-step automatic scrolling, read-only event-tap takeover, and fail-safe manual mode.
- [x] Stitch only verified overlapping frames; show preview with pin, copy, and save actions.
- [x] Test overlap, static toolbars, and mode transitions with deterministic frame fixtures.

### Task 4: Integration and verification

- [x] Wire menu, progress/stop, settings, permissions, and session cleanup.
- [x] Run `swift build`, `swift run PasterSelfTests`, `swift run Paster --self-test`, `./scripts/build-app.sh`, and signature verification.
- [x] Record real macOS permission and cross-app interaction as remaining manual validation in the README and delivery note.
