## Purpose

定义应用如何从系统剪贴板建立可靠的本地历史，包括首版支持的内容、重复复制时的行为以及无法处理内容时的边界，让用户知道哪些复制操作会被保存。

## ADDED Requirements

### Requirement: Record supported clipboard content
The application SHALL record newly copied nonempty plain text, URLs, and bitmap images while recording is enabled. It SHALL preserve enough data to preview and copy each recorded item again.

#### Scenario: Copy text
- **WHEN** recording is enabled and the user copies nonempty plain text
- **THEN** the text appears as a new or updated history item

#### Scenario: Copy image
- **WHEN** recording is enabled and the user copies a supported bitmap image within the size limit
- **THEN** the image appears with a preview and can later be copied again

#### Scenario: Unsupported or oversized content
- **WHEN** the clipboard contains only unsupported content or an item larger than 20 MiB
- **THEN** no history item is created and the application remains usable

### Requirement: Capture only observable new changes
The application SHALL begin observing clipboard changes after launch without adding the clipboard content that was present before launch. It SHALL NOT promise to capture an item overwritten before the next observation.

#### Scenario: Application launches with existing clipboard content
- **WHEN** the application starts while the clipboard already contains content
- **THEN** that existing content is not added to history solely because the application started

### Requirement: Coalesce duplicate content
The application SHALL identify repeated copies of the same supported content and update the existing item's recency and copy count instead of creating another history item.

#### Scenario: Recopy existing text
- **WHEN** the user copies text that is already represented by a history item
- **THEN** that item moves to the most recently used position and its copy count increases without adding a duplicate

### Requirement: Ignore application-originated clipboard writes
The application SHALL avoid recording a new history item when it writes a selected history item back to the system clipboard.

#### Scenario: Copy a history item again
- **WHEN** the user selects an existing item and the application writes it to the clipboard
- **THEN** no extra history item is created by that write
