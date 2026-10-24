#if DEBUG
    import AppKit

    /// The screenshot tour's camera: with `-FLCapture <folder>`, the app draws
    /// each of its windows into a PNG once the screen has settled, then quits.
    /// An app may always draw its own windows, so this needs no permission.
    enum Capture {
        static var folder: URL? { UserDefaults.standard.string(forKey: "FLCapture").map { URL(filePath: $0) } }

        @MainActor
        static func run(name: String, size: CGSize?) async {
            guard let folder else { return }
            if let size, let main = NSApp.windows.first(where: { $0.title != "" && !$0.isSheet && $0.isVisible }) {
                main.setContentSize(size)
                main.center()
            }
            try? await Task.sleep(for: .seconds(2.5))
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let windows = NSApp.windows.filter { $0.isVisible && $0.frame.width > 100 }
            for (i, window) in windows.enumerated() {
                guard let view = window.contentView?.superview ?? window.contentView,
                    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
                else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                let kind =
                    window.isSheet ? "sheet" : window.title.isEmpty ? "window\(i)" : window.title.replacingOccurrences(of: " ", with: "-")
                try? rep.representation(using: .png, properties: [:])?.write(to: folder.appending(path: "\(name)--\(kind).png"))
            }
            NSApp.terminate(nil)
        }
    }
#endif
