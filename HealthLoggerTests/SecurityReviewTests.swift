import Foundation
import HealthKit
import PDFKit
import Testing
import UIKit
@testable import HealthLogger

// Regression tests for SECURITY-REVIEW.md. SR-1: only Logalyst's own Health samples are treated as its entries.
// SR-3: remote responses are limited while they download, and nutrition PDFs before they're read through.

// MARK: - SR-1: Health entry provenance

struct EntryProvenanceTests {
    private let tagged: [String: Any] = [HealthStore.entryMetadataKey: true]

    @Test func entriesFromTheAppAndWatchAreOurs() {
        #expect(HealthStore.isOwn(metadata: tagged, sourceBundleIdentifier: "com.justinleahy.HealthLogger"))
        #expect(HealthStore.isOwn(metadata: tagged, sourceBundleIdentifier: "com.justinleahy.HealthLogger.watchkitapp"))
    }

    @Test func anotherAppCopyingTheTagIsNotOurs() {
        #expect(!HealthStore.isOwn(metadata: tagged, sourceBundleIdentifier: "com.example.HealthApp"))
        // Similar names don't count: the list is exact.
        #expect(!HealthStore.isOwn(metadata: tagged, sourceBundleIdentifier: "com.justinleahy.HealthLogger.evil"))
        #expect(!HealthStore.isOwn(metadata: tagged, sourceBundleIdentifier: "com.justinleahy.HealthLoggerX"))
    }

    @Test func ourAppsUntaggedSamplesAreNotEntries() {
        #expect(!HealthStore.isOwn(metadata: nil, sourceBundleIdentifier: "com.justinleahy.HealthLogger"))
        #expect(!HealthStore.isOwn(metadata: [HKMetadataKeyWasUserEntered: true],
                                   sourceBundleIdentifier: "com.justinleahy.HealthLogger"))
    }

    /// Tests run inside the app, so its samples come from the app's own bundle identifier.
    @Test func theAppsBundleIdentifierIsAllowed() {
        #expect(HealthStore.ownBundleIdentifiers.contains(Bundle.main.bundleIdentifier ?? ""))
    }

    private func sourceMetadata(url: String) -> [String: Any] {
        [HealthStore.sourceTitleMetadataKey: "Nutrition", HealthStore.sourceURLMetadataKey: url,
         HealthStore.sourceRetrievedMetadataKey: Date.now]
    }

    @Test func onlySecureSourcesAreRead() {
        #expect(HealthStore.source(in: sourceMetadata(url: "https://www.chipotle.com/nutrition.pdf")) != nil)
        #expect(HealthStore.source(in: sourceMetadata(url: "http://www.chipotle.com/nutrition.pdf")) == nil)
        #expect(HealthStore.source(in: sourceMetadata(url: "javascript:alert(1)")) == nil)
        #expect(HealthStore.source(in: sourceMetadata(url: "tel:5555555555")) == nil)
        #expect(HealthStore.source(in: sourceMetadata(url: "https:///nohost")) == nil)
    }
}

/// An entry the app saves is still listed as its own and can be deleted. Needs Health access in the simulator.
@MainActor
@Suite(.serialized)
final class OwnEntryHealthTests {
    private let raw = HKHealthStore()
    private let health = HealthStore(syncs: false, editDefaults: UserDefaults(suiteName: "OwnEntryHealthTests")!)
    private let start = Date.now.addingTimeInterval(-2 * 3600)

    init() throws {
        let status = raw.authorizationStatus(for: HKQuantityType(.dietaryWater))
        try #require(status == .sharingAuthorized, "Open Logalyst in this simulator and allow Health access first.")
    }

    @Test func aSavedEntryIsListedAsOursAndDeletable() async throws {
        let water = try #require(Metric.metric(id: "dietaryWater"))
        let option = try #require(water.unitOptions.first)
        try await health.saveQuantity(water, value: 321, option: option, date: start)
        let entries = try await health.recentEntries(of: [water], includingFoods: false,
                                                     since: start.addingTimeInterval(-1), before: start.addingTimeInterval(1))
        let entry = try #require(entries.first)
        #expect(HealthStore.isOwn(entry.sample))
        #expect(HealthStore.ownBundleIdentifiers.contains(entry.sample.sourceRevision.source.bundleIdentifier))
        try await health.delete(entry)
    }
}

// MARK: - SR-3: Bounded downloads

/// Serves canned responses by path. Bodies are sent in chunks, slowly enough that a cancelled download stops them.
nonisolated final class StubServer: URLProtocol, @unchecked Sendable {
    static let chunk = 16 * 1024
    static let streamedBytes = 8 * 1024 * 1024
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _sent: [String: Int] = [:]
    nonisolated(unsafe) private static var _stopped: Set<String> = []

    static func sent(_ path: String) -> Int { lock.withLock { _sent[path] ?? 0 } }
    static func stopped(_ path: String) -> Bool { lock.withLock { _stopped.contains(path) } }

    private var cancelled = false
    private let cancelLock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let path = url.path()
        var headers: [String: String] = [:]
        var status = 200
        var body = Data()
        var total = 0
        switch path {
        case "/ok":
            headers["Content-Type"] = "application/json"
            body = Data(#"{"product":{"product_name":"Oats"}}"#.utf8)
        case "/stream":
            // No Content-Length, and far more than any limit.
            headers["Content-Type"] = "application/json"
            total = Self.streamedBytes
        case "/declared":
            headers["Content-Type"] = "application/json"
            headers["Content-Length"] = String(Self.streamedBytes)
            total = Self.streamedBytes
        case "/html":
            headers["Content-Type"] = "text/html"
            body = Data("<html></html>".utf8)
        default:
            status = 404
            headers["Content-Type"] = "application/json"
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        guard total > 0 else {
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        DispatchQueue.global().async { [self] in
            var sent = 0
            while sent < total, !cancelLock.withLock({ cancelled }) {
                client?.urlProtocol(self, didLoad: Data(repeating: 0x20, count: Self.chunk))
                sent += Self.chunk
                Self.lock.withLock { Self._sent[path] = sent }
                usleep(500)
            }
            if !cancelLock.withLock({ cancelled }) { client?.urlProtocolDidFinishLoading(self) }
        }
    }

    override func stopLoading() {
        cancelLock.withLock { cancelled = true }
        let path = request.url!.path()
        Self.lock.withLock { _ = Self._stopped.insert(path) }
    }
}

@Suite(.serialized)
struct BoundedDownloadTests {
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubServer.self]
        return URLSession(configuration: configuration)
    }()

    private func request(_ path: String) -> URLRequest {
        URLRequest(url: URL(string: "https://stub.test\(path)")!)
    }

    @Test func aNormalResponseIsRead() async throws {
        let data = try await BoundedDownload.data(for: request("/ok"), session: session, maxBytes: 1_000,
                                                  accepts: BoundedDownload.isJSON)
        #expect(String(data: data, encoding: .utf8)?.contains("Oats") == true)
    }

    @Test func aStreamWithoutALengthIsCutOffAtTheLimit() async throws {
        await #expect(throws: BoundedDownload.Failure.tooLarge) {
            try await BoundedDownload.data(for: request("/stream"), session: session, maxBytes: 64 * 1024)
        }
        // The server is told to stop well before it has sent everything.
        for _ in 0..<40 where !StubServer.stopped("/stream") { try await Task.sleep(for: .milliseconds(50)) }
        #expect(StubServer.stopped("/stream"))
        #expect(StubServer.sent("/stream") < StubServer.streamedBytes)
    }

    @Test func aDeclaredOversizedResponseIsRefusedBeforeItsBody() async throws {
        await #expect(throws: BoundedDownload.Failure.tooLarge) {
            try await BoundedDownload.data(for: request("/declared"), session: session, maxBytes: 64 * 1024)
        }
        for _ in 0..<40 where !StubServer.stopped("/declared") { try await Task.sleep(for: .milliseconds(50)) }
        #expect(StubServer.stopped("/declared"))
        #expect(StubServer.sent("/declared") < StubServer.streamedBytes)
    }

    @Test func errorStatusesAndWrongTypesAreRefused() async throws {
        await #expect(throws: BoundedDownload.Failure.status(404)) {
            try await BoundedDownload.data(for: request("/missing"), session: session, maxBytes: 1_000)
        }
        await #expect(throws: BoundedDownload.Failure.unexpectedType("text/html")) {
            try await BoundedDownload.data(for: request("/html"), session: session, maxBytes: 1_000,
                                           accepts: BoundedDownload.isJSON)
        }
    }

    @Test func contentTypes() {
        #expect(BoundedDownload.isJSON("application/json"))
        #expect(BoundedDownload.isTextOrXML("text/plain"))
        #expect(BoundedDownload.isTextOrXML("application/xml"))
        #expect(!BoundedDownload.isTextOrXML("application/pdf"))
        #expect(BoundedDownload.isPDF("application/pdf"))
        #expect(!BoundedDownload.isPDF("text/html"))
    }

    @MainActor
    @Test func overlongBarcodesAreNotLookedUp() async throws {
        #expect(try await FoodDatabase.lookUp(barcode: String(repeating: "1", count: 15)) == nil)
    }
}

// MARK: - SR-3: PDF limits

struct PDFTextTests {
    /// A PDF with one line of text per page.
    private func pdf(pages: [String]) throws -> PDFDocument {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        let data = renderer.pdfData { context in
            for text in pages {
                context.beginPage()
                (text as NSString).draw(at: CGPoint(x: 40, y: 40), withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
            }
        }
        return try #require(PDFDocument(data: data))
    }

    @Test func aNormalPDFIsRead() throws {
        let lines = try PDFText.lines(in: pdf(pages: ["Chicken 180", "Rice 210"]))
        #expect(lines.joined(separator: " ").contains("Chicken 180"))
        #expect(lines.joined(separator: " ").contains("Rice 210"))
    }

    @Test func tooManyPagesIsRefused() throws {
        let document = try pdf(pages: ["a", "b", "c"])
        #expect(throws: PDFText.Failure.tooManyPages) { try PDFText.lines(in: document, maxPages: 2) }
    }

    @Test func tooMuchTextIsRefused() throws {
        let document = try pdf(pages: ["Chicken 180 calories", "Rice 210 calories"])
        #expect(throws: PDFText.Failure.tooMuchText) { try PDFText.lines(in: document, maxCharacters: 25) }
        #expect(throws: PDFText.Failure.tooMuchText) { try PDFText.lines(in: document, maxCharactersPerPage: 5) }
    }

    @Test func somethingElseIsNotReadAsAPDF() {
        #expect(throws: PDFText.Failure.notPDF) { try PDFText.lines(in: Data("<html>".utf8)) }
    }

    @Test func theDefaultLimitsAllowLargeNutritionGuides() {
        #expect(PDFText.maxPages >= 40)
    }
}
