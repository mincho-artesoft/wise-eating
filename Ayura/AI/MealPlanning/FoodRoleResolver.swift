import Foundation

struct FoodRolePortionRange: Codable, Equatable, Sendable {
    let min: Double
    let typical: Double
    let max: Double
}

struct FoodRoleDefinition: Codable, Equatable, Sendable {
    let id: FoodRole
    let anchor: Bool
    let minPerMeal: Int
    let maxPerMeal: Int
    let portionGrams: FoodRolePortionRange
    let eligibleAsComponent: Bool
}

struct FoodRoleResolution: Codable, Equatable, Sendable {
    let foodId: Int
    let role: FoodRole
    let ruleId: String
    let notReadyToEat: Bool
    let headword: String
}

/// Immutable build-time role cache for the canonical 14,484-row catalogue.
///
/// This mirrors `FoodConcepts`: source rules are evaluated by `build_seed.py`
/// once, the deterministic membership is shipped, and planning performs only
/// food-ID lookups. User-created rows outside the canonical catalogue receive
/// the documented non-anchoring `other` fallback.
struct FoodRoleResolver: Sendable {
    static let shared: FoodRoleResolver = {
        do {
            return try FoodRoleResolver()
        } catch {
            fatalError("Malformed food_roles.json.gz: \(error)")
        }
    }()

    private let resolutionByFoodID: [Int: FoodRoleResolution]
    private let definitionByRole: [FoodRole: FoodRoleDefinition]

    private init(bundle: Bundle = .main) throws {
        guard let url = bundle.url(
            forResource: "food_roles",
            withExtension: "json.gz"
        ) else {
            throw FoodRoleResolverError.missingBundle
        }
        try self.init(
            compressedData: Data(
                contentsOf: url,
                options: .mappedIfSafe
            )
        )
    }

    init(compressedData: Data) throws {
        let plain = try ZlibGzip.decompress(data: compressedData)
        let document = try JSONDecoder().decode(
            FoodRoleDocument.self,
            from: plain
        )
        guard document.rolesVersion == 9,
              document.catalogCount == 14_484,
              document.roleCount == FoodRole.allCases.count,
              document.ruleCount == 34,
              document.items.count == document.catalogCount,
              document.definitions.count == document.roleCount
        else {
            throw FoodRoleResolverError.invalidCounts
        }

        let resolutions = Dictionary(
            document.items.map { ($0.foodId, $0) },
            uniquingKeysWith: { _, _ in
                fatalError("Duplicate food role resolution")
            }
        )
        let definitions = Dictionary(
            document.definitions.map { ($0.id, $0) },
            uniquingKeysWith: { _, _ in
                fatalError("Duplicate food role definition")
            }
        )
        guard resolutions.count == document.catalogCount,
              definitions.count == document.roleCount,
              definitions[.other] != nil
        else {
            throw FoodRoleResolverError.invalidCounts
        }
        resolutionByFoodID = resolutions
        definitionByRole = definitions
    }

    func resolution(for foodID: Int) -> FoodRoleResolution {
        resolutionByFoodID[foodID] ?? FoodRoleResolution(
            foodId: foodID,
            role: .other,
            ruleId: "runtime-default",
            notReadyToEat: false,
            headword: "unknown"
        )
    }

    func definition(for role: FoodRole) -> FoodRoleDefinition {
        if let definition = definitionByRole[role] {
            return definition
        }
        preconditionFailure("Missing shipped definition for food role \(role)")
    }

    func isNearDuplicate(foodID lhs: Int, foodID rhs: Int) -> Bool {
        let left = resolution(for: lhs)
        let right = resolution(for: rhs)
        return left.role == right.role
            && left.headword != "unknown"
            && left.headword == right.headword
    }
}

private struct FoodRoleDocument: Decodable, Sendable {
    let rolesVersion: Int
    let catalogCount: Int
    let roleCount: Int
    let ruleCount: Int
    let definitions: [FoodRoleDefinition]
    let items: [FoodRoleResolution]
}

private enum FoodRoleResolverError: Error {
    case missingBundle
    case invalidCounts
}
