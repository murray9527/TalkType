import Foundation
import SwiftUI

// App-wide user settings, persisted via UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @AppStorage("whisperModelPath") var whisperModelPath: String = ""
    @AppStorage("toneStyle") var toneStyleRaw: String = ToneStyle.none.rawValue
    @AppStorage("language") var language: String = "zh"

    var toneStyle: ToneStyle {
        get { ToneStyle(rawValue: toneStyleRaw) ?? .none }
        set { toneStyleRaw = newValue.rawValue }
    }

    var isToneConversionEnabled: Bool {
        toneStyle != .none
    }
}
