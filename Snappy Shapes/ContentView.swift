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
                    #if DEBUG
                    // UI tests pinch inside this middle square: XCUITest starts an inward pinch
                    // with the fingers at the element's edges, which on a full screen land on
                    // the home-indicator and toolbar zones a real pinch never starts in
                    Color.clear.frame(width: 500, height: 500)
                        .allowsHitTesting(false)
                        .accessibilityElement()
                        .accessibilityIdentifier("pinchpad")
                        .frame(maxHeight: .infinity)
                    #endif
                    TopBar(model: model) { Task { await model.goHome() } }
                    #if DEBUG
                    VStack(spacing: 10) {
                        Button { model.editor.zoomStep(1 / 1.4) } label: {
                            Image(systemName: "minus").font(.title2.weight(.semibold)).frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Zoom out")
                        Button { model.editor.zoomStep(1.4) } label: {
                            Image(systemName: "plus.magnifyingglass").font(.title3).frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Zoom in")
                    }
                    .foregroundStyle(Color(Theme.text))
                    .panel(Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(16)
                    .padding(.bottom, 8)
                    #endif
                    if let toast = model.editor.toast {
                        Text(toast)
                            .font(.subheadline)
                            .foregroundStyle(Color(red: 1, green: 0.7, blue: 0.7))
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .panel(Capsule())
                            .padding(.top, 76)
                            .transition(.opacity)
                    }
                }
                .transition(.opacity)
            }
            if let next = model.pendingShape {
                ConfirmOverlay(
                    message: "A puzzle can only use one shape — switching clears the current board. Continue?",
                    confirmLabel: "Switch to \(TileShape.of(next).label)",
                    onConfirm: { Task { await model.confirmShapeSwitch() } },
                    onCancel: { model.cancelShapeSwitch() }
                ) {
                    HStack(spacing: 16) {
                        ShapeIcon(id: model.editor.board.shape.id).frame(width: 56, height: 56)
                        Text("→").font(.title).foregroundStyle(Color(Theme.muted))
                        ShapeIcon(id: next).frame(width: 56, height: 56)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.pendingShape)
        .animation(.easeInOut(duration: 0.2), value: model.editor.toast)
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


