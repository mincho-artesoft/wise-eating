@available(iOS 26.0, *)
@inline(__always)
func replaceIfZero(_ lhs: inout AINutrient, with rhs: AINutrient) {
    // ако текущата стойност е 0, а новата е ненулева – взимаме новата
    // (по желание: може да добавиш проверка units да съвпадат)
    if lhs.value == 0, rhs.value != 0 {
        lhs = rhs
    }
}
