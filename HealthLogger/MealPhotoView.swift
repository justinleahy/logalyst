import SwiftUI
import SwiftData
import PhotosUI

/// Takes or picks a photo of a meal, then estimates its foods on the device and opens them to check and log. With
/// a restaurant or brand, its published nutrition is found on its website for the foods it finds.
struct MealPhotoView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var savedFoods: [Food]
    @Query private var recipes: [Recipe]
    @State private var path: [Analysis] = []
    @State private var photo: PhotosPickerItem?
    @State private var takingPhoto = false
    @State private var image: UIImage?
    /// When a photo from the library was taken, to log the meal then.
    @State private var dateTaken: Date?
    @State private var brand = ""
    @State private var details = ""
    @State private var stage: Stage?
    @State private var analysis: Task<Void, Never>?
    /// The foods found in the last branded photo, so a failed lookup can be tried again without reading the photo
    /// again.
    @State private var lastItems: [MealPhoto.BrandedItem] = []
    @State private var error: String?
    @FocusState private var focused: Field?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private enum Field { case brand, details }

    private enum Analysis: Hashable {
        case estimate([FoodPortion], date: Date?)
        case branded(BrandedMeal, date: Date?)
    }

    private enum Stage: Equatable {
        case reading
        case lookingUp(String)

        var title: String {
            switch self {
            case .reading: "Looking at Your Meal…"
            case .lookingUp(let brand): "Looking Up \(brand)'s Nutrition…"
            }
        }
    }

    private var cleanBrand: String {
        LookupRequest.clean(brand, maxLength: LookupRequest.maxBrandLength)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let image {
                    form(image)
                } else {
                    VStack(spacing: 20) {
                        ContentUnavailableView {
                            Label("Photograph Your Meal", systemImage: "camera")
                        } description: {
                            Text("Apple Intelligence estimates each food and how much is there, on your iPhone. "
                                 + "For a restaurant or brand, Logalyst can use the nutrition it publishes instead. "
                                 + "You can check and change everything before it's logged.")
                        }
                        .frame(maxHeight: .infinity)
                        photoButtons
                    }
                    .padding()
                }
            }
            .navigationTitle("Photo of Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { stop(); dismiss() } }
            }
            .navigationDestination(for: Analysis.self) { analysis in
                switch analysis {
                case .estimate(let foods, let date):
                    LogMealView(title: "Meal from Photo", portions: foods, date: date,
                                note: "Estimated from your photo. Check each food and amount before logging.") {
                        dismiss()
                    }
                case .branded(let meal, let date):
                    LogMealView(branded: meal, date: date,
                                onRetryLookup: meal.failure == nil ? nil : { retryLookup(meal) }) { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $takingPhoto) {
                CameraPicker { image in
                    takingPhoto = false
                    if let image { use(image, dateTaken: nil) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                photo = nil
                Task { await load(item) }
            }
            .alert("Couldn't Read the Photo", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    private func form(_ image: UIImage) -> some View {
        Form {
            Section {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 260)
                    .clipShape(.rect(cornerRadius: 12))
                    .overlay {
                        if let stage {
                            VStack(spacing: 12) {
                                ProgressView(stage.title)
                                Button("Stop", role: .cancel) { stop() }
                                    .buttonStyle(.bordered)
                            }
                            .padding()
                            .background(.regularMaterial, in: .rect(cornerRadius: 12))
                        }
                    }
                    .accessibilityLabel("Your photo")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            Section {
                // At the largest text sizes the field gets the whole row, with its name as the prompt.
                if dynamicTypeSize.isAccessibilitySize {
                    // Named, since there's no label beside it to name it.
                    brandField(prompt: "Restaurant or Brand (Optional)")
                        .accessibilityLabel("Restaurant or Brand")
                } else {
                    LabeledContent("Restaurant or Brand") {
                        brandField(prompt: "Optional").multilineTextAlignment(.trailing)
                    }
                }
                TextField("Meal Details", text: $details, prompt: Text("Details, e.g. double chicken, no sour cream"),
                          axis: .vertical)
                    .lineLimit(1...4)
                    .focused($focused, equals: .details)
                    .accessibilityLabel("Meal Details")
                    .accessibilityIdentifier("Meal Details")
            } footer: {
                Text(footer)
            }
            Section {
                Button(cleanBrand.isEmpty ? "Estimate Nutrition" : "Look Up Nutrition",
                       systemImage: cleanBrand.isEmpty ? "sparkles" : "magnifyingglass") {
                    analyze()
                }
                .frame(maxWidth: .infinity)
                .disabled(stage != nil)
            }
            Section {
                photoButtons
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func brandField(prompt: String) -> some View {
        TextField("Restaurant or Brand", text: $brand, prompt: Text(prompt))
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.next)
            .focused($focused, equals: .brand)
            .onSubmit { focused = .details }
    }

    private var footer: String {
        if !cleanBrand.isEmpty {
            return "Logalyst finds the nutrition \(cleanBrand) publishes on its own website and reads it on your "
                + "iPhone. Apple Maps is asked for \(cleanBrand)'s website, which then sees a visit like any other. "
                + "Your photo, details and foods stay on your iPhone."
        }
        return "Add a restaurant or brand to use the nutrition it publishes. Without one, Apple Intelligence "
            + "estimates everything on your iPhone, and nothing is sent anywhere."
    }

    private var photoButtons: some View {
        HStack {
            PhotosPicker(selection: $photo, matching: .images) {
                Label(image == nil ? "Choose Photo" : "Choose Another", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.bordered)
            Spacer()
            #if DEBUG
            if MealPhoto.isStubbed {
                Button("Use Test Photo", systemImage: "photo") { use(Self.testPhoto, dateTaken: nil) }
                    .buttonStyle(.bordered)
            }
            #endif
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button(image == nil ? "Take Photo" : "Retake", systemImage: "camera") { takingPhoto = true }
                    .buttonStyle(.borderedProminent)
            }
        }
        .disabled(stage != nil)
    }

    #if DEBUG
    private static let testPhoto = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300)).image { context in
        UIColor.systemOrange.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
    }
    #endif

    private func load(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            error = "That photo couldn't be opened."
            return
        }
        // A photo from the library was likely taken at the meal, so log it then.
        use(image, dateTaken: MealPhoto.dateTaken(data))
    }

    private func use(_ image: UIImage, dateTaken: Date?) {
        stop()
        self.image = image
        self.dateTaken = dateTaken.map { min($0, .now) }
        lastItems = []
    }

    private func stop() {
        analysis?.cancel()
        analysis = nil
        stage = nil
    }

    private func analyze() {
        guard let image, let cgImage = image.cgImage, stage == nil else { return }
        focused = nil
        let brand = cleanBrand
        let details = details
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let known = savedFoods.map(\.portion) + recipes.map(\.portion)
        stage = .reading
        analysis = Task {
            defer { if !Task.isCancelled { stage = nil; analysis = nil } }
            do {
                if !brand.isEmpty {
                    let items = try await MealPhoto.brandedItems(in: cgImage, orientation: orientation, brand: brand,
                                                                 details: details)
                    lastItems = items
                    let meal = try await lookUp(items, brand: brand, known: known, in: NutritionLookup.shared)
                    path = [.branded(meal, date: dateTaken)]
                } else {
                    let foods = try await MealPhoto.foods(in: cgImage, orientation: orientation, known: known,
                                                          details: details)
                    try Task.checkCancellation()
                    path = [.estimate(foods, date: dateTaken)]
                }
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                self.error = error.localizedDescription
            }
        }
    }

    /// Looks the items up and puts the meal together. A failed lookup still gives a meal, of estimates, that says
    /// why; only cancelling stops it.
    private func lookUp(_ items: [MealPhoto.BrandedItem], brand: String, known: [FoodPortion],
                        in lookup: NutritionLookup) async throws -> BrandedMeal {
        stage = .lookingUp(brand)
        let result: Result<LookupResult, LookupError>
        if let request = LookupRequest(brand: brand, terms: items.map(\.searchTerm)) {
            do {
                result = .success(try await lookup.foods(for: request))
            } catch let error as LookupError {
                result = .failure(error)
            }
        } else {
            result = .success(LookupResult(foods: [:]))
        }
        try Task.checkCancellation()
        return BrandedMeal.assemble(items: items, brand: brand, lookup: result, known: known)
    }

    /// Tries the lookup again for the same foods, from the meal screen, which reopens with what it finds.
    private func retryLookup(_ meal: BrandedMeal) {
        guard !lastItems.isEmpty, stage == nil else { return }
        path = []
        let known = savedFoods.map(\.portion) + recipes.map(\.portion)
        let items = lastItems
        analysis = Task {
            defer { if !Task.isCancelled { stage = nil; analysis = nil } }
            do {
                path = [.branded(try await lookUp(items, brand: meal.brand, known: known, in: NutritionLookup.shared),
                                 date: dateTaken)]
            } catch {}
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
