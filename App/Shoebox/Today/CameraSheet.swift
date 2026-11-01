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

            if !camera.problem.isEmpty {
                Text(camera.problem)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .frame(maxHeight: .infinity, alignment: .center)
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
    @Published var problem = ""

    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "shoebox.camera")
    private var handler: ((Data) -> Void)?
    /// Set once the sheet has gone, so a late permission answer or photo does nothing.
    private var stopped = false

    @MainActor
    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            if !(await AVCaptureDevice.requestAccess(for: .video)) { denied = true; return }
            guard !stopped else { return }
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

    @MainActor
    func stop() {
        stopped = true
        handler = nil
        queue.async { [weak self] in
            if self?.session.isRunning == true { self?.session.stopRunning() }
        }
    }

    @MainActor
    func capture(_ done: @escaping (Data) -> Void) {
        guard !stopped, handler == nil else { return }
        handler = done
        problem = ""
        queue.async { [weak self] in
            guard let self else { return }
            // The app is portrait: keep the photo upright.
            if let c = self.output.connection(with: .video), c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
            self.output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let done = self.handler
            self.handler = nil
            if let data { done?(data) } else if done != nil { self.problem = "That photo didn't take. Try again." }
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
