## Purpose

定义用户从菜单栏或全局快捷键快速打开历史并再次使用内容的交互，包括快捷键冲突、复制回剪贴板以及自动粘贴不可用时的可恢复结果。

## ADDED Requirements

### Requirement: Open history from menu bar and shortcut
The application SHALL provide a menu bar entry and a configurable global shortcut for opening the history panel. A shortcut registration conflict SHALL be visible to the user and SHALL NOT prevent use of the menu bar entry.

#### Scenario: Open with shortcut
- **WHEN** the configured global shortcut is available and the user presses it
- **THEN** the history panel opens ready for keyboard navigation and search

#### Scenario: Shortcut conflict
- **WHEN** the configured shortcut cannot be registered
- **THEN** the application reports the conflict and the user can still open history from the menu bar

### Requirement: Copy a selected history item
The application SHALL let the user select a history item by keyboard or pointer and copy its supported representation back to the system clipboard.

#### Scenario: Copy selected item
- **WHEN** the user chooses the copy action for a text, URL, or image item
- **THEN** the system clipboard contains that item's supported representation

### Requirement: Optional automatic paste
The application SHALL offer automatic paste only when the user enables it. When permission or the destination application is unavailable, it SHALL leave the selected item copied to the clipboard and explain that the user can paste manually.

#### Scenario: Automatic paste succeeds
- **WHEN** automatic paste is enabled, required permission is granted, and the destination application is available
- **THEN** selecting the paste action returns focus to that application and attempts to paste the selected item

#### Scenario: Automatic paste unavailable
- **WHEN** the user requests automatic paste without the required permission or a valid destination
- **THEN** the selected item is copied to the clipboard and the application gives a clear manual-paste message
