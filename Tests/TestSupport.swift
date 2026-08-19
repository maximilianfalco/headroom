import Foundation

/// Costs are sums of floating point products, so `5.000000000000001` is a correct answer.
/// Compare with a tolerance far tighter than any difference that could matter in a bill.
func isClose(_ actual: Double, _ expected: Double, tolerance: Double = 1e-9) -> Bool {
    abs(actual - expected) <= tolerance
}
