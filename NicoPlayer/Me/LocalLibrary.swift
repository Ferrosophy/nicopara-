import Foundation
import NicoKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// 本地列表: favorites kept only on this phone, no size limit, grouped like folders.
/// Saved as JSON in Application Support after every change; export / import use the same format.
@MainActor @Observable
final class LocalLibrary {
    struct Item: Codable, Identifiable, Equatable {
        var video: VideoSummary
        var addedAt: Date
        var group: String

        var id: VideoID { video.id }
    }

    /// The file format, for the app's own storage and for export.
    struct Archive: Codable {
        var version = 1
        var exportedAt = Date()
        var groups: [String]
        var items: [Item]
    }

    static let defaultGroup = "默认"

    /// Newest added first.
    private(set) var items: [Item] = []
    /// Always starts with ``defaultGroup``.
    private(set) var groups: [String] = [LocalLibrary.defaultGroup]
    private(set) var saveError: String?

    private static let fileURL = URL.applicationSupportDirectory.appending(path: "local-list.json")

    init() {
        if let data = try? Data(contentsOf: Self.fileURL), let archive = try? Self.decoder.decode(Archive.self, from: data) {
            apply(archive)
        }
    }

    func item(for id: VideoID) -> Item? { items.first { $0.id == id } }

    /// The group's name for display (the default group's stored name is Chinese).
    func displayName(_ group: String) -> String { group == Self.defaultGroup ? L(group) : group }

    func count(in group: String) -> Int { items.count { $0.group == group } }

    func add(_ video: VideoSummary, to group: String = LocalLibrary.defaultGroup) {
        if let index = items.firstIndex(where: { $0.id == video.id }) {
            items[index].group = group
        } else {
            items.insert(Item(video: video, addedAt: Date(), group: group), at: 0)
        }
        save()
    }

    func remove(_ ids: Set<VideoID>) {
        items.removeAll { ids.contains($0.id) }
        save()
    }

    func move(_ id: VideoID, to group: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].group = group
        save()
    }

    /// Returns false when the name is empty or taken.
    @discardableResult
    func addGroup(_ name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !groups.contains(name) else { return false }
        groups.append(name)
        save()
        return true
    }

    @discardableResult
    func renameGroup(_ old: String, to new: String) -> Bool {
        let new = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard old != Self.defaultGroup, !new.isEmpty, !groups.contains(new),
              let index = groups.firstIndex(of: old) else { return false }
        groups[index] = new
        for i in items.indices where items[i].group == old { items[i].group = new }
        save()
        return true
    }

    /// Deletes the group; its videos move to the default group (nothing is lost).
    func deleteGroup(_ name: String) {
        guard name != Self.defaultGroup else { return }
        groups.removeAll { $0 == name }
        for i in items.indices where items[i].group == name { items[i].group = Self.defaultGroup }
        save()
    }

    // MARK: Export / import

    func exportArchive() -> Archive { Archive(groups: groups, items: items) }

    /// Merges an exported file: new videos and groups are added, existing ones are kept as they are.
    /// Returns how many videos were added.
    func importArchive(_ data: Data) throws -> Int {
        let archive = try Self.decoder.decode(Archive.self, from: data)
        for group in archive.groups where !groups.contains(group) { groups.append(group) }
        let known = Set(items.map(\.id))
        let fresh = archive.items.filter { !known.contains($0.id) }
        for item in fresh where !groups.contains(item.group) { groups.append(item.group) }
        items = (items + fresh).sorted { $0.addedAt > $1.addedAt }
        save()
        return fresh.count
    }

    // MARK: Storage

    private func apply(_ archive: Archive) {
        groups = [Self.defaultGroup] + archive.groups.filter { $0 != Self.defaultGroup }
        items = archive.items.sorted { $0.addedAt > $1.addedAt }
        for item in items where !groups.contains(item.group) { groups.append(item.group) }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.encoder.encode(exportArchive()).write(to: Self.fileURL, options: .atomic)
            saveError = nil
        } catch {
            saveError = String(localized: "本地列表保存失败：\(error.localizedDescription)")
        }
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// The exported file, for `fileExporter`.
struct LocalListDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
