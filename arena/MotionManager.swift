//
//  MotionManager.swift
//  arena
//

import Foundation
import CoreMotion

protocol MotionManagerDelegate: AnyObject {
    func motionManagerDidDetectShot(_ manager: MotionManager)
}

/// Detects a jump-like impulse using user acceleration (debounced).
final class MotionManager {
    weak var delegate: MotionManagerDelegate?

    private let motion = CMMotionManager()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.name = "arena.motion"
        return q
    }()

    private var lastShotDate: Date?
    private let debounce = GameConstants.shotMotionDebounce

    /// Minimum peak |userAcceleration| (roughly in g) to count as a jump (gravity removed).
    private let jumpThreshold: Double = 1.85

    /// Raw accelerometer includes gravity; use a higher threshold to reduce false positives.
    private let rawAccelerometerThreshold: Double = 2.45

    private var usesRawAccelerometer = false

    func start() {
        if motion.isDeviceMotionAvailable {
            usesRawAccelerometer = false
            motion.deviceMotionUpdateInterval = 1.0 / 60.0
            motion.startDeviceMotionUpdates(to: queue) { [weak self] motionData, _ in
                guard let self, let motionData else { return }
                self.process(userAccel: motionData.userAcceleration)
            }
        } else if motion.isAccelerometerAvailable {
            usesRawAccelerometer = true
            motion.accelerometerUpdateInterval = 1.0 / 60.0
            motion.startAccelerometerUpdates(to: queue) { [weak self] data, _ in
                guard let self, let data else { return }
                self.process(userAccel: data.acceleration)
            }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        motion.stopAccelerometerUpdates()
    }

    private func process(userAccel: CMAcceleration) {
        let mag = sqrt(userAccel.x * userAccel.x + userAccel.y * userAccel.y + userAccel.z * userAccel.z)
        let threshold = usesRawAccelerometer ? rawAccelerometerThreshold : jumpThreshold
        guard mag >= threshold else { return }

        let now = Date()
        if let last = lastShotDate, now.timeIntervalSince(last) < debounce {
            return
        }
        lastShotDate = now

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.motionManagerDidDetectShot(self)
        }
    }
}
