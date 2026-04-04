import SwiftUI
import AVFoundation

private enum WithdrawStep: Equatable {
    case scan       // QR scanner (opens immediately)
    case amount     // enter amount + confirm
}

struct WithdrawSheet: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authManager: BiometricAuthManager
    @Environment(\.dismiss) private var dismiss

    let vaultBalance: String

    @State private var step: WithdrawStep = .scan
    @State private var address = ""
    @State private var amountText = ""
    @State private var isLoading = false
    @State private var error: String?
    @State private var success = false
    @State private var showAuth = false
    @State private var showManualEntry = false
    @FocusState private var amountFocused: Bool
    @FocusState private var addressFocused: Bool

    private var vaultBal: Double { Double(vaultBalance) ?? 0 }

    private var parsedAmount: Double? {
        Double(amountText.replacingOccurrences(of: ",", with: "."))
    }

    private var canSubmit: Bool {
        guard let amount = parsedAmount, amount > 0, amount <= vaultBal else { return false }
        return !isLoading && !success
    }

    private var isValidAddress: Bool {
        let addr = address.trimmingCharacters(in: .whitespaces)
        return addr.hasPrefix("0x") && addr.count == 42
    }

    private var truncatedAddress: String {
        let addr = address.trimmingCharacters(in: .whitespaces)
        guard addr.count > 12 else { return addr }
        return "\(addr.prefix(6))...\(addr.suffix(4))"
    }

    var body: some View {
        Group {
            switch step {
            case .scan:
                scanView
            case .amount:
                amountView
            }
        }
        .sheet(isPresented: $showAuth) {
            NavigationStack {
                LockScreenView(
                    mode: .pinOnly(onCancel: { showAuth = false }),
                    onSuccess: {
                        showAuth = false
                        Task { await executeWithdraw() }
                    }
                )
            }
            .environmentObject(authManager)
            .interactiveDismissDisabled()
        }
        .sensoryFeedback(.success, trigger: success)
        .sensoryFeedback(.error, trigger: error)
    }

    // MARK: - Scan View (opens immediately)

    private var isTyping: Bool { addressFocused }

    private var scanView: some View {
        ZStack {
            // Camera (always running underneath)
            QRCameraView(onScan: { code in
                let parsed = parseAddress(code)
                guard !parsed.isEmpty else { return }
                address = parsed
                withAnimation(.easeInOut(duration: 0.3)) { step = .amount }
            })
            .ignoresSafeArea()

            // Blur overlay when typing (tap to dismiss)
            if isTyping {
                Color.black.opacity(0.4)
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .onTapGesture {
                        addressFocused = false
                        if address.isEmpty {
                            withAnimation(.easeInOut(duration: 0.2)) { showManualEntry = false }
                        }
                    }
                    .transition(.opacity)
            }

            // UI overlay
            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial.opacity(0.6))
                            .clipShape(Circle())
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                if !isTyping {
                    Spacer()

                    // Viewfinder
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(.white.opacity(0.5), lineWidth: 2)
                        .frame(width: 260, height: 260)
                        .shadow(color: .white.opacity(0.1), radius: 20)
                }

                Spacer()

                // Bottom: label + input
                VStack(spacing: 12) {
                    if !isTyping {
                        Text("Scan wallet QR code")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                    }

                    if showManualEntry {
                        HStack(spacing: 12) {
                            // Input field with paste icon inside
                            HStack(spacing: 8) {
                                TextField("Wallet address", text: $address)
                                    .font(.subheadline)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .focused($addressFocused)
                                    .submitLabel(.go)
                                    .onSubmit {
                                        if isValidAddress {
                                            addressFocused = false
                                            withAnimation(.easeInOut(duration: 0.3)) { step = .amount }
                                        }
                                    }

                                if address.isEmpty {
                                    // Paste action inside input
                                    Button {
                                        if let clip = UIPasteboard.general.string {
                                            address = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                                            if isValidAddress {
                                                addressFocused = false
                                                withAnimation(.easeInOut(duration: 0.3)) { step = .amount }
                                            }
                                        }
                                    } label: {
                                        Image(systemName: "doc.on.clipboard")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                } else {
                                    Button { address = "" } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .glassEffect()

                            // Submit button (right side — Liquid Glass)
                            Button {
                                addressFocused = false
                                withAnimation(.easeInOut(duration: 0.3)) { step = .amount }
                            } label: {
                                Image(systemName: "arrow.up")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(isValidAddress ? Color.accentColor : .secondary)
                                    .frame(width: 24, height: 24)
                            }
                            .disabled(!isValidAddress)
                            .buttonStyle(.glass)
                            .clipShape(Circle())
                        }
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { showManualEntry = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { addressFocused = true }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "keyboard")
                                    .font(.caption)
                                Text("Enter address manually")
                                    .font(.subheadline.weight(.medium))
                            }
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial.opacity(0.4))
                            .clipShape(Capsule())
                        }
                    }
                }
                .padding(.bottom, isTyping ? 8 : 48)
                .animation(.easeInOut(duration: 0.25), value: isTyping)
                .animation(.easeInOut(duration: 0.2), value: isValidAddress)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isTyping)
    }

    // MARK: - Amount View

    private var amountView: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // Destination badge
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.caption2)
                        Text(truncatedAddress)
                            .font(.caption.weight(.medium).monospaced())
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(Capsule())
                    .padding(.top, 20)

                    // Amount input
                    VStack(spacing: 8) {
                        Text(amountText.isEmpty ? "$0" : "$\(amountText)")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(amountText.isEmpty ? Color(.tertiaryLabel) : .primary)
                            .contentTransition(.numericText())
                            .animation(.default, value: amountText)
                            .frame(maxWidth: .infinity)
                            .onTapGesture { amountFocused = true }

                        TextField("", text: $amountText)
                            .keyboardType(.decimalPad)
                            .focused($amountFocused)
                            .frame(width: 0, height: 0)
                            .opacity(0)
                    }

                    // Vault balance + Max
                    HStack(spacing: 6) {
                        Image(systemName: "building.columns.fill")
                            .font(.caption2)
                        Text("Vault:")
                            .font(.caption)
                        Text(CurrencyFormatter.format(vaultBalance))
                            .font(.caption.weight(.semibold))

                        Button("Max") {
                            amountText = String(format: "%.2f", vaultBal)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    }
                    .foregroundStyle(.secondary)

                    // Gas sponsored
                    HStack(spacing: 6) {
                        Image(systemName: "gift.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                        Text("Gas fee sponsored")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.accentColor.opacity(0.08))
                    .clipShape(Capsule())

                    // Error / Success
                    if let error {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                            Text(error)
                                .font(.caption)
                        }
                        .foregroundStyle(.red)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if success {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Sent successfully!")
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(Color.green.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 20)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                }
                .padding(.bottom, 100)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    if success {
                        dismiss()
                    } else {
                        Task {
                            if await authManager.authenticate() {
                                await executeWithdraw()
                            } else {
                                showAuth = true
                            }
                        }
                    }
                } label: {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    } else {
                        Text(success ? "Done" : "Confirm & Send")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
                .disabled(!canSubmit && !success)
                .buttonStyle(.glassProminent)
                .tint(success ? .green : Color.accentColor)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !isLoading && !success {
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) { step = .scan }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.body.weight(.medium))
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                        .font(.subheadline)
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { amountFocused = true }
        }
    }

    // MARK: - Helpers

    private func parseAddress(_ code: String) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased().hasPrefix("ethereum:") {
            return String(trimmed.dropFirst("ethereum:".count))
                .components(separatedBy: CharacterSet(charactersIn: "@?/"))
                .first ?? trimmed
        }
        return trimmed
    }

    // MARK: - Execute

    private func executeWithdraw() async {
        guard let amount = parsedAmount else { return }
        isLoading = true
        error = nil

        do {
            struct WithdrawRequest: Encodable {
                let amountDollars: Double
                let toAddress: String
            }
            struct WithdrawResponse: Decodable {
                let success: Bool?
                let txHash: String?
                let error: String?
            }

            let response: WithdrawResponse = try await appState.apiClient.request(
                "POST",
                path: "/v1/wallet/withdraw-from-vault",
                body: WithdrawRequest(amountDollars: amount, toAddress: address)
            )

            if response.success == true {
                withAnimation { success = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { dismiss() }
            } else {
                withAnimation { self.error = response.error ?? "Withdrawal failed" }
            }
        } catch {
            withAnimation { self.error = error.localizedDescription }
        }

        isLoading = false
    }
}

// MARK: - QR Camera View

private struct QRCameraView: UIViewRepresentable {
    let onScan: (String) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black

        let session = AVCaptureSession()
        context.coordinator.session = session

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return view }

        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return view }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(context.coordinator, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = UIScreen.main.bounds
        view.layer.addSublayer(preview)
        context.coordinator.previewLayer = preview

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.previewLayer?.frame = uiView.bounds
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onScan: (String) -> Void
        var session: AVCaptureSession?
        var previewLayer: AVCaptureVideoPreviewLayer?

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let value = object.stringValue else { return }
            session?.stopRunning()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onScan(value)
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.session?.stopRunning()
    }
}
