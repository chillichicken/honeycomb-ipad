import SwiftUI
import Core

struct StartScreen: View {
    let model: AppModel

    private let order: [ShapeID] = [.triangle, .hexagon, .diamond]

    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 28) {
                Text("Snappy Shapes")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(Theme.textBright))
                Text("Pick a shape to build with")
                    .foregroundStyle(Color(Theme.muted))
                    .padding(.top, -14)

                HStack(spacing: 20) {
                    ForEach(order, id: \.self) { id in
                        Button { model.newPuzzle(shape: id) } label: {
                            VStack(spacing: 10) {
                                ShapeIcon(id: id).frame(width: 72, height: 72)
                                Text(TileShape.of(id).label).font(.subheadline)
                            }
                            .frame(width: 140, height: 140)
                            .foregroundStyle(Color(Theme.text))
                            .panel(RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !model.puzzles.isEmpty {
                    VStack(spacing: 8) {
                        Text("Continue a saved puzzle").font(.footnote).foregroundStyle(Color(Theme.muted))
                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach(model.puzzles, id: \.id) { meta in
                                    PuzzleRow(meta: meta, onOpen: { Task { await model.open(meta) } }, onDelete: { Task { await model.delete(meta) } })
                                }
                            }
                        }
                        .frame(maxHeight: 280)
                    }
                    .frame(maxWidth: 440)
                }
            }
            .padding(20)
        }
        .preferredColorScheme(.dark)
    }
}
