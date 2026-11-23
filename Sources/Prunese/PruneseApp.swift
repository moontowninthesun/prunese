import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let pruneseLevel = UTType(exportedAs: "com.prunese.level")
}

struct LevelDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pruneseLevel] }
    var draft: RouteDraft

    init(draft: RouteDraft = .example) { self.draft = draft }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        draft = try JSONDecoder().decode(RouteDraft.self, from: data)
        guard draft.version == 1 else {
            throw RouteImportError("This document needs a newer version of Prunese.")
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(draft))
    }
}

@main
struct PruneseApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: LevelDocument()) { configuration in
            WorkspaceView(document: configuration.$document)
        }
        .defaultSize(width: 1350, height: 800)
    }
}
