## Purpose

定义剪贴板历史的用户控制边界，使记录必须经用户开启、可随时暂停或排除应用，并能清除本机保存的全部内容且不会产生网络上传。

## ADDED Requirements

### Requirement: Explicitly enable and pause recording
The application SHALL explain local history storage at first launch and SHALL NOT record content until the user enables recording. It SHALL let the user pause and resume recording without backfilling content copied while paused.

#### Scenario: First launch
- **WHEN** the user first opens the application
- **THEN** recording is disabled until the user explicitly enables it

#### Scenario: Pause and resume
- **WHEN** the user pauses recording, copies content, and later resumes
- **THEN** the content copied during the pause is not added to history

### Requirement: Exclude chosen applications
The application SHALL let the user manage a list of applications excluded from future capture. When it observes a clipboard change while an excluded application is identified as the foreground application, it SHALL skip that change. The interface SHALL explain that foreground attribution can be imprecise if the user switches applications before observation.

#### Scenario: Copy in excluded application
- **WHEN** the user copies content while an excluded application is observed as foreground
- **THEN** that clipboard change is not added to history

### Requirement: Configure retention and clear local history
The application SHALL let the user configure how long unpinned history is retained and SHALL provide an action that deletes all recorded items, including pinned items and image data.

#### Scenario: Clear all history
- **WHEN** the user confirms the clear-history action
- **THEN** all recorded items and their stored image data are deleted

### Requirement: Keep clipboard data local
The application SHALL store clipboard history only on the user's Mac and SHALL NOT transmit clipboard content or include it in diagnostic logs.

#### Scenario: Record item offline
- **WHEN** the user records and later retrieves an item without a network connection
- **THEN** the item remains available and no network connection is required
