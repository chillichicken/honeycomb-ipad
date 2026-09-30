import Core
import SwiftUI

struct ContentView: View {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            switch model.screen {
            case .start:
                StartScreen(model: model)
                    .transition(.opacity)
            case .playing:
                ZStack(alignment: .top) {
                    BoardView(editor: model.editor).ignoresSafeArea()
                    TopBar(editor: model.editor) { Task { await model.goHome() } }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.screen)
        .preferredColorScheme(.dark)
        .tint(Color(Theme.accent))
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { Task { await model.saveNow() } }  // never lose work on the way out
        }
        #if DEBUG
        .task {
            // e.g. SIMCTL_CHILD_SEED_SHAPE=hexagon SIMCTL_CHILD_SEED_TILES=2000 xcrun simctl launch ...
            let env = ProcessInfo.processInfo.environment
            if let raw = env["SEED_SHAPE"], let id = ShapeID(rawValue: raw) {
                model.newPuzzle(shape: id)
                if let n = env["SEED_TILES"].flatMap(Int.init) {
                    try? await Task.sleep(for: .milliseconds(400))  // let the canvas get its size
                    model.editor.debugFill(n)
                }
            }
        }
        #endif
    }
}


