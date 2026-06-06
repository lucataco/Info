import OSLog

/// Centralized, low-overhead logging.
///
/// We deliberately avoid logging on the sampling hot path. `os.Logger` only
/// materializes messages when something is actually reading the log, so these
/// are cheap, but we still keep per-tick logging at `.debug`/`.trace` so it is
/// disabled by default and never spams the unified log (unlike Stats, which
/// wrote `error(...)` to stderr at 1 Hz).
enum Log {
    static let subsystem = "com.info.app"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let engine = Logger(subsystem: subsystem, category: "engine")
    static let cpu = Logger(subsystem: subsystem, category: "cpu")
    static let gpu = Logger(subsystem: subsystem, category: "gpu")
    static let memory = Logger(subsystem: subsystem, category: "memory")
    static let network = Logger(subsystem: subsystem, category: "network")
    static let menubar = Logger(subsystem: subsystem, category: "menubar")
    static let onboarding = Logger(subsystem: subsystem, category: "onboarding")

    /// Signposter for Instruments "Points of Interest" / sampling intervals.
    static let signposter = OSSignposter(subsystem: subsystem, category: "sampling")
}
