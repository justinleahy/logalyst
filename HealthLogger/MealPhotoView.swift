import SwiftUI
import SwiftData
import PhotosUI

/// Takes or picks a photo of a meal, estimates its foods on the device, then opens them to check and log.
struct MealPhotoView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var savedFoods: [Food]
    @Query private var recipes: [Recipe]
    @State private var path: [Estimate] = []
    @State private var photo: PhotosPickerItem?
    @State private var takingPhoto = false
    @State private var preview: UIImage?
    @State private var reading = false
    @State private var error: String?

    private struct Estimate: Hashable {
        let foods: [FoodPortion]
        let date: Date?
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 20) {
                Group {
                    if let preview {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFit()
                            .clipShape(.rect(cornerRadius: 16))
                            .overlay {
                                if reading {
                                    ProgressView("Looking at Your Meal…")
                                        .padding()
                                        .background(.regularMaterial, in: .rect(cornerRadius: 12))
                                }
                            }
                    } else {
                        ContentUnavailableView {
                            Label("Photograph Your Meal", systemImage: "camera")
                        } description: {
                            Text("Apple Intelligence estimates each food and how much is there, on your iPhone. "
                                 + "You can check and change everything before it's logged.")
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                HStack {
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label("Choose Photo", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button("Take Photo", systemImage: "camera") { takingPhoto = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .disabled(reading)
            }
            .padding()
            .navigationTitle("Photo of Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .navigationDestination(for: Estimate.self) { estimate in
                LogMealView(title: "Meal from Photo", portions: estimate.foods, date: estimate.date,
                            note: "Estimated from your photo. Check each food and amount before logging.") {
                    dismiss()
                }
            }
            .fullScreenCover(isPresented: $takingPhoto) {
                CameraPicker { image in
                    takingPhoto = false
                    if let image { Task { await read(image, date: nil) } }
                }
                .ignoresSafeArea()
            }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                photo = nil
                Task { await read(item) }
            }
            .alert("Couldn't Read the Photo", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    private func read(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            error = "That photo couldn't be opened."
            return
        }
        // A photo from the library was likely taken at the meal, so log it then.
        await read(image, date: MealPhoto.dateTaken(data))
    }

    private func read(_ image: UIImage, date: Date?) async {
        guard let cgImage = image.cgImage else { return }
        preview = image
        reading = true
        defer { reading = false }
        do {
            let known = savedFoods.map(\.portion) + recipes.map(\.portion)
            let foods = try await MealPhoto.foods(in: cgImage, orientation: .init(image.imageOrientation), known: known)
            path = [Estimate(foods: foods, date: date.map { min($0, .now) })]
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// The system camera, for a single photo. Reports nil if cancelled.
private struct CameraPicker: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void

        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}
