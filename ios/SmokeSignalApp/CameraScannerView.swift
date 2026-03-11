import SwiftUI
import AVFoundation

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let onCode: (String) -> Void

    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var lastString: String?
    private var lastTime: CFAbsoluteTime = 0

    init(onCode: @escaping (String) -> Void) {
        self.onCode = onCode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        guard AVCaptureDevice.authorizationStatus(for: .video) != .denied else {
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .high

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(output)

        output.setMetadataObjectsDelegate(self, queue: DispatchQueue(label: "smokesignal.qr.scanner"))
        output.metadataObjectTypes = [.qr]

        session.commitConfiguration()

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        previewLayer = layer
        view.layer.addSublayer(layer)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    func start() {
        guard !session.isRunning else { return }
        session.startRunning()
    }

    func stop() {
        guard session.isRunning else { return }
        session.stopRunning()
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject else { return }
        guard obj.type == .qr, let str = obj.stringValue, !str.isEmpty else { return }

        // Throttle duplicates (AVFoundation tends to repeat the same QR many times).
        let now = CFAbsoluteTimeGetCurrent()
        if str == lastString && (now - lastTime) < 0.15 {
            return
        }
        lastString = str
        lastTime = now

        DispatchQueue.main.async { [onCode] in
            onCode(str)
        }
    }
}

struct CameraScannerView: UIViewControllerRepresentable {
    @Binding var isRunning: Bool
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        ScannerViewController(onCode: onCode)
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {
        if isRunning {
            uiViewController.start()
        } else {
            uiViewController.stop()
        }
    }
}

