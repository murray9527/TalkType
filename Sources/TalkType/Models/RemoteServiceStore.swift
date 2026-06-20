import Foundation
import GRDB
import AppKit

@MainActor
final class RemoteServiceStore: ObservableObject {
    static let shared = RemoteServiceStore()

    private var dbQueue: DatabaseQueue?

    @Published private(set) var asrServices: [RemoteService] = []
    @Published private(set) var llmServices: [RemoteService] = []

    private init() {
        do {
            try openDatabase()
            try createTablesIfNeeded()
            try seedPresetsIfNeeded()
            reloadFromDB()
        } catch {
            print("[RemoteServiceStore] Init failed: \(error)")
        }
    }

    // MARK: - Database

    private func openDatabase() throws {
        let dir = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first!
        let supportDir = (dir as NSString).appendingPathComponent("TalkType")
        try FileManager.default.createDirectory(atPath: supportDir, withIntermediateDirectories: true)
        let dbPath = (supportDir as NSString).appendingPathComponent("services.db")
        dbQueue = try DatabaseQueue(path: dbPath)
    }

    private func createTablesIfNeeded() throws {
        try dbQueue?.write { db in
            try db.create(table: "remoteService", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("type", .text).notNull()
                t.column("baseURL", .text).notNull()
                t.column("apiKey", .text).notNull().defaults(to: "")
                t.column("modelName", .text).notNull().defaults(to: "")
                t.column("isPreset", .boolean).notNull().defaults(to: false)
            }
        }
    }

    private func seedPresetsIfNeeded() throws {
        try dbQueue?.write { db in
            let existingCount = try RemoteService.fetchCount(db)
            guard existingCount == 0 else { return }

            for preset in Self.presets {
                var record = preset
                try record.insert(db)
            }
        }
    }

    private func reloadFromDB() {
        do {
            asrServices = (try dbQueue?.read { db in
                try RemoteService.filter(Column("type") == ServiceType.asr.rawValue)
                    .order(Column("isPreset").desc, Column("rowid").asc)
                    .fetchAll(db)
            }) ?? []
            llmServices = (try dbQueue?.read { db in
                try RemoteService.filter(Column("type") == ServiceType.llm.rawValue)
                    .order(Column("isPreset").desc, Column("rowid").asc)
                    .fetchAll(db)
            }) ?? []
        } catch {
            print("[RemoteServiceStore] Reload failed: \(error)")
        }
    }

    // MARK: - CRUD

    func addService(_ service: RemoteService) {
        do {
            try dbQueue?.write { db in
                var record = service
                try record.insert(db)
            }
            reloadFromDB()
        } catch {
            print("[RemoteServiceStore] Add failed: \(error)")
        }
    }

    func updateService(_ service: RemoteService) {
        do {
            try dbQueue?.write { db in
                let record = service
                try record.update(db)
            }
            reloadFromDB()
        } catch {
            print("[RemoteServiceStore] Update failed: \(error)")
        }
    }

    func deleteService(id: String) {
        do {
            guard let service = service(id: id) else { return }
            guard !service.isPreset else {
                print("[RemoteServiceStore] Cannot delete preset service")
                return
            }
            _ = try dbQueue?.write { db in
                try RemoteService.filter(Column("id") == id).deleteAll(db)
            }
            reloadFromDB()
        } catch {
            print("[RemoteServiceStore] Delete failed: \(error)")
        }
    }

    func service(id: String) -> RemoteService? {
        do {
            return try dbQueue?.read { db in
                try RemoteService.filter(Column("id") == id).fetchOne(db)
            }
        } catch {
            return nil
        }
    }

    // MARK: - Presets

    private static let presets: [RemoteService] = [
        // ASR
        RemoteService(
            id: "preset-alibaba-asr",
            name: "阿里云 Qwen-ASR",
            type: .asr,
            baseURL: "wss://dashscope.aliyuncs.com/api-ws/v1/realtime",
            apiKey: "",
            modelName: "qwen3-asr-flash-realtime",
            isPreset: true
        ),
        // LLM
        RemoteService(
            id: "preset-alibaba-llm",
            name: "阿里云 Qwen",
            type: .llm,
            baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
            apiKey: "",
            modelName: "qwen-flash",
            isPreset: true
        ),
        RemoteService(
            id: "preset-deepseek-llm",
            name: "DeepSeek",
            type: .llm,
            baseURL: "https://api.deepseek.com",
            apiKey: "",
            modelName: "deepseek-v4-flash",
            isPreset: true
        ),
        RemoteService(
            id: "preset-xiaomi-llm",
            name: "小米 MiMo",
            type: .llm,
            baseURL: "https://api.xiaomimimo.com",
            apiKey: "",
            modelName: "mimo-v2-flash",
            isPreset: true
        ),
    ]
}

// MARK: - Model

struct RemoteService: Codable, Identifiable, FetchableRecord, MutablePersistableRecord {
    var id: String
    var name: String
    var type: ServiceType
    var baseURL: String
    var apiKey: String
    var modelName: String
    var isPreset: Bool
}

enum ServiceType: String, Codable, DatabaseValueConvertible {
    case asr
    case llm
}
