import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

@MainActor
final class SendViewModel: ObservableObject {
    @Published var errorMessage: String?
    @Published var selectedName: String?
    @Published var selectedData: Data?
    @Published var selectedMime: String?

    @Published var fps: Double = 10
    @Published var blockSize: Int = 256

    @Published var isTransmitting = false
    @Published var framesSent: Int = 0
    @Published var currentCode: String = ""

    @Published var photoItem: PhotosPickerItem?

    private var transmitter: SmokeSignalTransmitter?
    private var timer: Timer?

    func loadFile(url: URL) {
        errorMessage = nil
        var didAccess = false
        if url.startAccessingSecurityScopedResource() {
            didAccess = true
        }
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let data = try Data(contentsOf: url)
            selectedData = data
            selectedName = url.lastPathComponent

            if let type = UTType(filenameExtension: url.pathExtension), let mime = type.preferredMIMEType {
                selectedMime = mime
            } else {
                selectedMime = "application/octet-stream"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadPhotoItem() async {
        errorMessage = nil
        guard let photoItem else { return }
        do {
            if let data = try await photoItem.loadTransferable(type: Data.self) {
                selectedData = data
                let bestType = photoItem.supportedContentTypes.first
                let ext = bestType?.preferredFilenameExtension ?? "bin"
                selectedName = "photo.\(ext)"
                selectedMime = bestType?.preferredMIMEType ?? "application/octet-stream"
            } else {
                errorMessage = "Unable to load photo data."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func start() {
        guard let selectedData else {
            errorMessage = "Pick a file or photo first."
            return
        }

        let safeBlock = max(64, min(blockSize, 1024))
        let name = selectedName ?? "smokesignal"
        let meta = SmokeSignalMetadata(
            fileName: name,
            mimeType: selectedMime,
            sha256Hex: smokeSignalSHA256Hex(of: selectedData)
        )
        transmitter = SmokeSignalTransmitter(
            data: selectedData,
            metadata: meta,
            config: SmokeSignalTransmitConfig(blockSize: safeBlock, metadataEveryNSymbols: 25)
        )

        framesSent = 0
        isTransmitting = true
        setIdleTimerDisabled(true)

        timer?.invalidate()
        let interval = max(1.0 / 30.0, 1.0 / max(1.0, fps))
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        transmitter = nil
        isTransmitting = false
        setIdleTimerDisabled(false)
    }

    private func tick() {
        guard let transmitter else { return }
        currentCode = transmitter.nextBase64Frame()
        framesSent += 1
    }

    private func setIdleTimerDisabled(_ disabled: Bool) {
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = disabled
        #endif
    }
}

struct SendView: View {
    @StateObject private var model = SendViewModel()
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button("Pick File") { isImporting = true }
                                .buttonStyle(.bordered)

                            PhotosPicker(selection: $model.photoItem, matching: .images) {
                                Text("Pick Photo")
                            }
                            .buttonStyle(.bordered)
                        }

                        if let name = model.selectedName {
                            Text("Selected: \(name)")
                                .font(.subheadline)
                        }

                        if let err = model.errorMessage {
                            Text(err).foregroundStyle(.red).font(.subheadline)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("FPS: \(Int(model.fps))")
                        Slider(value: $model.fps, in: 1...20, step: 1)

                        Picker("Block Size", selection: $model.blockSize) {
                            Text("128").tag(128)
                            Text("192").tag(192)
                            Text("256").tag(256)
                            Text("384").tag(384)
                            Text("512").tag(512)
                        }
                        .pickerStyle(.segmented)
                    }

                    if model.isTransmitting {
                        VStack(spacing: 12) {
                            QRCodeView(code: model.currentCode)
                                .frame(maxWidth: 420)
                                .padding()

                            Text("Frames sent: \(model.framesSent)")
                                .font(.subheadline)

                            Button("Stop") { model.stop() }
                                .buttonStyle(.borderedProminent)
                        }
                    } else {
                        Button("Start Transmitting") { model.start() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
            }
            .navigationTitle("Send")
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    model.loadFile(url: url)
                }
            case .failure(let error):
                model.errorMessage = error.localizedDescription
            }
        }
        .onChange(of: model.photoItem) { _ in
            Task { await model.loadPhotoItem() }
        }
    }
}
