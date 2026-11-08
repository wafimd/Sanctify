import UIKit

final class HapticEngine {
    static let shared = HapticEngine()
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private init() {}
    func light() { light.impactOccurred() }
    func snap() { rigid.impactOccurred(intensity: 0.85) }
    func medium() { medium.impactOccurred() }
}
