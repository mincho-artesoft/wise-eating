enum ConstraintValue: Hashable, Sendable {
    case high, low
    case min(Double), max(Double)
    case strictMin(Double), strictMax(Double)
    case range(Double, Double)
    case notEqual(Double)
    
    // ✅ НОВИ КЕЙСОВЕ: За пълно сортиране (1-14 или 14-1) без скриване на резултати
    case lowest
    case highest
}
