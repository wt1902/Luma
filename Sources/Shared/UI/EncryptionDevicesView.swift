import SwiftUI

struct EncryptionDevicesView: View {
    @ObservedObject var model: AppModel
    let conversation: Conversation
    @Environment(\.dismiss) private var dismiss
    @State private var devices: [OMEMODevice] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(
                        statusTitle,
                        systemImage: statusIcon
                    )
                    .foregroundStyle(statusColor)
                } footer: {
                    Text(
                        "Luma использует trust-on-first-use. Сверьте отпечаток по другому каналу и отметьте устройство как проверенное."
                    )
                }

                Section("Устройства контакта") {
                    if devices.isEmpty {
                        ContentUnavailableView(
                            "Ключи ещё не получены",
                            systemImage: "key.horizontal",
                            description: Text(
                                "Они появятся после первой попытки отправки или получения OMEMO-сообщения."
                            )
                        )
                    } else {
                        ForEach(devices) { device in
                            DeviceRow(device: device) {
                                model.setDeviceVerified(
                                    device.trust != .verified,
                                    jid: device.jid,
                                    deviceID: device.deviceID
                                )
                                reload()
                            }
                        }
                    }
                }

                if let fingerprint = model.ownFingerprint {
                    Section("Это устройство") {
                        Text(fingerprint.chunked(every: 8).joined(separator: " "))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Шифрование")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .onAppear(perform: reload)
        }
        #if os(macOS)
            .frame(minWidth: 480, minHeight: 500)
        #endif
    }

    private func reload() {
        devices = model.devices(for: conversation.jid).filter { !$0.isOwn }
    }

    private var statusTitle: String {
        guard model.encryptionEnabled(for: conversation.jid) else {
            return "OMEMO выключено для этого чата"
        }
        return model.isOMEMOReady ? "OMEMO активно" : "OMEMO подготавливается"
    }

    private var statusIcon: String {
        guard model.encryptionEnabled(for: conversation.jid) else { return "lock.open" }
        return model.isOMEMOReady ? "lock.shield.fill" : "lock.rotation"
    }

    private var statusColor: Color {
        model.encryptionEnabled(for: conversation.jid) && model.isOMEMOReady ? .green : .orange
    }
}

private struct DeviceRow: View {
    let device: OMEMODevice
    let toggleVerification: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(
                    "Устройство \(device.deviceID)",
                    systemImage: device.isActive ? "iphone" : "iphone.slash"
                )
                .font(.headline)
                Text(device.protocolName)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .foregroundStyle(device.isOMEMO2 ? Color.indigo : Color.secondary)
                    .background(
                        (device.isOMEMO2 ? Color.indigo : Color.secondary).opacity(0.14),
                        in: Capsule()
                    )
                Spacer()
                Button(action: toggleVerification) {
                    Label(trustTitle, systemImage: trustIcon)
                }
                .buttonStyle(.bordered)
                .tint(trustColor)
            }
            Text(device.formattedFingerprint)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 5)
    }

    private var trustTitle: String {
        switch device.trust {
        case .verified: return "Проверено"
        case .trusted: return "Доверено"
        case .undecided: return "Проверить"
        case .compromised: return "Скомпрометировано"
        }
    }

    private var trustIcon: String {
        switch device.trust {
        case .verified: return "checkmark.seal.fill"
        case .trusted: return "checkmark.shield"
        case .undecided: return "questionmark.diamond"
        case .compromised: return "exclamationmark.triangle.fill"
        }
    }

    private var trustColor: Color {
        switch device.trust {
        case .verified: return .green
        case .trusted: return .blue
        case .undecided: return .orange
        case .compromised: return .red
        }
    }
}

extension String {
    fileprivate func chunked(every size: Int) -> [String] {
        guard size > 0 else { return [self] }
        var result: [String] = []
        var cursor = startIndex
        while cursor < endIndex {
            let end = index(cursor, offsetBy: size, limitedBy: endIndex) ?? endIndex
            result.append(String(self[cursor..<end]))
            cursor = end
        }
        return result
    }
}

#Preview {
    EncryptionDevicesView(
        model: PreviewSupport.model,
        conversation: PreviewSupport.conversation(displayName: "Алиса")
    )
}
