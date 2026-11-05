import Foundation

/// Read-only Hevy client (docs/04). Needs a Hevy Pro API key, sent in the `api-key` header.
/// Nothing is ever sent to Hevy except the key and paging parameters.
/// The shapes below follow Hevy's public v1 API; verify against api.hevyapp.com/docs.
public struct HevyAPI: Sendable {
    public let apiKey: String
    public var base = URL(string: "https://api.hevyapp.com/v1/")!
    public var session: URLSession = .shared

    public init(apiKey: String) { self.apiKey = apiKey }

    public struct WorkoutDTO: Decodable, Sendable, Equatable {
        public let id: String
        public let title: String?
        public let start_time: Date
        public let end_time: Date
        public let exercises: [ExerciseDTO]
    }

    public struct ExerciseDTO: Decodable, Sendable, Equatable {
        public let index: Int
        public let title: String
        public let sets: [SetDTO]
    }

    public struct SetDTO: Decodable, Sendable, Equatable {
        public let index: Int
        public let type: String?
        public let weight_kg: Double?
        public let reps: Int?
        public let distance_meters: Double?
        public let duration_seconds: Double?
        public let rpe: Double?
    }

    struct WorkoutPage: Decodable {
        let page: Int
        let page_count: Int
        let workouts: [WorkoutDTO]
    }

    public enum Event: Sendable, Equatable {
        case updated(WorkoutDTO)
        case deleted(id: String)
    }

    struct EventPage: Decodable {
        let page: Int
        let page_count: Int
        let events: [RawEvent]
    }

    struct RawEvent: Decodable {
        let type: String
        let workout: WorkoutDTO?
        let id: String?
    }

    public enum HevyError: Error, Equatable {
        case unauthorized
        case http(Int)
    }

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f.date(from: s) { return date }
            f.formatOptions = [.withInternetDateTime]
            if let date = f.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "Bad date \(s)"))
        }
        return d
    }()

    public static func decodeWorkouts(_ data: Data) throws -> (workouts: [WorkoutDTO], pageCount: Int) {
        let p = try decoder.decode(WorkoutPage.self, from: data)
        return (p.workouts, p.page_count)
    }

    public static func decodeEvents(_ data: Data) throws -> (events: [Event], pageCount: Int) {
        let p = try decoder.decode(EventPage.self, from: data)
        let events: [Event] = p.events.compactMap { e in
            switch e.type {
            case "updated": e.workout.map(Event.updated)
            case "deleted": e.id.map { .deleted(id: $0) }
            default: nil
            }
        }
        return (events, p.page_count)
    }

    func get(_ path: String, _ query: [URLQueryItem]) async throws -> Data {
        var c = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        c.queryItems = query
        var req = URLRequest(url: c.url!)
        req.setValue(apiKey, forHTTPHeaderField: "api-key")
        req.setValue("application/json", forHTTPHeaderField: "accept")
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 || code == 403 { throw HevyError.unauthorized }
        guard (200..<300).contains(code) else { throw HevyError.http(code) }
        return data
    }

    /// Most recent workouts, newest first.
    public func recentWorkouts(pages: Int = 3) async throws -> [WorkoutDTO] {
        var all: [WorkoutDTO] = []
        var page = 1
        while page <= pages {
            let (ws, count) = try Self.decodeWorkouts(try await get("workouts", [.init(name: "page", value: "\(page)"), .init(name: "pageSize", value: "10")]))
            all += ws
            if page >= count { break }
            page += 1
        }
        return all
    }

    /// Changes since a date, for incremental sync.
    public func events(since: Date, maxPages: Int = 10) async throws -> [Event] {
        let f = ISO8601DateFormatter()
        var all: [Event] = []
        var page = 1
        while page <= maxPages {
            let (es, count) = try Self.decodeEvents(try await get("workouts/events", [
                .init(name: "page", value: "\(page)"), .init(name: "pageSize", value: "10"),
                .init(name: "since", value: f.string(from: since)),
            ]))
            all += es
            if page >= count { break }
            page += 1
        }
        return all
    }
}

extension HevyAPI.WorkoutDTO {
    /// A short description of the heaviest working set, e.g. "Squat 80 kg × 5".
    public var topSet: String? {
        var best: (String, Double, Int)?
        for e in exercises {
            for s in e.sets where s.type != "warmup" {
                guard let w = s.weight_kg, let r = s.reps, w > 0 else { continue }
                if best == nil || w > best!.1 { best = (e.title, w, r) }
            }
        }
        guard let best else { return nil }
        let kg = best.1.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(best.1)) : String(format: "%.1f", best.1)
        return "\(best.0) \(kg) kg × \(best.2)"
    }
}
