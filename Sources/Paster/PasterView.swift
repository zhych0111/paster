import AppKit
import SwiftUI
import PasterCore

struct PasterView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore
    @State private var search = ""
    @State private var selectedID: UUID?
    @State private var settingsVisible = false
    @State private var excludedInput: String
    @State private var showClearConfirmation = false

    init(model: AppModel) {
        self.model = model
        self.settings = model.settings
        _excludedInput = State(initialValue: model.settings.excludedBundleIDs.joined(separator: ", "))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if settingsVisible { settingsPage } else { historyPage }
        }
        .frame(minWidth: 510, minHeight: 520)
        .confirmationDialog("清空所有剪贴板历史？", isPresented: $showClearConfirmation) {
            Button("清空全部历史", role: .destructive) { model.clearAll() }
        } message: { Text("包括固定项目和图片。此操作不能撤销。") }
    }

    private var header: some View {
        HStack {
            if let icon = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "doc.on.clipboard")
            }
            Text("Paster").font(.headline)
            Spacer()
            Button(settingsVisible ? "历史" : "设置") { settingsVisible.toggle() }
                .buttonStyle(.borderless)
        }
        .padding(14)
    }

    private var historyPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !settings.recordingEnabled {
                VStack(alignment: .leading, spacing: 5) {
                    Text("开始记录剪贴板历史？").font(.headline)
                    Text("文字、链接和图片会保存在本机。你可以随时暂停、排除应用或清空历史。")
                        .font(.caption).foregroundColor(.secondary)
                    Button("启用记录") { settings.recordingEnabled = true }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                TextField("搜索历史", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { useSelected() }
                Button(settings.paused ? "继续记录" : "暂停记录") { settings.paused.toggle() }
                    .disabled(!settings.recordingEnabled)
            }
            if let message = model.message {
                Text(message).font(.caption).foregroundColor(.secondary)
            }
            let visible = model.filteredItems(search)
            if visible.isEmpty {
                Spacer()
                Text(search.isEmpty ? "还没有剪贴板历史" : "没有匹配的内容")
                    .foregroundColor(.secondary).frame(maxWidth: .infinity)
                Spacer()
            } else {
                List(selection: $selectedID) {
                    ForEach(visible) { item in
                        itemRow(item)
                            .tag(item.id)
                    }
                }
                .listStyle(.plain)
            }
            HStack {
                Text("回车复制第一条结果 · 双击列表项复制")
                    .font(.caption2).foregroundColor(.secondary)
                Spacer()
                Text("\(model.items.count) 项").font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(12)
    }

    private func itemRow(_ item: ClipItem) -> some View {
        HStack(spacing: 10) {
            if item.kind == .image, let image = model.image(for: item) {
                Image(nsImage: image).resizable().scaledToFit().frame(width: 46, height: 46)
            } else {
                Image(systemName: item.kind == .url ? "link" : "text.alignleft")
                    .frame(width: 46, height: 46)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.text ?? "图片")
                    .lineLimit(2)
                    .font(.body)
                Text(item.lastCopiedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            if item.isPinned { Image(systemName: "pin.fill").foregroundColor(.accentColor) }
            Button("复制") { model.use(item, automaticPaste: false) }
                .buttonStyle(.borderless)
            if settings.autoPasteEnabled {
                Button("粘贴") { model.use(item, automaticPaste: true) }
                    .buttonStyle(.borderless)
            }
            Menu {
                Button(item.isPinned ? "取消固定" : "固定") { model.togglePin(item) }
                Button("删除", role: .destructive) { model.delete(item) }
            } label: { Image(systemName: "ellipsis") }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.use(item, automaticPaste: false) }
    }

    private var settingsPage: some View {
        Form {
            Section("记录") {
                Toggle("启用剪贴板记录", isOn: $settings.recordingEnabled)
                Toggle("暂停记录", isOn: $settings.paused).disabled(!settings.recordingEnabled)
                Picker("保留未固定内容", selection: $settings.retentionDays) {
                    Text("1 天").tag(1); Text("7 天").tag(7); Text("30 天").tag(30)
                    Text("90 天").tag(90); Text("365 天").tag(365)
                }
            }
            Section("快捷操作") {
                Picker("打开历史快捷键", selection: $settings.hotkeyChoice) {
                    ForEach(HotkeyChoice.allCases) { choice in Text(choice.label).tag(choice) }
                }
                if !model.shortcutAvailable {
                    Text("快捷键被其他应用占用。仍可从菜单栏打开历史。")
                        .font(.caption).foregroundColor(.orange)
                }
                Picker("区域截图快捷键", selection: $settings.screenshotHotkeyChoice) {
                    ForEach(ScreenshotHotkeyChoice.allCases) { choice in Text(choice.label).tag(choice) }
                }
                if !model.screenshotShortcutAvailable {
                    Text("截图快捷键被占用。仍可从菜单栏启动区域截图。")
                        .font(.caption).foregroundColor(.orange)
                }
                Button("请求滚动截图辅助功能权限") { QuickPasteController.requestAccessibilityPermission() }
                Text("滚动截图还需要屏幕录制权限；自动滚动时需允许系统观察输入。授权不可用时可手动滚动。")
                    .font(.caption).foregroundColor(.secondary)
                Toggle("允许自动粘贴", isOn: $settings.autoPasteEnabled)
                Text("自动粘贴需要系统辅助功能权限；未授权时仍可复制后手动粘贴。")
                    .font(.caption).foregroundColor(.secondary)
                if settings.autoPasteEnabled {
                    Button("请求辅助功能权限") { QuickPasteController.requestAccessibilityPermission() }
                }
            }
            Section("隐私") {
                TextField("排除的应用 Bundle ID，用逗号分隔", text: $excludedInput)
                    .onSubmit(saveExclusions)
                Button("保存排除列表") { saveExclusions() }
                Text("复制后若很快切换应用，来源判断可能不准确。历史仅保存在本机，未进行应用层加密。")
                    .font(.caption).foregroundColor(.secondary)
                Button("清空全部历史", role: .destructive) { showClearConfirmation = true }
            }
        }
        .formStyle(.grouped)
    }

    private func saveExclusions() {
        settings.excludedBundleIDs = Array(Set(excludedInput.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })).sorted()
        model.message = "排除列表已保存"
    }

    private func useSelected() {
        let visible = model.filteredItems(search)
        if let selectedID, let item = visible.first(where: { $0.id == selectedID }) {
            model.use(item, automaticPaste: false)
        } else if let item = visible.first {
            model.use(item, automaticPaste: false)
        }
    }
}
