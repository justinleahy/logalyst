import Foundation
import PDFKit

/// Downloads from servers the app doesn't control (Open Food Facts and brands' websites) with a size limit that's
/// enforced while the body arrives, so a huge or endless response is cut off at the limit rather than read whole.
nonisolated enum BoundedDownload {
    enum Failure: LocalizedError, Equatable {
        /// The server answered with a status other than 200, such as 404.
        case status(Int)
        /// The response isn't the kind of document asked for, going by its Content-Type.
        case unexpectedType(String?)
        /// The response is, or says it is, longer than the limit.
        case tooLarge

        var errorDescription: String? {
            switch self {
            case .status: "The server couldn't answer right now. Try again later."
            case .unexpectedType: "The server's answer wasn't in the expected format."
            case .tooLarge: "The server's answer was too large to read."
            }
        }
    }

    /// The body of a successful response of at most `maxBytes`. The status and Content-Type (when `accepts` is
    /// given) are checked before any of the body is read, and a declared length over the limit is refused before
    /// it's downloaded. The download is cancelled as soon as it passes the limit, whatever length was declared.
    @concurrent
    static func data(for request: URLRequest, session: URLSession, maxBytes: Int,
                     accepts: ((String) -> Bool)? = nil) async throws -> Data {
        let (bytes, response) = try await session.bytes(for: request)
        let task = bytes.task
        do {
            guard let http = response as? HTTPURLResponse else { throw Failure.status(0) }
            guard http.statusCode == 200 else { throw Failure.status(http.statusCode) }
            if let accepts {
                let type = http.mimeType?.lowercased()
                guard let type, accepts(type) else { throw Failure.unexpectedType(type) }
            }
            if http.expectedContentLength > Int64(maxBytes) { throw Failure.tooLarge }
            var data = [UInt8]()
            data.reserveCapacity(Int(min(max(http.expectedContentLength, 0), Int64(maxBytes))))
            for try await byte in bytes {
                guard data.count < maxBytes else { throw Failure.tooLarge }
                data.append(byte)
            }
            return Data(data)
        } catch {
            task.cancel()
            throw error
        }
    }

    static func isJSON(_ type: String) -> Bool { type == "application/json" || type.hasSuffix("+json") }
    /// robots.txt and sitemaps, which sites serve as plain text or one of several XML types.
    static func isTextOrXML(_ type: String) -> Bool { type.hasPrefix("text/") || type.hasSuffix("xml") }
    /// Many sites serve PDFs as generic binary data, so those are accepted too; the file's own header is checked
    /// before it's opened.
    static func isPDF(_ type: String) -> Bool {
        ["application/pdf", "application/x-pdf", "application/octet-stream", "binary/octet-stream"].contains(type)
    }
}

/// The text of a downloaded nutrition PDF, refusing documents too long to be a nutrition guide before reading them
/// through, since a small file can hold a great many pages or a great deal of text.
nonisolated enum PDFText {
    static let maxPages = 60
    static let maxCharactersPerPage = 40_000
    static let maxCharacters = 600_000

    enum Failure: Error, Equatable {
        case notPDF
        case tooManyPages
        case tooMuchText
    }

    static func lines(in data: Data) throws -> [String] {
        guard data.starts(with: Data("%PDF".utf8)), let pdf = PDFDocument(data: data) else { throw Failure.notPDF }
        return try lines(in: pdf)
    }

    /// The limits can be lowered for tests.
    static func lines(in pdf: PDFDocument, maxPages: Int = maxPages, maxCharactersPerPage: Int = maxCharactersPerPage,
                      maxCharacters: Int = maxCharacters) throws -> [String] {
        guard pdf.pageCount <= maxPages else { throw Failure.tooManyPages }
        var lines: [String] = []
        var characters = 0
        for index in 0..<pdf.pageCount {
            let text = pdf.page(at: index)?.string ?? ""
            characters += text.count
            guard text.count <= maxCharactersPerPage, characters <= maxCharacters else { throw Failure.tooMuchText }
            lines += text.split(whereSeparator: \.isNewline).map(String.init)
        }
        return lines
    }
}
