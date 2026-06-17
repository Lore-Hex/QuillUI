// SceneKit shim - deterministic action sampling.
import Foundation
import QuillFoundation

enum SCNActionRuntime {
    struct State {
        var elapsed: TimeInterval = 0
        let baseline: Baseline
    }

    struct Baseline {
        var position: SCNVector3
        var eulerAngles: SCNVector3
        var scale: SCNVector3
        var opacity: CGFloat

        init(node: SCNNode) {
            position = node.position
            eulerAngles = node.eulerAngles
            scale = node.scale
            opacity = node.opacity
        }

        init(position: SCNVector3, eulerAngles: SCNVector3, scale: SCNVector3, opacity: CGFloat) {
            self.position = position
            self.eulerAngles = eulerAngles
            self.scale = scale
            self.opacity = opacity
        }
    }

    struct Sample {
        var position: SCNVector3? = nil
        var eulerAngles: SCNVector3? = nil
        var scale: SCNVector3? = nil
        var opacity: CGFloat? = nil

        mutating func merge(_ other: Sample) {
            if let position = other.position { self.position = position }
            if let eulerAngles = other.eulerAngles { self.eulerAngles = eulerAngles }
            if let scale = other.scale { self.scale = scale }
            if let opacity = other.opacity { self.opacity = opacity }
        }

        func applying(to baseline: Baseline) -> Baseline {
            Baseline(
                position: position ?? baseline.position,
                eulerAngles: eulerAngles ?? baseline.eulerAngles,
                scale: scale ?? baseline.scale,
                opacity: opacity ?? baseline.opacity
            )
        }

        func apply(to node: SCNNode) {
            if let position { node.position = position }
            if let eulerAngles { node.eulerAngles = eulerAngles }
            if let scale { node.scale = scale }
            if let opacity { node.opacity = opacity }
        }
    }

    static func sample(_ action: SCNAction, elapsed: TimeInterval, baseline: Baseline) -> Sample {
        let localElapsed = localElapsed(for: action, after: elapsed)

        switch action.kind {
        case let .rotateBy(x, y, z):
            let t = timedProgress(for: action, at: localElapsed)
            return Sample(eulerAngles: baseline.eulerAngles.adding(x: x * t, y: y * t, z: z * t))

        case let .rotateTo(x, y, z):
            let t = timedProgress(for: action, at: localElapsed)
            return Sample(eulerAngles: baseline.eulerAngles.interpolated(to: SCNVector3(x, y, z), progress: t))

        case let .moveBy(x, y, z):
            let t = timedProgress(for: action, at: localElapsed)
            return Sample(position: baseline.position.adding(x: x * t, y: y * t, z: z * t))

        case let .scaleBy(factor):
            let t = timedProgress(for: action, at: localElapsed)
            let target = baseline.scale.scaled(by: factor)
            return Sample(scale: baseline.scale.interpolated(to: target, progress: t))

        case let .fadeOpacity(to):
            let t = timedProgress(for: action, at: localElapsed)
            return Sample(opacity: baseline.opacity + (to - baseline.opacity) * t)

        case .wait:
            return Sample()

        case let .repeatForever(child):
            return repeatedSample(child, elapsed: localElapsed, count: nil, baseline: baseline)

        case let .repeatCount(child, count):
            return repeatedSample(child, elapsed: localElapsed, count: max(0, count), baseline: baseline)

        case let .sequence(actions):
            return sequenceSample(actions, elapsed: localElapsed, baseline: baseline)

        case let .group(actions):
            return groupSample(actions, elapsed: localElapsed, baseline: baseline)
        }
    }

    static func isComplete(_ action: SCNAction, after elapsed: TimeInterval) -> Bool {
        switch action.kind {
        case .repeatForever:
            return false
        case let .repeatCount(_, count):
            return count <= 0 || localElapsed(for: action, after: elapsed) >= action.duration
        default:
            return localElapsed(for: action, after: elapsed) >= action.duration
        }
    }

    private static func repeatedSample(
        _ action: SCNAction,
        elapsed: TimeInterval,
        count: Int?,
        baseline: Baseline
    ) -> Sample {
        guard count != 0 else { return Sample() }
        guard action.duration > 0 else {
            return sample(action, elapsed: 0, baseline: baseline)
        }

        let totalDuration = count.map { action.duration * TimeInterval($0) }
        let clampedElapsed = totalDuration.map { min(max(0, elapsed), $0) } ?? max(0, elapsed)
        var completedCycles = Int(floor(clampedElapsed / action.duration))
        var cycleElapsed = clampedElapsed - TimeInterval(completedCycles) * action.duration

        if let count, completedCycles >= count {
            completedCycles = max(0, count - 1)
            cycleElapsed = action.duration
        }

        if let primitive = repeatedPrimitiveSample(
            action,
            completedCycles: completedCycles,
            cycleElapsed: cycleElapsed,
            baseline: baseline
        ) {
            return primitive
        }

        var runningBaseline = baseline
        var result = Sample()
        for _ in 0..<completedCycles {
            let cycle = sample(action, elapsed: action.duration, baseline: runningBaseline)
            result.merge(cycle)
            runningBaseline = cycle.applying(to: runningBaseline)
        }

        let partial = sample(action, elapsed: cycleElapsed, baseline: runningBaseline)
        result.merge(partial)
        return result
    }

    private static func repeatedPrimitiveSample(
        _ action: SCNAction,
        completedCycles: Int,
        cycleElapsed: TimeInterval,
        baseline: Baseline
    ) -> Sample? {
        let progress = timedProgress(for: action, at: cycleElapsed)
        let cycleCount = CGFloat(completedCycles) + progress

        switch action.kind {
        case let .rotateBy(x, y, z):
            return Sample(eulerAngles: baseline.eulerAngles.adding(
                x: x * cycleCount,
                y: y * cycleCount,
                z: z * cycleCount
            ))

        case let .moveBy(x, y, z):
            return Sample(position: baseline.position.adding(
                x: x * cycleCount,
                y: y * cycleCount,
                z: z * cycleCount
            ))

        case let .scaleBy(factor):
            let completedFactor = CGFloat(pow(Double(factor), Double(completedCycles)))
            let cycleStart = baseline.scale.scaled(by: completedFactor)
            let cycleEnd = cycleStart.scaled(by: factor)
            return Sample(scale: cycleStart.interpolated(to: cycleEnd, progress: progress))

        case .wait:
            return Sample()

        default:
            return nil
        }
    }

    private static func sequenceSample(
        _ actions: [SCNAction],
        elapsed: TimeInterval,
        baseline: Baseline
    ) -> Sample {
        var remaining = max(0, elapsed)
        var runningBaseline = baseline
        var result = Sample()

        for action in actions {
            let childDuration = max(0, action.duration)
            let childElapsed = min(remaining, childDuration)
            let childSample = sample(action, elapsed: childElapsed, baseline: runningBaseline)
            result.merge(childSample)
            runningBaseline = childSample.applying(to: runningBaseline)

            if remaining <= childDuration {
                break
            }
            remaining -= childDuration
        }

        return result
    }

    private static func groupSample(
        _ actions: [SCNAction],
        elapsed: TimeInterval,
        baseline: Baseline
    ) -> Sample {
        var result = Sample()
        for action in actions {
            result.merge(sample(action, elapsed: min(max(0, elapsed), max(0, action.duration)), baseline: baseline))
        }
        return result
    }

    private static func localElapsed(for action: SCNAction, after elapsed: TimeInterval) -> TimeInterval {
        elapsed * TimeInterval(max(0, action.speed))
    }

    private static func timedProgress(for action: SCNAction, at elapsed: TimeInterval) -> CGFloat {
        guard action.duration > 0 else { return 1 }
        let raw = CGFloat(min(1, max(0, elapsed / action.duration)))
        return evaluate(action.timingMode, at: raw)
    }

    private static func evaluate(_ timingMode: SCNActionTimingMode, at progress: CGFloat) -> CGFloat {
        switch timingMode {
        case .linear:
            return progress
        case .easeIn:
            return progress * progress
        case .easeOut:
            let remaining = 1 - progress
            return 1 - remaining * remaining
        case .easeInEaseOut:
            return progress * progress * (3 - 2 * progress)
        }
    }
}

private extension SCNVector3 {
    func adding(x: CGFloat, y: CGFloat, z: CGFloat) -> SCNVector3 {
        SCNVector3(self.x + x, self.y + y, self.z + z)
    }

    func scaled(by factor: CGFloat) -> SCNVector3 {
        SCNVector3(x * factor, y * factor, z * factor)
    }

    func interpolated(to other: SCNVector3, progress: CGFloat) -> SCNVector3 {
        SCNVector3(
            x + (other.x - x) * progress,
            y + (other.y - y) * progress,
            z + (other.z - z) * progress
        )
    }
}
