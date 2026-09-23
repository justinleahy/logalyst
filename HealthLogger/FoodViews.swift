import SwiftUI
import SwiftData
import Vision
import VisionKit
import AVFoundation

// MARK: - Library

/// Saved foods, most recently logged first.
struct FoodLibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Food.name) private var foods: [Food]
    @State private var search = ""
    @State private var editor: EditorTarget?
    @State private var scanning = false

    private enum EditorTarget: Identifiable {
        case new
        case edit(Food)

        var id: PersistentIdentifier? {
            if case .edit(let food) = self { food.persistentModelID } else { nil }
        }
    }

    var body: some View {
        List {
            ForEach(visibleFoods) { food in
                NavigationLink {
                    LogFoodView(food: food)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(food.name)
                        if !food.summary.isEmpty {
                            Text(food.summary).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) { context.delete(food) }
                    Button("Edit", systemImage: "pencil") { editor = .edit(food) }
                }
            }
        }
        .overlay {
            if foods.isEmpty {
                ContentUnavailableView {
                    Label("No Foods Yet", systemImage: "fork.knife")
                } description: {
                    Text("Create a food from its nutrition label, or scan its barcode to fill it in.")
                } actions: {
                    Button("Scan Barcode") { scanning = true }.buttonStyle(.borderedProminent)
                    Button("New Food") { editor = .new }
                }
            } else if visibleFoods.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .searchable(text: $search, prompt: "Search Foods")
        .navigationTitle("My Foods")
        .toolbar {
            Button("Scan Barcode", systemImage: "barcode.viewfinder") { scanning = true }
            Button("New Food", systemImage: "plus") { editor = .new }
        }
        .sheet(item: $editor) { target in
            NavigationStack {
                switch target {
                case .new: FoodEditor { _ in editor = nil }.cancelButton { editor = nil }
                case .edit(let food): FoodEditor(food: food) { _ in editor = nil }.cancelButton { editor = nil }
                }
            }
        }
        .sheet(isPresented: $scanning) { ScanFoodView() }
    }

    private var visibleFoods: [Food] {
        let matches = search.isEmpty ? foods : foods.filter {
            $0.name.localizedStandardContains(search) || $0.brand.localizedStandardContains(search)
        }
        // Recently logged first, then alphabetical (the query's order) for the rest.
        return matches.enumerated().sorted { a, b in
            let (dateA, dateB) = (a.element.lastLogged ?? .distantPast, b.element.lastLogged ?? .distantPast)
            return dateA != dateB ? dateA > dateB : a.offset < b.offset
        }.map(\.element)
    }
}

private extension View {
    func cancelButton(_ action: @escaping () -> Void) -> some View {
        toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: action) }
        }
    }
}

// MARK: - Logging

struct LogFoodView: View {
    let food: Food
    /// Called after saving; pops this screen when nil.
    var onSaved: (() -> Void)?

    @Environment(HealthStore.self) private var health
    @Environment(\.dismiss) private var dismiss
    @State private var servings = 1.0
    @State private var date = Date.now
    @State private var error: String?
    @State private var isSaving = false
    @State private var saved = false

    var body: some View {
        Form {
            Section {
                if !food.servingSize.isEmpty {
                    LabeledContent("Serving Size", value: food.servingSize)
                }
                HStack {
                    Text("Servings")
                    Spacer()
                    TextField("1", value: $servings, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(maxWidth: 60)
                    Stepper("Servings", value: $servings, in: 0.5...20, step: 0.5)
                        .labelsHidden()
                }
            } header: {
                if !food.brand.isEmpty { Text(food.brand) }
            }
            Section("Nutrition") {
                ForEach(FoodNutrient.metrics.filter { food.amount(of: $0) > 0 }) { metric in
                    if let option = metric.unitOptions.first {
                        LabeledContent {
                            Text(option.format(food.amount(of: metric) * servings)).monospacedDigit()
                        } label: {
                            Label(metric.name, systemImage: metric.systemImage)
                        }
                    }
                }
            }
            Section {
                DatePicker("Date & Time", selection: $date, in: ...Date.now)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(food.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Log", action: save).disabled(isSaving || servings <= 0)
            }
        }
        .sensoryFeedback(.success, trigger: saved)
        .alert("Couldn't Save", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private func save() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let amounts = FoodNutrient.metrics.map { ($0, food.amount(of: $0) * servings) }
                try await health.saveFood(named: food.name, amounts: amounts, date: date)
                food.lastLogged = .now
                saved.toggle()
                if let onSaved { onSaved() } else { dismiss() }
            } catch {
                self.error = error.healthMessage
            }
        }
    }
}

// MARK: - Editing

struct FoodEditor: View {
    let food: Food?
    let onSave: (Food) -> Void

    @Environment(\.modelContext) private var context
    @State private var draft: FoodDraft

    init(food: Food? = nil, draft: FoodDraft? = nil, onSave: @escaping (Food) -> Void) {
        self.food = food
        self.onSave = onSave
        _draft = State(initialValue: draft ?? food?.draft ?? FoodDraft())
    }

    var body: some View {
        Form {
            Section {
                textField("Name", text: $draft.name, prompt: "Required")
                textField("Brand", text: $draft.brand, prompt: "Optional")
                textField("Serving Size", text: $draft.servingSize, prompt: "e.g. 1 cup or 30 g")
            } footer: {
                switch draft.source {
                case .database: Text("Filled in from Open Food Facts. Check it against the label before saving.")
                case .notFound: Text("This barcode isn't in Open Food Facts. Enter the details from the label.")
                case .manual: EmptyView()
                }
            }
            Section("Nutrition per Serving") {
                ForEach(FoodNutrient.metrics) { nutrientField($0) }
            }
            if let barcode = draft.barcode {
                Section("Barcode") {
                    Text(barcode).monospacedDigit()
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(food == nil ? "New Food" : "Edit Food")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save).disabled(!draft.isValid)
            }
        }
    }

    private func textField(_ title: String, text: Binding<String>, prompt: String) -> some View {
        LabeledContent(title) {
            TextField(title, text: text, prompt: Text(prompt))
                .multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder
    private func nutrientField(_ metric: Metric) -> some View {
        if let option = metric.unitOptions.first {
            let amount = Binding<Double?> {
                draft.nutrients[metric.id]
            } set: {
                draft.nutrients[metric.id] = $0
            }
            HStack {
                Label(metric.name, systemImage: metric.systemImage)
                Spacer()
                TextField("0", value: amount, format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(maxWidth: 90)
                Text(option.label).foregroundStyle(.secondary)
            }
        }
    }

    private func save() {
        let saved: Food
        if let food {
            food.update(from: draft)
            saved = food
        } else {
            saved = Food(draft)
            context.insert(saved)
        }
        onSave(saved)
    }
}

// MARK: - Scanning

/// Scans (or takes a typed) barcode, then logs the matching saved food or creates one from a lookup.
struct ScanFoodView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var path: [Step] = []
    @State private var cameraReady = false
    @State private var typedCode = ""
    @State private var lookingUp = false
    @State private var error: String?

    private enum Step: Hashable {
        case log(Food)
        case create(FoodDraft)
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                ZStack {
                    if cameraReady {
                        BarcodeScanner(onScan: handle)
                    } else {
                        ContentUnavailableView("Camera Unavailable", systemImage: "barcode.viewfinder",
                                               description: Text("Type the number under the barcode instead."))
                    }
                    if lookingUp {
                        ProgressView("Looking Up…")
                            .padding()
                            .background(.regularMaterial, in: .rect(cornerRadius: 12))
                    }
                }
                .frame(maxHeight: .infinity)
                HStack {
                    TextField("Barcode Number", text: $typedCode)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    Button("Look Up") { handle(typedCode) }
                        .buttonStyle(.borderedProminent)
                        .disabled(typedCode.isEmpty || lookingUp)
                }
                .padding()
            }
            .navigationTitle("Scan Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .navigationDestination(for: Step.self) { step in
                switch step {
                case .log(let food): LogFoodView(food: food) { dismiss() }
                case .create(let draft): FoodEditor(draft: draft) { food in path = [.log(food)] }
                }
            }
            .alert("Couldn't Look Up Barcode", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
            .task {
                if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                    _ = await AVCaptureDevice.requestAccess(for: .video)
                }
                cameraReady = BarcodeScanner.isAvailable
            }
        }
    }

    private func handle(_ code: String) {
        let barcode = code.filter { $0.isASCII && $0.isNumber }
        // The scanner keeps reporting while a result is on screen, so ignore it until we're back.
        guard !barcode.isEmpty, path.isEmpty, !lookingUp else { return }
        if let food = savedFood(withBarcode: barcode) {
            path = [.log(food)]
            return
        }
        lookingUp = true
        Task {
            defer { lookingUp = false }
            do {
                let draft = try await FoodDatabase.lookUp(barcode: barcode)
                    ?? FoodDraft(barcode: barcode, source: .notFound)
                path = [.create(draft)]
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func savedFood(withBarcode barcode: String) -> Food? {
        var descriptor = FetchDescriptor<Food>(predicate: #Predicate { $0.barcode == barcode })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}

/// Live camera barcode reader.
private struct BarcodeScanner: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])],
            qualityLevel: .balanced, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onScan = onScan
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onScan: (String) -> Void

        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            for case .barcode(let barcode) in addedItems {
                if let value = barcode.payloadStringValue {
                    onScan(value)
                    return
                }
            }
        }
    }
}
