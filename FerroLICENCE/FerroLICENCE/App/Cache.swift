import Foundation
import GitHubKit
import Register
import SwiftData

/// A file from the repository, by its git blob hash.
@Model
final class CachedBlob {
    @Attribute(.unique) var sha: String
    var data: Data

    init(sha: String, data: Data) {
        self.sha = sha
        self.data = data
    }
}

/// The register as last read from GitHub, for working offline.
@Model
final class SavedRegister {
    /// Always `main`; one row.
    @Attribute(.unique) var branch: String
    var commit: String
    var etag: String?
    var savedAt: Date
    /// The snapshot's files, JSON-encoded.
    var files: Data

    init(branch: String = "main", commit: String, etag: String?, savedAt: Date, files: Data) {
        self.branch = branch
        self.commit = commit
        self.etag = etag
        self.savedAt = savedAt
        self.files = files
    }
}

/// The offline copy: blobs for sync and the last register read.
@ModelActor
actor OfflineStore: BlobCache {
    static func container(inMemory: Bool) throws -> ModelContainer {
        try ModelContainer(
            for: CachedBlob.self, SavedRegister.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory))
    }

    func blob(_ sha: String) -> Data? {
        try? modelContext.fetch(FetchDescriptor<CachedBlob>(predicate: #Predicate { $0.sha == sha })).first?.data
    }

    func store(_ data: Data, sha: String) {
        modelContext.insert(CachedBlob(sha: sha, data: data))
        try? modelContext.save()
    }

    /// The last register read, with when and at which commit.
    func saved() -> (snapshot: Snapshot, etag: String?, savedAt: Date)? {
        guard let row = try? modelContext.fetch(FetchDescriptor<SavedRegister>()).first,
            let files = try? JSONDecoder().decode([String: Data].self, from: row.files)
        else { return nil }
        return (Snapshot(files: files, commit: row.commit), row.etag, row.savedAt)
    }

    func save(_ snapshot: Snapshot, etag: String?, at date: Date) {
        guard let files = try? JSONEncoder().encode(snapshot.files) else { return }
        let rows = (try? modelContext.fetch(FetchDescriptor<SavedRegister>())) ?? []
        if let row = rows.first {
            row.commit = snapshot.commit ?? row.commit
            row.etag = etag
            row.savedAt = date
            row.files = files
        } else {
            modelContext.insert(SavedRegister(commit: snapshot.commit ?? "", etag: etag, savedAt: date, files: files))
        }
        try? modelContext.save()
    }

    /// Forget everything, as signing out does.
    func clear() {
        try? modelContext.delete(model: CachedBlob.self)
        try? modelContext.delete(model: SavedRegister.self)
        try? modelContext.save()
    }
}
