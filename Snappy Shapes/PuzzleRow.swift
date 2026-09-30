import SwiftUI
import Core

/// One saved puzzle: tap anywhere to open it, the trash icon deletes it.
struct PuzzleRow: View {
    let meta: PuzzleMeta
    let onOpen: () -> Void
    let onDelete: () -> Void
    @State private var confirming = false

    var body: some View {
        HStack(spacing: 12) {
            ShapeIcon(id: meta.shape).frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(meta.name).font(.body.weight(.medium)).foregroundStyle(Color(Theme.textBright))
                Text(subtitle).font(.footnote).foregroundStyle(Color(Theme.muted))
            }
            Spacer(minLength: 8)
            Button { confirming = true } label: {
                Image(systemName: "trash").frame(width: 44, height: 44)
            }
            .foregroundStyle(Color(Theme.muted))
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(minHeight: 60)
        .panel(RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture(perform: onOpen)
        .confirmationDialog("Delete \"\(meta.name)\"?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: onDelete)
        } message: {
            Text("This can't be undone.")
        }
    }

    private var subtitle: String {
        let pieces = meta.tileCount > 0 ? "\(meta.tileCount.formatted()) piece\(meta.tileCount == 1 ? "" : "s") · " : ""
        return "\(pieces)saved \(relativeTime(from: meta.updatedAt)) · edited \(formatDuration(ms: meta.activeMs))"
    }
}
