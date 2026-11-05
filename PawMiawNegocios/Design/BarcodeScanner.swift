//
//  BarcodeScanner.swift
//  PawMiawNegocios
//
//  The camera scanner (web components/app/barcode-scanner.tsx), the one way
//  the app reads a barcode: the scan mark beside a search box or a code field
//  opens it, it reads the code by itself and hands it over — the same code a
//  hardware scanner would have typed. VisionKit's live scanner where the
//  device has it, otherwise the camera through AVFoundation; a photo of the
//  code (Vision) or the code typed by hand when the camera can't. A read is
//  only taken when it can be trusted (`BarcodeStableReader`), and a GS1 label
//  also gives its lot and expiry (the rules are in Core/Barcode.swift).
//  Used by the Store's counter, the Catalog's product sheet and quick edit,
//  the bill's item search, Inventory's search, stock settings and the
//  delivery's product picker.
//

import SwiftUI
import AVFoundation
import VisionKit
import Vision
import PhotosUI
import UIKit

/// The symbologies asked of the camera, by the web's format names.
nonisolated enum BarcodeSymbology {
    static let vision: [VNBarcodeSymbology] = [.ean13, .ean8, .upce, .code128, .code39, .code39Checksum, .code39FullASCII, .itf14, .i2of5, .qr, .microQR, .dataMatrix]
    static let capture: [AVMetadataObject.ObjectType] = [.ean13, .ean8, .upce, .code128, .code39, .code39Mod43, .itf14, .interleaved2of5, .qr, .microQR, .dataMatrix]

    static func format(_ symbology: VNBarcodeSymbology) -> String? {
        switch symbology {
        case .ean13: "ean_13"
        case .ean8: "ean_8"
        case .upce: "upc_e"
        case .code128: "code_128"
        case .code39, .code39Checksum, .code39FullASCII, .code39FullASCIIChecksum: "code_39"
        case .itf14, .i2of5, .i2of5Checksum: "itf"
        case .qr, .microQR: "qr_code"
        case .dataMatrix: "data_matrix"
        default: nil
        }
    }

    static func format(_ type: AVMetadataObject.ObjectType) -> String? {
        switch type {
        case .ean13: "ean_13"
        case .ean8: "ean_8"
        case .upce: "upc_e"
        case .code128: "code_128"
        case .code39, .code39Mod43: "code_39"
        case .itf14, .interleaved2of5: "itf"
        case .qr, .microQR: "qr_code"
        case .dataMatrix: "data_matrix"
        default: nil
        }
    }

    /// The first code in a photo, or nil when none is found.
    static func read(photo data: Data) -> (raw: String, format: String?)? {
        guard let image = UIImage(data: data), let cgImage = image.cgImage else { return nil }
        let request = VNDetectBarcodesRequest()
        request.symbologies = vision
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation), options: [:])
        try? handler.perform([request])
        guard let found = request.results?.first(where: { ($0.payloadStringValue ?? "").trimmingCharacters(in: .whitespaces).isEmpty == false }),
              let payload = found.payloadStringValue else { return nil }
        return (payload, format(found.symbology))
    }
}

private extension CGImagePropertyOrientation {
    nonisolated init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

/// The scan mark of a search box or a code field, as a round button: it opens the camera
/// and hands over what it read (a GS1 label's GTIN, otherwise the code, with the rest of the label).
struct BarcodeScanButton: View {
    var label: String = L("Scan with the camera")
    var keepScanning: Bool = false
    let onScan: (BarcodeScan) -> Void
    @State private var open = false

    var body: some View {
        IconCircleButton(systemImage: "barcode.viewfinder", label: label) { open = true }
            .sheet(isPresented: $open) {
                BarcodeScannerSheet(keepScanning: keepScanning, onScan: onScan)
            }
    }
}

/// A code field with the scan mark beside it (a product's barcode or SKU): typed, or read by the
/// camera — a hardware scanner types into it like a keyboard.
struct BarcodeField: View {
    let label: String
    @Binding var text: String
    var key: String? = nil
    var form: FormState? = nil
    var prompt: String? = nil
    var hint: String? = nil
    var optional: Bool = true
    var capitalization: TextInputAutocapitalization = .never
    /// The longest code the field keeps (the server's limit).
    var maxLength: Int = 120
    /// What the camera read, once it is in the field (a twin check, "also use it as the barcode").
    var onScan: (BarcodeScan) -> Void = { _ in }

    var body: some View {
        FormField(label: label, key: key, hint: hint, form: form, optional: optional) {
            HStack(spacing: 8) {
                TextField(prompt ?? "", text: $text)
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(capitalization)
                    .autocorrectionDisabled()
                    .fieldChrome(invalid: key.flatMap { form?.error($0) } != nil)
                    .onChange(of: text) { _, _ in if let key { form?.clear(key) } }
                BarcodeScanButton { scan in
                    text = String(scan.code.prefix(maxLength))
                    if let key { form?.clear(key) }
                    onScan(scan)
                }
            }
        }
    }
}

/// A search box with the scan mark beside it: typing searches, Return looks the code up,
/// the camera reads it.
struct BarcodeSearchField: View {
    let prompt: String
    @Binding var text: String
    var onSubmit: () -> Void = {}
    let onScan: (BarcodeScan) -> Void

    var body: some View {
        HStack(spacing: 8) {
            SearchField(prompt: prompt, text: $text)
                .submitLabel(.search)
                .onSubmit(onSubmit)
            BarcodeScanButton(onScan: onScan)
        }
    }
}

/// The camera scanner, in the provider modal's frame. It layers over another sheet (the
/// delivery, the counter) as their own questions do; the camera is on only while it is open.
struct BarcodeScannerSheet: View {
    var title: String = L("Scan a code")
    /// Several codes in a row (a delivery being counted): the sheet stays open until Done.
    var keepScanning: Bool = false
    let onScan: (BarcodeScan) -> Void

    private enum Phase { case starting, scanning, stopped }
    private enum Problem { case denied, noCamera, failed }
    private enum PhotoState { case idle, reading, none, failed }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var phase: Phase = .starting
    @State private var problem: Problem?
    @State private var liveScanner = true
    @State private var slow = false
    @State private var lastRead: BarcodeScan?
    @State private var lastTaken: (code: String, at: Date)?
    @State private var reader = BarcodeStableReader()
    @State private var manual = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: PhotoState = .idle
    @State private var torchAvailable = false
    @State private var torchOn = false
    @State private var cameraRun = 0
    @State private var done = false
    @FocusState private var typing: Bool

    /// With nothing read after this long, say so and offer typing (the camera keeps looking).
    private let slowAfter: Duration = .seconds(12)
    /// While several codes are taken in a row, the code still in front of the lens is not taken twice.
    private let sameCodeGap: TimeInterval = 2.5

    var body: some View {
        ProviderModal(
            title: title,
            subtitle: L("Point the camera at the barcode. It is read by itself."),
            systemImage: "barcode.viewfinder",
            accent: .aqua,
            cancelTitle: keepScanning && lastRead != nil ? L("Done") : L("Cancel")
        ) {
            cameraBox
            status
            if let lastRead { readCard(lastRead) }
            photoStatus
            FormField(label: L("Or type the code")) {
                HStack(spacing: 8) {
                    TextField(L("The numbers under the bars"), text: $manual)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .submitLabel(.done)
                        .focused($typing)
                        .onSubmit(acceptManual)
                        .fieldChrome()
                    PMButton(L("Use this code"), variant: .outline, size: .compact, action: acceptManual)
                        .disabled(manual.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(L("Use a photo"), systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.pm(.outline, size: .compact))
            .disabled(photo == .reading)
        }
        .task { await start() }
        .task(id: "\(phase == .scanning)-\(lastRead?.code ?? "")") {
            slow = false
            guard phase == .scanning else { return }
            try? await Task.sleep(for: slowAfter)
            if !Task.isCancelled && phase == .scanning { slow = true }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task { await readPhoto(item) }
        }
        .onChange(of: scenePhase) { _, next in
            // The camera is let go while the app is in the background, and comes back with it.
            if next == .background { setTorch(false) }
        }
        .onDisappear { setTorch(false) }
    }

    // MARK: The camera

    @ViewBuilder
    private var cameraBox: some View {
        if let problem {
            let copy = problemCopy(problem)
            NoticeCard(tone: .problem, title: copy.title, message: copy.body, actionTitle: L("Try again"), action: { Task { await start() } })
            if problem == .denied {
                PMButton(L("Open Settings"), systemImage: "gearshape", variant: .outline, size: .compact) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
        } else {
            ZStack {
                Color.black
                if phase == .scanning {
                    Group {
                        if liveScanner {
                            BarcodeLiveScanner(onRead: frameRead)
                        } else {
                            BarcodeCaptureScanner(onRead: frameRead, onFail: { fail(.failed) })
                        }
                    }
                    .id(cameraRun)
                    BarcodeScanTarget()
                        .allowsHitTesting(false)
                }
                if phase == .starting {
                    HStack(spacing: 8) {
                        ProgressView().tint(.white)
                        Text(L("Opening the camera…")).font(Theme.text(14, weight: .semibold)).foregroundStyle(.white)
                    }
                }
                if phase == .scanning && torchAvailable {
                    VStack {
                        HStack {
                            Spacer()
                            Button { setTorch(!torchOn) } label: {
                                Image(systemName: torchOn ? "flashlight.off.fill" : "flashlight.on.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 40, height: 40)
                                    .background(.black.opacity(0.45), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(torchOn ? L("Turn the light off") : L("Turn the light on"))
                        }
                        Spacer()
                    }
                    .padding(10)
                }
            }
            .frame(height: 280)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .accessibilityLabel(L("Camera"))
        }
    }

    @ViewBuilder
    private var status: some View {
        if problem != nil {
            EmptyView()
        } else if slow {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Nothing read yet. Hold the code steady and closer, with good light — or type it."))
                    .font(Theme.smallFont).foregroundStyle(Theme.inkSoft)
                Button(L("Type it instead@scan")) { typing = true }
                    .font(Theme.text(15, weight: .bold)).foregroundStyle(Theme.blueText)
                    .frame(minHeight: 40)
            }
        } else if phase == .scanning && lastRead == nil {
            Text(L("Hold the code inside the frame.")).font(Theme.smallFont).foregroundStyle(Theme.inkSoft)
        }
    }

    private func readCard(_ read: BarcodeScan) -> some View {
        let label = [read.lot.map { LF("Lot %@", $0) }, read.expiresOn].compactMap { $0 }
            + (keepScanning ? [L("Scan the next one, or close when you are done.")] : [])
        return NoticeCard(tone: .success, title: LF("Read: %@@scan", read.code), message: label.isEmpty ? nil : label.joined(separator: "\n"))
    }

    @ViewBuilder
    private var photoStatus: some View {
        switch photo {
        case .reading:
            HStack(spacing: 8) { ProgressView(); Text(L("Reading the photo…")).font(Theme.smallFont).foregroundStyle(Theme.inkSoft) }
        case .none:
            Text(L("No code was found in that photo. Try one that is closer and sharper, or type the code.")).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
        case .failed:
            Text(L("That photo could not be read. Try another one, or type the code.")).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
        case .idle:
            EmptyView()
        }
    }

    private func problemCopy(_ problem: Problem) -> (title: String, body: String) {
        switch problem {
        case .denied: (L("The camera is blocked for PawMiaw Business"), L("Allow the camera for PawMiaw Business in Settings, then try again. Or type the code, or use a photo of it."))
        case .noCamera: (L("No camera was found"), L("This device has no camera we can use. Type the code, or use a photo of it."))
        case .failed: (L("The camera could not be opened"), L("Try again, or type the code."))
        }
    }

    private func fail(_ kind: Problem) {
        setTorch(false)
        phase = .stopped
        problem = kind
    }

    private func start() async {
        problem = nil
        phase = .starting
        reader.reset()
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { fail(.denied); return }
        default:
            fail(.denied)
            return
        }
        guard let device = AVCaptureDevice.default(for: .video) else { fail(.noCamera); return }
        torchAvailable = device.hasTorch && device.isTorchAvailable
        torchOn = false
        // VisionKit's scanner where this device has it; the camera's own reader otherwise.
        liveScanner = DataScannerViewController.isSupported && DataScannerViewController.isAvailable
        cameraRun += 1
        phase = .scanning
    }

    private func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            if on { try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel) } else { device.torchMode = .off }
            device.unlockForConfiguration()
            torchOn = on
        } catch {
            if on { torchAvailable = false }
            torchOn = false
        }
    }

    // MARK: Taking a code

    /// A frame's read: taken once it can be trusted.
    private func frameRead(_ raw: String, _ format: String?) {
        guard !done || keepScanning else { return }
        guard reader.push(raw, format: format) else { return }
        take(Barcode.interpret(raw, format: format, source: .camera))
    }

    private func take(_ result: BarcodeScan) {
        guard !result.code.isEmpty else { return }
        let now = Date()
        if keepScanning, result.source == .camera, let last = lastTaken, last.code == result.code, now.timeIntervalSince(last.at) < sameCodeGap {
            lastTaken = (result.code, now)
            return
        }
        lastTaken = (result.code, now)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        lastRead = result
        slow = false
        reader.reset()
        onScan(result)
        if !keepScanning {
            done = true
            setTorch(false)
            dismiss()
        }
    }

    private func acceptManual() {
        let typed = manual.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return }
        manual = ""
        take(Barcode.interpret(typed, format: nil, source: .typed))
    }

    private func readPhoto(_ item: PhotosPickerItem) async {
        photo = .reading
        guard let data = try? await item.loadTransferable(type: Data.self) else { photo = .failed; return }
        let found = await Task.detached(priority: .userInitiated) { BarcodeSymbology.read(photo: data) }.value
        guard let found else { photo = .none; return }
        photo = .idle
        take(Barcode.interpret(found.raw, format: found.format, source: .photo))
    }
}

/// The frame drawn over the camera: four corners and the line that sweeps while it looks.
private struct BarcodeScanTarget: View {
    @State private var sweep = false

    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width * 0.78, 340)
            let height = min(geo.size.height * 0.55, 160)
            ZStack {
                BarcodeCorners()
                    .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .frame(width: width, height: height)
                Rectangle()
                    .fill(Theme.coral.opacity(0.85))
                    .frame(width: width - 24, height: 2)
                    .offset(y: sweep ? height / 2 - 10 : -height / 2 + 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { sweep = true }
        }
    }
}

private struct BarcodeCorners: Shape {
    func path(in rect: CGRect) -> Path {
        let arm = min(rect.width, rect.height) * 0.22
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + arm)); path.addLine(to: CGPoint(x: rect.minX, y: rect.minY)); path.addLine(to: CGPoint(x: rect.minX + arm, y: rect.minY))
        path.move(to: CGPoint(x: rect.maxX - arm, y: rect.minY)); path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY)); path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + arm))
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - arm)); path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); path.addLine(to: CGPoint(x: rect.maxX - arm, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX + arm, y: rect.maxY)); path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY)); path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - arm))
        return path
    }
}

// MARK: - VisionKit's live scanner

private struct BarcodeLiveScanner: UIViewControllerRepresentable {
    let onRead: (String, String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onRead: onRead) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: BarcodeSymbology.vision)],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: false,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        context.coordinator.onRead = onRead
        if !controller.isScanning { try? controller.startScanning() }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onRead: (String, String?) -> Void

        init(onRead: @escaping (String, String?) -> Void) { self.onRead = onRead }

        private func hand(_ items: [RecognizedItem]) {
            for item in items {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue, !payload.trimmingCharacters(in: .whitespaces).isEmpty {
                    onRead(payload, BarcodeSymbology.format(barcode.observation.symbology))
                }
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) { hand(addedItems) }
        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) { hand(updatedItems) }
    }
}

// MARK: - The camera through AVFoundation (devices without the live scanner)

/// The session, handed to the queue that starts and stops it.
nonisolated private final class BarcodeSessionBox: @unchecked Sendable {
    let session = AVCaptureSession()
}

private final class BarcodePreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

private struct BarcodeCaptureScanner: UIViewRepresentable {
    let onRead: (String, String?) -> Void
    let onFail: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onRead: onRead) }

    func makeUIView(context: Context) -> BarcodePreviewView {
        let view = BarcodePreviewView()
        view.preview.videoGravity = .resizeAspectFill
        let box = context.coordinator.box
        let session = box.session
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            DispatchQueue.main.async { onFail() }
            return view
        }
        session.beginConfiguration()
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            DispatchQueue.main.async { onFail() }
            return view
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(context.coordinator, queue: .main)
        output.metadataObjectTypes = BarcodeSymbology.capture.filter { output.availableMetadataObjectTypes.contains($0) }
        session.commitConfiguration()
        view.preview.session = session
        DispatchQueue.global(qos: .userInitiated).async { box.session.startRunning() }
        return view
    }

    func updateUIView(_ view: BarcodePreviewView, context: Context) {
        context.coordinator.onRead = onRead
    }

    static func dismantleUIView(_ view: BarcodePreviewView, coordinator: Coordinator) {
        let box = coordinator.box
        DispatchQueue.global(qos: .userInitiated).async { box.session.stopRunning() }
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var onRead: (String, String?) -> Void
        let box = BarcodeSessionBox()

        init(onRead: @escaping (String, String?) -> Void) { self.onRead = onRead }

        nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            let reads: [(String, String?)] = metadataObjects.compactMap { object in
                guard let code = object as? AVMetadataMachineReadableCodeObject, let value = code.stringValue,
                      !value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
                return (value, BarcodeSymbology.format(code.type))
            }
            guard !reads.isEmpty else { return }
            // The delegate's queue is the main one.
            MainActor.assumeIsolated {
                for read in reads { onRead(read.0, read.1) }
            }
        }
    }
}
