import SwiftUI
import AppKit

@main
struct YazbozNoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup("NoteLight", id: "main-window") {
            ContentView()
                .environmentObject(appState)
                .onAppear {
                    appDelegate.configure(appState: appState)
                }
                .background(MainWindowBinder(appDelegate: appDelegate))
        }
        .defaultSize(width: 900, height: 620)
        .commands {
            CommandMenu("Hızlı İşlemler") {
                // Global hotkey Carbon tarafında tek kombinasyonla kayıtlı:
                // Command + ç
                Button("Hızlı Paneli Aç/Kapat (Cmd+ç)") {
                    NotificationCenter.default.post(name: .toggleQuickCapturePanel, object: nil)
                }
            }
        }
    }
}

private struct MainWindowBinder: NSViewRepresentable {
    let appDelegate: AppDelegate

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            if let window = view.window {
                // SwiftUI WindowGroup tarafından üretilen NSWindow referansını
                // AppDelegate'e geçiriyoruz. Böylece status bar menüsünden
                // "Ana Pencereyi Aç" her zaman doğru pencereyi hedefliyor.
                appDelegate.registerMainWindow(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                appDelegate.registerMainWindow(window)
            }
        }
    }
}
