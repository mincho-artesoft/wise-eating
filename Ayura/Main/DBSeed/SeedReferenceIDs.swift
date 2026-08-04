import Foundation

enum SeedReferenceIDs {
    struct Entity: Decodable, Sendable {
        let id: UUID
        let key: String
        let requirementIds: [UUID]
    }

    private struct Document: Decodable, Sendable {
        let identitySchema: String
        let entities: [String: [Entity]]
    }

    private static let records: [String: [String: Entity]] = {
        guard let url = Bundle.main.url(
            forResource: "reference_ids",
            withExtension: "json"
        ) else {
            fatalError("reference_ids.json is missing from the app bundle")
        }
        do {
            let document = try JSONDecoder().decode(
                Document.self,
                from: Data(contentsOf: url)
            )
            guard document.identitySchema == "stable-uuid-v1" else {
                fatalError(
                    "Unsupported reference identity schema: \(document.identitySchema)"
                )
            }
            return document.entities.mapValues { rows in
                Dictionary(uniqueKeysWithValues: rows.map { ($0.key, $0) })
            }
        } catch {
            fatalError("Unable to decode reference_ids.json: \(error)")
        }
    }()

    static func entity(kind: String, key: String) -> Entity {
        guard let entity = records[kind]?[key] else {
            fatalError("Missing stable UUIDs for \(kind) \(key)")
        }
        return entity
    }
}
