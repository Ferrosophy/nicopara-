import NicoKit
import SwiftUI

/// 本地列表: filter by group, search titles, swipe to delete, move between groups,
/// export / import as a JSON file.
struct LocalListView: View {
    @Environment(LocalLibrary.self) private var library
    @Environment(ListenStore.self) private var listen
    @Environment(AccountStore.self) private var account
    @Environment(AppSettings.self) private var settings
    @State private var group: String?   // nil = 全部
    @State private var searchText = ""
    @State private var showingGroups = false
    @State private var exporting: LocalListDocument?
    @State private var importing = false
    @State private var message: String?

    private var shown: [LocalLibrary.Item] {
        library.items.filter { item in
            (group == nil || item.group == group)
                && (searchText.isEmpty || item.video.title.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        groupChip(nil, title: String(localized: "全部 \(library.items.count)"))
                        ForEach(library.groups, id: \.self) { name in
                            groupChip(name, title: "\(library.displayName(name)) \(library.count(in: name))")
                        }
                    }
                }
                .listRowSeparator(.hidden)
            }

            ForEach(shown) { item in
                NavigationLink(value: item.video.id) { VideoRow(video: item.video) }
                    .swipeActions {
                        Button("删除", role: .destructive) { library.remove([item.id]) }
                    }
                    .contextMenu {
                        Menu("移到分组") {
                            ForEach(library.groups, id: \.self) { name in
                                Button {
                                    library.move(item.id, to: name)
                                } label: {
                                    if name == item.group { Label(name, systemImage: "checkmark") } else { Text(name) }
                                }
                            }
                        }
                        Button("删除", systemImage: "trash", role: .destructive) { library.remove([item.id]) }
                    }
            }

            if shown.isEmpty {
                Text(library.items.isEmpty ? "本地列表是空的。在视频页点「本地列表」加入。" : "没有符合条件的视频")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
            if let error = library.saveError {
                Text(error).foregroundStyle(.red).font(.footnote)
            }
        }
        .listStyle(.plain)
        // Always visible, not tucked away when the list scrolls.
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索标题")
        .navigationTitle("本地列表")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button("听视频", systemImage: "headphones") {
                    // The list as shown (current group and search).
                    listen.start(shown.map(\.video), title: group.map(library.displayName) ?? L("本地列表"),
                                 client: account.client, audioPreference: settings.defaultAudioQuality)
                }
                .disabled(shown.isEmpty)
                Button("管理分组", systemImage: "folder") { showingGroups = true }
                Button("导出", systemImage: "square.and.arrow.up") { export() }
                Button("导入", systemImage: "square.and.arrow.down") { importing = true }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .sheet(isPresented: $showingGroups) { GroupManager() }
        .fileExporter(
            isPresented: Binding(get: { exporting != nil }, set: { if !$0 { exporting = nil } }),
            document: exporting, contentType: .json,
            defaultFilename: "nicopara-本地列表-\(Date().formatted(.iso8601.year().month().day()))"
        ) { result in
            if case .failure(let error) = result { message = String(localized: "导出失败：\(error.localizedDescription)") }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            importFile(result)
        }
        .alert("本地列表", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好") {}
        } message: {
            Text(message ?? "")
        }
    }

    private func groupChip(_ name: String?, title: String) -> some View {
        Button { group = name } label: {
            Text(title)
                .font(.footnote)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(group == name ? Color.white : Color.primary)
                .background(group == name ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private func export() {
        do {
            exporting = LocalListDocument(data: try LocalLibrary.encoder.encode(library.exportArchive()))
        } catch {
            message = String(localized: "导出失败：\(error.localizedDescription)")
        }
    }

    private func importFile(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let added = try library.importArchive(Data(contentsOf: url))
            message = String(localized: "导入完成：新增 \(added) 个视频（已有的保持不变）")
        } catch {
            message = String(localized: "导入失败：不是 nicopara 导出的本地列表文件（\(error.localizedDescription)）")
        }
    }
}

/// Create, rename and delete groups. Deleting a group moves its videos to 默认.
private struct GroupManager: View {
    @Environment(LocalLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var renaming: String?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            List {
                Section("新建分组") {
                    HStack {
                        TextField("分组名", text: $newName)
                        Button("添加") {
                            if library.addGroup(newName) { newName = "" }
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Section {
                    ForEach(library.groups, id: \.self) { name in
                        HStack {
                            Text(name)
                            Spacer()
                            Text("\(library.count(in: name))").foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            if name != LocalLibrary.defaultGroup {
                                Button("删除", role: .destructive) { library.deleteGroup(name) }
                                Button("重命名") {
                                    renameText = name
                                    renaming = name
                                }
                            }
                        }
                    }
                } footer: {
                    Text("左滑分组可以重命名或删除；删除分组后，里面的视频会移到「默认」。")
                }
            }
            .navigationTitle("管理分组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .alert("重命名分组", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("新名字", text: $renameText)
                Button("取消", role: .cancel) {}
                Button("确定") {
                    if let old = renaming { library.renameGroup(old, to: renameText) }
                }
            }
        }
    }
}
