import SwiftUI

@main
struct BatteryHarborApp: App {
    @StateObject private var store = BatteryStore()

    var body: some Scene {
        MenuBarExtra {
            DashboardView()
                .environmentObject(store)
                .environment(\.locale, store.interfaceLanguage.locale)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: store.snapshot.menuBarSymbol)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(menuBarColor, menuBarColor.opacity(0.45))
                Text(store.menuBarTitle)
                    .foregroundStyle(menuBarColor)
            }
        }
        .menuBarExtraStyle(.window)

        Window("电池港设置", id: "settings") {
            SettingsView()
                .environmentObject(store)
                .environment(\.locale, store.interfaceLanguage.locale)
                .harborWindowTitle(
                    L10n.text("电池港设置"),
                    identifier: HarborWindowIdentifier.settings
                )
        }
        .defaultSize(width: 760, height: 570)
        .windowResizability(.contentSize)

        Window("电池详情", id: "battery-details") {
            BatteryDetailView()
                .environmentObject(store)
                .environment(\.locale, store.interfaceLanguage.locale)
                .harborWindowTitle(L10n.text("电池详情"))
        }
        .defaultSize(width: 620, height: 560)
        .windowResizability(.contentSize)

        Window("计划执行日志", id: "schedule-logs") {
            ScheduleLogView()
                .environmentObject(store)
                .environment(\.locale, store.interfaceLanguage.locale)
                .harborWindowTitle(L10n.text("计划执行日志"))
        }
        .defaultSize(width: 560, height: 440)
        .windowResizability(.contentSize)

        Window("新增计划", id: "schedule-editor") {
            ScheduleEditorWindow()
                .environmentObject(store)
                .environment(\.locale, store.interfaceLanguage.locale)
                .harborWindowTitle(
                    L10n.text(store.scheduleBeingEdited == nil ? "新增计划" : "编辑计划")
                )
        }
        .defaultSize(width: 484, height: 434)
        .windowResizability(.contentSize)
    }

    private var menuBarColor: Color {
        .primary
    }
}

enum HarborWindowIdentifier {
    static let settings = NSUserInterfaceItemIdentifier("io.github.muu3327.batteryharbor.settings")
}

private struct HarborWindowTitleBridge: NSViewRepresentable {
    let title: String
    let identifier: NSUserInterfaceItemIdentifier?

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        updateTitle(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        updateTitle(for: nsView)
    }

    private func updateTitle(for view: NSView) {
        DispatchQueue.main.async {
            view.window?.title = title
            if let identifier {
                view.window?.identifier = identifier
            }
        }
    }
}

private extension View {
    func harborWindowTitle(
        _ title: String,
        identifier: NSUserInterfaceItemIdentifier? = nil
    ) -> some View {
        background(
            HarborWindowTitleBridge(title: title, identifier: identifier)
                .frame(width: 0, height: 0)
        )
    }
}
