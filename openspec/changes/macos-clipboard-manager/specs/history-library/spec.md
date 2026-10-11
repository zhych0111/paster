## Purpose

定义用户如何在本机查找和整理已保存的剪贴板内容，以及删除、固定、自动清理和重新启动后的可见结果，确保历史既方便使用又不会无限增长。

## ADDED Requirements

### Requirement: Browse and search history
The application SHALL show pinned items and recent items in a browsable history. It SHALL search the text of plain text and URL items without requiring an exact case match. Image items SHALL remain browsable with a preview.

#### Scenario: Search saved text
- **WHEN** the user enters a search term matching part of a saved text or URL item
- **THEN** the matching item appears in the results

#### Scenario: Browse image item
- **WHEN** the user opens history containing an image item
- **THEN** the image item has a visible preview

### Requirement: Pin and delete items
The application SHALL let users pin or unpin a history item and delete an individual item. A deleted image item SHALL no longer retain its stored image data.

#### Scenario: Pin item
- **WHEN** the user pins an item
- **THEN** it remains available in the pinned section until the user unpins or deletes it

#### Scenario: Delete image
- **WHEN** the user deletes a saved image item
- **THEN** the item disappears from history and its stored image data is removed

### Requirement: Persist and limit history
The application SHALL preserve history across application restarts. By default it SHALL remove unpinned items older than 30 days and keep at most 1000 unpinned items; pinned items SHALL be exempt from automatic removal.

#### Scenario: Restart application
- **WHEN** the user quits and reopens the application
- **THEN** previously retained items and their pinned states remain available

#### Scenario: Retention cleanup
- **WHEN** an unpinned item becomes older than the configured retention period
- **THEN** the item is removed from history and any stored image data is deleted

#### Scenario: Count limit reached
- **WHEN** adding an item would make the number of unpinned items exceed 1000
- **THEN** the oldest unpinned item is removed while pinned items remain
