import SwiftUI
import PhotosUI
import VisionKit
import AVFoundation

/// Photographs a nutrition facts label (or reads one from Photos), then creates a food from it and logs it.
struct ScanLabelView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var path: [Step] = []

    private enum Step: Hashable {
        case create(FoodDraft)
        case log(Food)
    }

    var body: some View {
        NavigationStack(path: $path) {
            LabelCaptureView { label in
                var draft = FoodDraft()
                draft.apply(label)
                path = [.create(draft)]
            }
            .navigationTitle("Scan Nutrition Label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .navigationDestination(for: Step.self) { step in
                switch step {
                case .create(let draft): FoodEditor(draft: draft) { food in path = [.log(food)] }
                case .log(let food): LogFoodView(food: food) { dismiss() }
                }
            }
        }
    }
}

extension FoodDraft {
    /// Fills in what a label gives: its serving size, if printed, and the nutrients it lists.
    mutating func apply(_ label: NutritionLabel) {
        if !label.servingSize.isEmpty { servingSize = label.servingSize }
        nutrients.merge(label.nutrients) { $1 }
        source = .label
    }
}

/// A camera for photographing a label, with a button to choose a photo instead. Reading happens on the device.
struct LabelCaptureView: View {
    let onRead: (NutritionLabel) -> Void

    @State private var camera = LabelCamera.Controller()
    @State private var cameraReady = false
    @State private var photo: PhotosPickerItem?
    @State private var reading = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if cameraReady {
                    LabelCamera(controller: camera)
                        .overlay(alignment: .top) {
                            Text("Fit the whole Nutrition Facts panel in view, flat and well lit.")
                                .font(.callout)
                                .multilineTextAlignment(.center)
                                .padding(10)
                                .background(.regularMaterial, in: .rect(cornerRadius: 10))
                                .padding()
                        }
                } else {
                    ContentUnavailableView("Camera Unavailable", systemImage: "text.viewfinder",
                                           description: Text("Choose a photo of the nutrition label instead."))
                }
                if reading {
                    ProgressView("Reading Label…")
                        .padding()
                        .background(.regularMaterial, in: .rect(cornerRadius: 12))
                }
            }
            .frame(maxHeight: .infinity)
            HStack {
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("Choose Photo", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)
                Spacer()
                if cameraReady {
                    Button {
                        Task { await takePhoto() }
                    } label: {
                        Label("Take Photo", systemImage: "camera.circle.fill")
                            .labelStyle(.iconOnly)
                            .font(.system(size: 56))
                    }
                    .disabled(reading)
                }
            }
            .disabled(reading)
            .padding()
        }
        .alert("Couldn't Read the Label", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
        .task {
            if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .video)
            }
            cameraReady = LabelCamera.isAvailable
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            photo = nil
            Task { await read(item) }
        }
    }

    private func takePhoto() async {
        do {
            await read(try await camera.capture())
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func read(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            error = "That photo couldn't be opened."
            return
        }
        await read(image)
    }

    private func read(_ image: UIImage) async {
        guard let cgImage = image.cgImage else { return }
        reading = true
        defer { reading = false }
        do {
            if let label = try await NutritionLabel.read(cgImage, orientation: .init(image.imageOrientation)) {
                onRead(label)
            } else {
                error = "No nutrition facts were found. Try again with the whole label in view, flat and well lit."
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Live camera that highlights the text it sees, so it's clear the label is in focus, and takes photos.
private struct LabelCamera: UIViewControllerRepresentable {
    /// Lets the capture button reach the scanner.
    @MainActor final class Controller {
        fileprivate weak var scanner: DataScannerViewController?

        func capture() async throws -> UIImage {
            guard let scanner else { throw CocoaError(.featureUnsupported) }
            return try await scanner.capturePhoto()
        }
    }

    let controller: Controller

    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.text()], qualityLevel: .accurate,
                                                isHighlightingEnabled: true)
        controller.scanner = scanner
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: ()) {
        scanner.stopScanning()
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        self = switch orientation {
        case .up: .up
        case .upMirrored: .upMirrored
        case .down: .down
        case .downMirrored: .downMirrored
        case .left: .left
        case .leftMirrored: .leftMirrored
        case .right: .right
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
