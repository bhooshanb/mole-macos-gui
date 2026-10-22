import Foundation

enum SparkCleanJSON {
    /// ISO-8601 variants emitted by the Go binaries (fractional seconds optional,
    /// numeric UTC offset as produced by Go's time package).
    private static let dateFormatters: [ISO8601DateFormatter] = [
        {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }(),
        {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f
        }(),
    ]

    private static let sessionDateFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func decodeDate(_ raw: String) -> Date? {
        for formatter in dateFormatters {
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }

    /// Decode a `yyyy-MM-dd HH:mm:ss` operations-log timestamp.
    static func decodeSessionDate(_ raw: String) -> Date? {
        sessionDateFormat.date(from: raw)
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let raw = try? container.decode(String.self) {
                if let date = decodeDate(raw) { return date }
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Unparseable date: \(raw)")
            }
            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: seconds)
            }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unsupported date encoding")
        }
        return decoder
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try makeDecoder().decode(type, from: data)
    }
}
