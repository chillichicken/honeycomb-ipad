import SwiftUI

/// An app-styled confirmation: optional visual on top, a message, Cancel and a
/// confirm button. `danger` makes the confirm button red.
struct ConfirmOverlay<Visual: View>: View {
    let message: String
    let confirmLabel: String
    var danger = false
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @ViewBuilder let visual: () -> Visual

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea().onTapGesture(perform: onCancel)
            VStack(spacing: 18) {
                visual()
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(Theme.text))
                HStack(spacing: 12) {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(ModalButtonStyle())
                    Button(confirmLabel, action: onConfirm)
                        .buttonStyle(ModalButtonStyle(danger: danger))
                }
            }
            .padding(24)
            .frame(maxWidth: 400)
            .panel(RoundedRectangle(cornerRadius: 16))
            .padding(24)
        }
        .transition(.opacity)
    }
}

private struct ModalButtonStyle: ButtonStyle {
    var danger = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(danger ? Color(red: 1, green: 0.7, blue: 0.7) : Color(Theme.textBright))
            .padding(.horizontal, 18).padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                (danger ? Color.red.opacity(0.28) : Color(Theme.panel2)).opacity(configuration.isPressed ? 0.6 : 1),
                in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(Theme.border).opacity(0.3)))
    }
}
