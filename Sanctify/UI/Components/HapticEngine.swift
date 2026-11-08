import UIKit

final class HapticEngine {
    static let shared = HapticEngine()
    private let lightGen = UIImpactFeedbackGenerator(style: .light)
    private let mediumGen = UIImpactFeedbackGenerator(style: .medium)
    private let rigidGen = UIImpactFeedbackGenerator(style: .rigid)
    private init() {}
    func light() { lightGen.impactOccurred() }
    func snap() { rigidGen.impactOccurred(intensity: 0.85) }
    func medium() { mediumGen.impactOccurred() }
}
