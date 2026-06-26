import Foundation
import Combine

/// User-facing preferences, persisted in UserDefaults.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    /// Overall window opacity (0.5 ... 1.0). The frosted material already adds translucency.
    @Published var opacity: Double { didSet { d.set(opacity, forKey: "opacity") } }
    /// Keep the widget above normal windows.
    @Published var alwaysOnTop: Bool { didSet { d.set(alwaysOnTop, forKey: "alwaysOnTop") } }
    /// Use the macOS frosted-glass material (matches system controls). Otherwise a flat dark panel.
    @Published var frosted: Bool { didSet { d.set(frosted, forKey: "frosted") } }
    /// How often to refresh, in seconds.
    @Published var refreshSeconds: Double { didSet { d.set(refreshSeconds, forKey: "refreshSeconds") } }

    private init() {
        opacity = (d.object(forKey: "opacity") as? Double) ?? 0.92
        alwaysOnTop = (d.object(forKey: "alwaysOnTop") as? Bool) ?? true
        frosted = (d.object(forKey: "frosted") as? Bool) ?? true
        refreshSeconds = (d.object(forKey: "refreshSeconds") as? Double) ?? 60
    }
}
