import Foundation

// Describes a downloadable Whisper model.
struct WhisperModelInfo: Identifiable, Sendable {
    let id: String          // e.g. "small"
    let displayName: String
    let fileName: String    // e.g. "ggml-small.bin"
    let sizeBytes: Int64
    let ramRequiredMB: Int
    let chineseQuality: Int // 1-5 stars
    let supportsRealtime: Bool // true if the model supports streaming/real-time transcription

    var downloadURL: URL {
        // Primary: hf-mirror.com (CN-friendly); fallback to HF directly
        URL(string: "https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main/\(fileName)")!
    }

    var localPath: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("TalkType/models/\(fileName)")
    }

    var isDownloaded: Bool {
        FileManager.default.fileExists(atPath: localPath.path)
    }

    var fileSizeDisplay: String {
        let mb = Double(sizeBytes) / 1_048_576
        return mb >= 1000 ? String(format: "%.1f GB", mb / 1024) : String(format: "%.0f MB", mb)
    }

    static let all: [WhisperModelInfo] = [
        WhisperModelInfo(id: "small",  displayName: "Small",  fileName: "ggml-small.bin",  sizeBytes: 488_000_000, ramRequiredMB: 1000, chineseQuality: 5, supportsRealtime: false),
        WhisperModelInfo(id: "medium", displayName: "Medium", fileName: "ggml-medium.bin", sizeBytes: 1_530_000_000, ramRequiredMB: 2500, chineseQuality: 5, supportsRealtime: false),
        WhisperModelInfo(id: "large-v3", displayName: "Large v3", fileName: "ggml-large-v3.bin", sizeBytes: 3_100_000_000, ramRequiredMB: 5000, chineseQuality: 5, supportsRealtime: false),
    ]
}

// Download state for a single model.
enum DownloadState: Equatable {
    case idle
    case downloading(progress: Double) // 0.0 - 1.0
    case verifying
    case done
    case failed(String)
}

// Manages downloading and tracking of Whisper model files.
@MainActor
final class ModelDownloadManager: NSObject, ObservableObject {
    static let shared = ModelDownloadManager()

    @Published var states: [String: DownloadState] = [:]

    private var tasks: [String: URLSessionDownloadTask] = [:]
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    func downloadState(for model: WhisperModelInfo) -> DownloadState {
        if model.isDownloaded { return .done }
        return states[model.id] ?? .idle
    }

    func startDownload(for model: WhisperModelInfo) {
        guard !model.isDownloaded, tasks[model.id] == nil else { return }

        // Ensure directory exists
        try? FileManager.default.createDirectory(
            at: model.localPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let task = session.downloadTask(with: model.downloadURL)
        task.taskDescription = model.id
        tasks[model.id] = task
        states[model.id] = .downloading(progress: 0)
        task.resume()
    }

    func cancelDownload(for model: WhisperModelInfo) {
        tasks[model.id]?.cancel()
        tasks[model.id] = nil
        states[model.id] = .idle
    }
}

extension ModelDownloadManager: URLSessionDownloadDelegate, @unchecked Sendable {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData _: Int64, totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription, totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in self.states[id] = .downloading(progress: progress) }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription,
              let model = WhisperModelInfo.all.first(where: { $0.id == id }) else { return }

        Task { @MainActor in self.states[id] = .verifying }

        let destination = model.localPath
        Task.detached {
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: location, to: destination)
                Task { @MainActor in
                    self.states[id] = .done
                    self.tasks[id] = nil
                    AppSettings.shared.whisperModelPath = destination.path
                }
            } catch {
                Task { @MainActor in
                    self.states[id] = .failed(error.localizedDescription)
                    self.tasks[id] = nil
                }
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                                didCompleteWithError error: Error?) {
        guard let error, let id = task.taskDescription else { return }
        let isCancelled = (error as NSError).code == NSURLErrorCancelled
        Task { @MainActor in
            self.states[id] = isCancelled ? .idle : .failed(error.localizedDescription)
            self.tasks[id] = nil
        }
    }
}
