import SwiftUI
import Core

/// Mode buttons on the left, actions ("+", delete) on the right. In recolor
/// mode a color strip drops down underneath.
struct TopBar: View {
    let model: AppModel
    let onHome: () -> Void
    @State private var showingShapes = false

    private var editor: Editor { model.editor }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button { showingShapes = true } label: {
                    ShapeIcon(id: editor.board.shape.id).frame(width: 30, height: 30).frame(width: 44, height: 44)
                }
                .panel(Circle())
                .accessibilityLabel("Shape")
                .popover(isPresented: $showingShapes, arrowEdge: .top) { shapePicker }

                Button(action: onHome) {
                    Image(systemName: "folder").font(.title3).frame(width: 44, height: 44)
                }
                .foregroundStyle(Color(Theme.text))
                .panel(Circle())
                .accessibilityLabel("Puzzles")

                HStack(spacing: 4) {
                    modeButton(.grab, "hand.draw", "Grab")
                    modeButton(.select, "rectangle.dashed", "Select")
                    modeButton(.recolor, "drop.fill", "Recolor", tint: Color(tile: editor.paintColor))
                }
                .padding(4)
                .panel(Capsule())

                Spacer()

                if editor.selectionCount > 0 {
                    Button(role: .destructive) { editor.deleteSelection() } label: {
                        Label("\(editor.selectionCount)", systemImage: "trash")
                            .padding(.horizontal, 14).padding(.vertical, 10)
                    }
                    .panel(Capsule())
                }

                #if DEBUG
                Menu {
                    Button("Add 1,000 tiles") { editor.debugFill(1_000) }
                    Button("Add 10,000 tiles") { editor.debugFill(10_000) }
                    Button("Add 100,000 tiles") { editor.debugFill(100_000) }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                }
                .foregroundStyle(Color(Theme.text))
                .panel(Circle())
                #endif

                RepeatButton(accessibilityLabel: "Add tile", action: { editor.addTile() }) {
                    Image(systemName: "plus").font(.title2.weight(.semibold)).frame(width: 44, height: 44)
                        .foregroundStyle(Color(Theme.text))
                        .panel(Circle())
                }
            }

            if editor.mode == .recolor {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Palette.colors, id: \.self) { color in
                            Button { editor.pick(color: color) } label: {
                                Circle().fill(Color(tile: color)).frame(width: 34, height: 34)
                                    .overlay(Circle().stroke(Color(Theme.accent).opacity(color == editor.paintColor ? 1 : 0), lineWidth: 3))
                            }
                        }
                    }
                    .padding(8)
                }
                .panel(Capsule())
                .frame(maxWidth: 520)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var shapePicker: some View {
        VStack(spacing: 4) {
            ForEach([TileShape.triangle, .hexagon, .diamond], id: \.id) { shape in
                Button {
                    showingShapes = false
                    model.requestShapeSwitch(to: shape.id)
                } label: {
                    HStack(spacing: 12) {
                        ShapeIcon(id: shape.id).frame(width: 34, height: 34)
                        Text(shape.label)
                        Spacer(minLength: 12)
                        if shape.id == editor.board.shape.id { Image(systemName: "checkmark") }
                    }
                    .foregroundStyle(Color(Theme.text))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(minWidth: 190)
                }
            }
        }
        .padding(8)
        .presentationCompactAdaptation(.popover)
    }

    private func modeButton(_ mode: Mode, _ symbol: String, _ label: String, tint: Color? = nil) -> some View {
        Button { editor.mode = mode } label: {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(editor.mode == mode ? Color(Theme.textBright) : (tint ?? Color(Theme.text)))
                .frame(width: 52, height: 44)
                .background(editor.mode == mode ? Color(Theme.accent) : Color.clear, in: Capsule())
        }
        .accessibilityLabel(label)
    }
}
