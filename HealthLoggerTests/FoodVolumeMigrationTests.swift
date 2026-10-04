import Foundation
import SwiftData
import Testing
@testable import HealthLogger

/// The saved-food entity immediately before C6. Its entity name and existing attributes match the app's Food.
private enum BeforeFoodVolume {
    @Model
    final class Food {
        @Attribute(.allowsCloudEncryption) var name = ""
        @Attribute(.allowsCloudEncryption) var brand = ""
        @Attribute(.allowsCloudEncryption) var servingSize = ""
        @Attribute(.allowsCloudEncryption) var gramsPerServing: Double?
        @Attribute(.allowsCloudEncryption) var barcode: String?
        @Attribute(.allowsCloudEncryption) var nutrients: [String: Double] = [:]
        @Attribute(.allowsCloudEncryption) var created = Date.now
        @Attribute(.allowsCloudEncryption) var lastLogged: Date?
        @Attribute(.allowsCloudEncryption) var isFavorite = false
        @Attribute(.allowsCloudEncryption) var uuid: UUID?

        init() {}
    }
}

@MainActor
struct FoodVolumeMigrationTests {
    @Test func addingOptionalVolumeUpgradesAnExistingLocalStoreWithoutChangingItsBasis() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Food.store")
        let id = UUID()
        try writeLegacyStore(at: url, id: id)

        let container = try ModelContainer(for: Food.self,
                                           configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        let context = ModelContext(container)
        let food = try #require(try context.fetch(FetchDescriptor<Food>()).first)
        #expect(food.name == "Legacy milk")
        #expect(food.uuid == id)
        #expect(food.isFavorite)
        #expect(food.nutrients == ["dietaryEnergyConsumed": 60, "dietaryProtein": 3.3])
        #expect(food.servingSize == "100 mL")
        #expect(food.millilitersPerServing == nil)
        #expect(food.portion.enteredVolumeUnit == nil)
        #expect(food.draft.statedServingVolume == 100)

        var reviewed = food.draft
        reviewed.millilitersPerServing = 100
        reviewed.nutrients["dietarySodium"] = 0
        food.update(from: reviewed)
        try context.save()
        #expect(food.portion.enteredVolumeUnit == .milliliters)
        #expect(food.nutrients["dietarySodium"] == 0)
    }

    private func writeLegacyStore(at url: URL, id: UUID) throws {
        let container = try ModelContainer(for: BeforeFoodVolume.Food.self,
                                           configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        let context = ModelContext(container)
        let food = BeforeFoodVolume.Food()
        food.name = "Legacy milk"
        food.servingSize = "100 mL"
        food.nutrients = ["dietaryEnergyConsumed": 60, "dietaryProtein": 3.3]
        food.isFavorite = true
        food.uuid = id
        context.insert(food)
        try context.save()
    }
}
