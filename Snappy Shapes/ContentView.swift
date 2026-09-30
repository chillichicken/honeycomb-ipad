import SwiftUI

struct ContentView: View {
    @State private var editor = Editor()

    var body: some View {
        ZStack(alignment: .top) {
            BoardView(editor: editor)
                .ignoresSafeArea()
            TopBar(editor: editor)
        }
        #if DEBUG
        .task {
            // e.g. SIMCTL_CHILD_SEED_TILES=2000 xcrun simctl launch ...
            if let n = ProcessInfo.processInfo.environment["SEED_TILES"].flatMap(Int.init) {
                try? await Task.sleep(for: .milliseconds(300))  // let the canvas get its size
                editor.debugFill(n)
            }
        }
        #endif
    }
}

#Preview {
    ContentView()
}
