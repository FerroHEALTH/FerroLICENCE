import AppKit
import SwiftUI

/// Launch, sign in, the ready check, then the main window.
struct RootView: View {
    let launch: Launch
    @Environment(AppModel.self) private var model
    @Environment(Updater.self) private var updater
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            switch model.phase {
            case .starting:
                ProgressView().controlSize(.large)
            case .signedOut:
                SignInView()
            case .checking:
                ReadyView()
            case .ready:
                MainView()
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .task { await boot() }
        .task(id: model.phase) {
            guard model.phase == .ready else { return }
            await withDiscardingTaskGroup { group in
                group.addTask { await syncEveryFiveMinutes() }
                group.addTask { await watchTheCard() }
                group.addTask { await updater.runDaily() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, model.phase == .ready { Task { await model.syncNow() } }
        }
    }

    func boot() async {
        if let dark = launch.dark { NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua) }
        await model.start()
        #if DEBUG
            // The section first, then the size, as a person does: a split view
            // swapped in during the resize lays out its sidebar under the title bar.
            if let screen = launch.screen { model.apply(screen) }
            await Task.yield()
            if let size = launch.windowSize, let main = NSApp.windows.first(where: { !$0.isSheet && $0.isVisible }) {
                main.setContentSize(size)
                main.center()
            }
            if let screen = launch.screen {
                if screen == .setup { openWindow(id: "setup") }
                if screen == .settings { openSettings() }
                if screen == .sync { model.showSync = true }
                let size = launch.windowSize.map { "\(Int($0.width))x\(Int($0.height))" } ?? "default"
                await Capture.run(name: "\(screen.rawValue)-\(launch.dark == true ? "dark" : "light")-\(size)", size: launch.windowSize)
            }
        #endif
    }

    func syncEveryFiveMinutes() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(300))
            await model.syncNow()
        }
    }

    /// Whether the YubiKey is plugged in, read every ten seconds.
    func watchTheCard() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(10))
            if model.issue?.step != .sign, model.setup?.running == nil { await model.refreshCard() }
        }
    }
}
