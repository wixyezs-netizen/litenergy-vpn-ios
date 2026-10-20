import AVFoundation
import SwiftUI
import UIKit

/// Экран сканирования QR-кода с подпиской.
struct QRScannerSheet: View {
    let onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var denied = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if denied {
                VStack(spacing: 14) {
                    Image(systemName: "camera.fill").font(.system(size: 36)).foregroundColor(.w1Muted)
                    Text("Нет доступа к камере").font(ui(20, .bold)).foregroundColor(.white)
                    Text("Разрешите доступ в «Настройки → LitEnergy VPN → Камера» или вставьте ссылку вручную.")
                        .font(ui(15)).foregroundColor(.w1Muted).multilineTextAlignment(.center)
                    PillButton(icon: "gearshape", title: "Открыть настройки") {
                        openLink(UIApplication.openSettingsURLString)
                    }
                }
                .padding(28)
            } else {
                QRCameraView(onCode: { code in
                    onCode(code)
                    dismiss()
                }, onDenied: { denied = true })
                    .ignoresSafeArea()
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.9), lineWidth: 3)
                    .frame(width: 250, height: 250)
            }
            VStack {
                HStack {
                    Text("Наведите на QR-код").font(ui(17, .semibold)).foregroundColor(.white)
                    Spacer()
                    RoundIconButton(icon: "xmark", label: "Закрыть") { dismiss() }
                }
                .padding(20)
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct QRCameraView: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onDenied: () -> Void

    func makeUIViewController(context _: Context) -> ScannerController {
        let controller = ScannerController()
        controller.onCode = onCode
        controller.onDenied = onDenied
        return controller
    }

    func updateUIViewController(_: ScannerController, context _: Context) {}
}

final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    var onDenied: (() -> Void)?
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private var done = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { granted ? self.configure() : self.onDenied?() }
            }
        default:
            DispatchQueue.main.async { self.onDenied?() }
        }
    }

    private func configure() {
        guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else {
            onDenied?()
            return
        }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        preview = layer
        DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning { session.stopRunning() }
    }

    func metadataOutput(_: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from _: AVCaptureConnection) {
        guard !done, let code = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        done = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        session.stopRunning()
        onCode?(code)
    }
}
