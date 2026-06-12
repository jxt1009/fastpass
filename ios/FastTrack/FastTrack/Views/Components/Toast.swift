import SwiftUI
import Combine

// MARK: - ToastMessage

struct ToastMessage: Identifiable {
    let id = UUID()
    let text: String
    let actionLabel: String?
    var action: (() -> Void)?

    init(text: String, actionLabel: String? = nil, action: (() -> Void)? = nil) {
        self.text = text
        self.actionLabel = actionLabel
        self.action = action
    }
}

// MARK: - ToastManager

final class ToastManager: ObservableObject {
    static let shared = ToastManager()

    @Published private(set) var current: ToastMessage?

    private var dismissTask: Task<Void, Never>?

    private init() {}

    /// Enqueue a toast. If one is already visible, replace it (cancel the
    /// pending auto-dismiss and start a new timer). The optional action
    /// runs on dismissal if the user taps the action button; the toast
    /// itself dismisses as soon as the user taps.
    @MainActor
    func show(_ message: ToastMessage, autoDismissAfter seconds: Double = 3) {
        let hasAction = message.action != nil
        let delay = hasAction ? max(seconds, 4) : seconds
        dismissTask?.cancel()
        current = message
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.dismiss()
        }
    }

    @MainActor
    func dismiss() {
        dismissTask?.cancel()
        current = nil
    }
}

// MARK: - ToastView

struct ToastView: View {
    let message: ToastMessage
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(message.text)
                .font(.subheadline)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let label = message.actionLabel {
                Button(label, action: onAction)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.ftBlue)
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.ftCardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.ftSectionBg, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

// MARK: - Overlay modifier

private struct ToastOverlayModifier: ViewModifier {
    @ObservedObject var manager: ToastManager

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message = manager.current {
                ToastView(message: message) {
                    message.action?()
                    manager.dismiss()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(message.id)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: manager.current?.id)
    }
}

extension View {
    /// Overlay a toast on this view, driven by the given ToastManager.
    /// Apply to the root view of the app so the toast sits above all
    /// tabs and sheets.
    func toastOverlay(_ manager: ToastManager = .shared) -> some View {
        modifier(ToastOverlayModifier(manager: manager))
    }
}
