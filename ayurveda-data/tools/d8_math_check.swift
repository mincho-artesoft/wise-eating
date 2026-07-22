import Foundation

@main
struct D8MathCheck {
  private static var passed = 0
  private static var total = 0

  static func main() {
    checkPercentages(0, 0, 0, expected: (34, 33, 33))
    checkPercentages(-1, 1, 2, expected: (13, 37, 50))
    checkPercentages(2, 0, -1, expected: (57, 29, 14))
    checkPercentages(-2, -2, -2, expected: (33, 33, 34))
    checkPercentages(1, 0, 1, expected: (38, 25, 37))
    checkPercentages(2, -1, 2, expected: (45, 11, 44))
    checkPercentages(0, 2, 0, expected: (25, 50, 25))
    checkPercentages(0, 1, -1, expected: (33, 50, 17))
    checkPercentages(-2, 2, -2, expected: (0, 100, 0))
    checkPercentages(-1, -1, -1, expected: (34, 33, 33))

    check(AyurvedaDisplayMath.tierLabel(.classical) == "Classical", "classical tier")
    check(AyurvedaDisplayMath.tierLabel(.recipe) == "Recipe", "recipe tier")
    check(AyurvedaDisplayMath.tierLabel(.derived(linkTier: "exact")) == "Classical", "exact tier")
    check(AyurvedaDisplayMath.tierLabel(.derived(linkTier: "near")) == "Classical", "near tier")
    check(AyurvedaDisplayMath.tierLabel(.derived(linkTier: "derived")) == "Derived", "derived tier")
    check(AyurvedaDisplayMath.tierLabel(.estimated) == "Estimated", "estimated tier")
    check(AyurvedaDisplayMath.tierLabel(.user) == "User", "user tier")

    check(AyurvedaDisplayMath.effectLabel(-2) == "strongly pacifies", "effect -2")
    check(AyurvedaDisplayMath.effectLabel(-1) == "pacifies", "effect -1")
    check(AyurvedaDisplayMath.effectLabel(0) == "neutral", "effect 0")
    check(AyurvedaDisplayMath.effectLabel(1) == "aggravates", "effect +1")
    check(AyurvedaDisplayMath.effectLabel(2) == "strongly aggravates", "effect +2")

    check(AyurvedaDisplayMath.valueString(-2) == "-2", "value -2")
    check(AyurvedaDisplayMath.valueString(-1) == "-1", "value -1")
    check(AyurvedaDisplayMath.valueString(0) == "0", "value 0")
    check(AyurvedaDisplayMath.valueString(1) == "+1", "value +1")
    check(AyurvedaDisplayMath.valueString(2) == "+2", "value +2")

    check(AyurvedaDisplayMath.barFraction(0) == 0.0, "bar 0")
    check(AyurvedaDisplayMath.barFraction(1) == 0.5, "bar +1")
    check(AyurvedaDisplayMath.barFraction(2) == 1.0, "bar +2")
    check(AyurvedaDisplayMath.barFraction(-2) == 1.0, "bar -2")

    guard total == 31, passed == total else {
      print("D8 MATH CHECK: \(passed)/\(total) FAIL")
      exit(1)
    }
    print("D8 MATH CHECK: \(passed)/\(total) PASS")
  }

  private static func checkPercentages(
    _ vata: Int,
    _ pitta: Int,
    _ kapha: Int,
    expected: (Int, Int, Int)
  ) {
    let actual = AyurvedaDisplayMath.percentages(vata: vata, pitta: pitta, kapha: kapha)
    check(
      actual.v == expected.0 && actual.p == expected.1 && actual.k == expected.2,
      "percentages \(vata),\(pitta),\(kapha)"
    )
  }

  private static func check(_ condition: Bool, _ label: String) {
    total += 1
    if condition {
      passed += 1
    } else {
      print("FAIL: \(label)")
    }
  }
}
