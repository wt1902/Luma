import SwiftUI

struct ConnectionBanner: View {
    @ObservedObject var model: AppModel
    var text: String

    var body: some View {
        switch model.connectionStatus {
        case .connected:
            if model.isArchiveSyncing || !model.isOMEMOReady {
                banner(
                    text: "Обновление",
                    color: .clear,
                    progress: true
                )
            } else {
                Text(text)
                    .font(.headline)
            }
        case .connecting:
            banner(text: "Подключение", color: .clear, progress: true)
        case .disconnected:
            banner(text: "Ожидание сети", color: .clear, progress: true)
        }
    }

    private func banner(text: String, color: Color, progress: Bool) -> some View {
        HStack(spacing: 8) {
            if progress {
                ProgressView().controlSize(.mini).tint(.white)
            }
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(.white)
    }
}

#Preview {
    ConnectionBanner(model: PreviewSupport.model, text: "Чаты")
        .padding()
}

