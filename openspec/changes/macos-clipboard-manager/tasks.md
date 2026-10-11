## 1. Application foundation

- [x] 1.1 Create a macOS 13 Swift package with app and self-test targets; verify `swift build` and `swift run PasterSelfTests` complete.
- [x] 1.2 Add an app bundle script and Info.plist with menu bar behavior; verify `Paster.app` is created and its executable launches.

## 2. History and capture

- [x] 2.1 Implement clip models and normalization for text, URLs, and images with a 20 MiB limit; verify parsing and hash self-tests pass.
- [x] 2.2 Implement SQLite persistence, duplicate coalescing, pinned items, deletion, and schema versioning; verify reopen, duplicate, and deletion self-tests pass.
- [x] 2.3 Implement retention cleanup and text/URL search; verify 30-day, 1000-unpinned-item, pinned-item, and case-insensitive search self-tests pass.
- [x] 2.4 Implement clipboard change observation, self-write suppression, and excluded-app checks; verify injected-pasteboard self-tests cover startup baseline, capture, pause, and exclusion.

## 3. User controls and quick access

- [x] 3.1 Implement persistent settings for opt-in recording, pause, retention, excluded apps, and automatic paste; verify settings survive restart and clear-history removes all data.
- [x] 3.2 Implement menu bar status item, SwiftUI history panel, preview, search, pin, delete, and first-run explanation; verify the packaged app opens and first-run and settings controls appear.
- [x] 3.3 Register a configurable global shortcut with conflict feedback and menu bar fallback; verify hotkey registration and conflict behavior in the app self-test.
- [x] 3.4 Implement copy-back for text, URL, and image plus optional automatic paste with permission and focus fallback; verify named-pasteboard round trips and simulated permission denial in the app self-test.

## 4. Delivery

- [x] 4.1 Run `swift run PasterSelfTests`, release build, and a local `.app` smoke test; verify text, URL, and image survive app restart.
- [x] 4.2 Document build, run, local data, privacy limits, and known macOS permission behavior in README; verify commands work as written.
- [ ] 4.3 Exercise recording, search, pin, and delete with test content in the live UI; verify content and controls after reopening the app.
- [ ] 4.4 Exercise the global shortcut and automatic paste in a real destination app with the needed system permission; verify success and permission fallback.
