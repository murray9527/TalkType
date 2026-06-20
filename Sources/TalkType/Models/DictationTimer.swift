import Foundation

/// A single-use timer bound to a specific event phase (recording, processing, etc.).
///
/// ```swift
/// let t = DictationTimer(maxSeconds: 60)
/// t.onTick = { secs in /* update UI */ }
/// t.onLimit = { /* auto-stop */ }
/// t.start()
/// // later:
/// t.stop()
/// ```
final class DictationTimer: @unchecked Sendable {
    /// Maximum seconds before `onLimit` fires. `nil` = no limit.
    let maxSeconds: Int?

    /// Called every second with the current elapsed count.
    var onTick: ((Int) -> Void)?

    /// Called once when `elapsed >= maxSeconds`.
    var onLimit: (() -> Void)?

    private var task: Task<Void, Never>?
    private(set) var elapsed = 0

    init(maxSeconds: Int? = nil) {
        self.maxSeconds = maxSeconds
    }

    /// Start (or restart) the timer.
    func start() {
        reset()
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let owner = self
                await MainActor.run {
                    guard let owner else { return }
                    owner.elapsed += 1
                    owner.onTick?(owner.elapsed)
                    if let max = owner.maxSeconds, owner.elapsed >= max {
                        owner.stop()
                        owner.onLimit?()
                    }
                }
            }
        }
    }

    /// Stop the timer.
    func stop() {
        task?.cancel()
        task = nil
    }

    /// Stop and reset to 0.
    func reset() {
        stop()
        elapsed = 0
    }
}
