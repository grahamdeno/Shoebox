import AVFoundation
import SwiftUI
import UIKit

/// The camera, in the lower half of the app. Pull it up for more. Take photo keeps what you see.
struct CameraSheet: View {
    var onPhoto: (Data) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CameraController()

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            CameraPreview(session: camera.session).ignoresSafeArea()

            if camera.denied {
                VStack(spacing: 12) {
                    Text("Shoebox can't use the camera.")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Allow it in Settings, then Shoebox.")
                        .font(.system(size: 15))
                        .opacity(0.8)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .underline()
                    .frame(minHeight: Metrics.touchMin)
                }
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .frame(minWidth: 88, minHeight: 52, alignment: .leading)
                Spacer()
                if !camera.denied {
                    Button("Take photo") {
                        camera.capture { data in
                            onPhoto(data)
                            dismiss()
                        }
                    }
                    .frame(minWidth: 120, minHeight: 52, alignment: .trailing)
                    .disabled(!camera.ready)
                    .opacity(camera.ready ? 1 : 0.5)
                }
            }
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .buttonStyle(.plain)
            .padding(.horizontal, 22)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .environment(\.colorScheme, .dark)
        .presentationDetents([.fraction(0.5), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Metrics.sheetRadius)
        .task { await camera.start() }
        .onDisappear { camera.stop() }
    }
}

/// Runs the camera and takes the picture.
final class CameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    @Published var denied = false
    @Published var ready = false

    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "shoebox.camera")
    private var handler: ((Data) -> Void)?

    @MainActor
    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            if !(await AVCaptureDevice.requestAccess(for: .video)) { denied = true; return }
        default:
            denied = true
            return
        }
        queue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
               let input = try? AVCaptureDeviceInput(device: device), self.session.canAddInput(input) {
                self.session.addInput(input)
            }
            if self.session.canAddOutput(self.output) { self.session.addOutput(self.output) }
            self.session.commitConfiguration()
            self.session.startRunning()
            DispatchQueue.main.async { self.ready = !self.session.inputs.isEmpty }
        }
    }

    func stop() {
        queue.async { [weak self] in
            if self?.session.isRunning == true { self?.session.stopRunning() }
        }
    }

    func capture(_ done: @escaping (Data) -> Void) {
        handler = done
        output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else { return }
        DispatchQueue.main.async { [weak self] in
            self?.handler?(data)
            self?.handler = nil
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.layer.session = session
        v.layer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        // swiftlint:disable:next force_cast
        var layer: AVCaptureVideoPreviewLayer { super.layer as! AVCaptureVideoPreviewLayer }
    }
}
