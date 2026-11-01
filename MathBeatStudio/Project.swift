import Foundation

enum Waveform: String, Codable, CaseIterable, Identifiable {
    case sine, square, triangle, sawtooth
    var id: String { rawValue }
}

struct BeatProject: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = "Untitled Beat"
    var bpm: Double = 120
    var waveform: Waveform = .sine
    // Each step is a sixteenth note; nil represents a rest.
    var steps: [Int?] = [60, nil, 64, nil, 67, nil, 64, nil, 60, nil, 65, nil, 69, nil, 67, nil]

    func validated() throws -> Self {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              bpm.isFinite, (40...240).contains(bpm), steps.count == 16,
              steps.allSatisfy({ $0 == nil || (48...84).contains($0!) }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return self
    }
}

enum ProjectStore {
    static func directory() throws -> URL {
        let root = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        let directory = root.appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func save(_ project: BeatProject) throws {
        let valid = try project.validated()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(valid).write(to: directory().appendingPathComponent("\(valid.id).json"), options: .atomic)
    }

    static func list() throws -> [BeatProject] {
        let files = try FileManager.default.contentsOfDirectory(at: directory(), includingPropertiesForKeys: nil)
        return try files.filter { $0.pathExtension == "json" }.map {
            try JSONDecoder().decode(BeatProject.self, from: Data(contentsOf: $0)).validated()
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func delete(_ project: BeatProject) throws {
        try FileManager.default.removeItem(at: directory().appendingPathComponent("\(project.id).json"))
    }
}
