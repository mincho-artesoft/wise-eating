import Foundation

private struct RolePerformanceOutput: Codable {
    let catalogueCount: Int
    let coldMilliseconds: Double
    let cachedMilliseconds: Double
    let checksum: Int
}

@main
private enum MP7RolePerformanceHarness {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            fatalError(
                "usage: mp7_role_performance_harness "
                    + "food_roles.json.gz food-ids.json"
            )
        }
        let ids = try JSONDecoder().decode(
            [Int].self,
            from: Data(
                contentsOf: URL(
                    fileURLWithPath: CommandLine.arguments[2]
                )
            )
        )

        let coldStarted = DispatchTime.now().uptimeNanoseconds
        let compressed = try Data(
            contentsOf: URL(
                fileURLWithPath: CommandLine.arguments[1]
            ),
            options: .mappedIfSafe
        )
        let resolver = try FoodRoleResolver(
            compressedData: compressed
        )
        var checksum = ids.reduce(into: 0) {
            let resolution = resolver.resolution(for: $1)
            $0 &+= resolution.foodId
            $0 &+= resolution.notReadyToEat ? 1 : 0
            $0 &+= resolution.headword.count
        }
        let coldMilliseconds = elapsedMilliseconds(coldStarted)

        let cachedStarted = DispatchTime.now().uptimeNanoseconds
        checksum = ids.reduce(into: checksum) {
            let resolution = resolver.resolution(for: $1)
            $0 &+= resolution.foodId
            $0 &+= resolution.notReadyToEat ? 1 : 0
            $0 &+= resolution.headword.count
        }
        let cachedMilliseconds = elapsedMilliseconds(cachedStarted)

        let output = RolePerformanceOutput(
            catalogueCount: ids.count,
            coldMilliseconds: coldMilliseconds,
            cachedMilliseconds: cachedMilliseconds,
            checksum: checksum
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(output))
        FileHandle.standardOutput.write(Data([0x0A]))
    }

    private static func elapsedMilliseconds(
        _ started: UInt64
    ) -> Double {
        Double(
            DispatchTime.now().uptimeNanoseconds - started
        ) / 1_000_000
    }
}
