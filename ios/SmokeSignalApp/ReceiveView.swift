import SwiftUI
import AVFoundation

@MainActor
final class ReceiveViewModel: ObservableObject {
    @Published var errorMessage: String?
    @Published var isScanning = false
    @Published var progress: Double = 0
    @Published var recoveredText: String = "Waiting for stream..."

    @Published var receivedURL: URL?
    @Published var receivedImage: Image?

    private let receiver = SmokeSignalReceiver()
    private var didComplete = false

    func requestCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { cont in
                AVCaptureDevice.requestAccess(for: .video) { ok in cont.resume(returning: ok) }
            }
        default:
            return false
        }
    }

    func start() {
        didComplete = false
        receivedURL = nil
        receivedImage = nil
        errorMessage = nil
        isScanning = true
        setIdleTimerDisabled(true)
    }

    func stop() {
        isScanning = false
        setIdleTimerDisabled(false)
    }

    func reset() {
        receiver.reset()
        progress = 0
        recoveredText = "Waiting for stream..."
        didComplete = false
        receivedURL = nil
        receivedImage = nil
        errorMessage = nil
    }

    func onCode(_ base64: String) {
        guard !didComplete else { return }
        let event = receiver.ingest(base64: base64)

        switch event {
        case .ignored:
            return
        case .updated(let p):
            progress = p
            recoveredText = "\(receiver.recoveredBlocks)/\(receiver.totalBlocks) blocks"
        case .completed(let file):
            didComplete = true
            progress = 1.0
            recoveredText = "Done"
            stop()
            persistAndPreview(file: file)
        }
    }

    private func persistAndPreview(file: SmokeSignalReceivedFile) {
        let safeName = sanitizeFileName(file.metadata.fileName) ?? "smokesignal-\(file.sessionId)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safeName)
        do {
            try file.data.write(to: url, options: [.atomic])
            receivedURL = url

            #if canImport(UIKit)
            if let ui = UIImage(data: file.data) {
                receivedImage = Image(uiImage: ui)
            }
            #endif
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sanitizeFileName(_ name: String?) -> String? {
        guard var name else { return nil }
        name = name.replacingOccurrences(of: "/", with: "_")
        name = name.replacingOccurrences(of: ":", with: "_")
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private func setIdleTimerDisabled(_ disabled: Bool) {
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = disabled
        #endif
    }
}

struct ReceiveView: View {
    @StateObject private var model = ReceiveViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if model.isScanning {
                    CameraScannerView(isRunning: $model.isScanning, onCode: model.onCode)
                        .frame(height: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.2), lineWidth: 1)
                        }
                        .padding()
                } else {
                    Text("Camera stopped")
                        .foregroundStyle(.secondary)
                        .padding(.top, 24)
                }

                ProgressView(value: model.progress)
                    .padding(.horizontal)

                Text(model.recoveredText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let err = model.errorMessage {
                    Text(err).foregroundStyle(.red).font(.subheadline)
                }

                if let image = model.receivedImage {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                }

                if let url = model.receivedURL {
                    ShareLink(item: url) {
                        Text("Share Received File")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
                }

                HStack {
                    Button(model.isScanning ? "Stop" : "Start") {
                        if model.isScanning {
                            model.stop()
                        } else {
                            model.start()
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Reset") { model.reset() }
                        .buttonStyle(.bordered)
                }
                .padding(.bottom, 12)
            }
            .navigationTitle("Receive")
        }
        .task {
            let ok = await model.requestCameraAccess()
            if ok {
                model.start()
            } else {
                model.errorMessage = "Camera access denied. Enable it in Settings."
            }
        }
    }
}
