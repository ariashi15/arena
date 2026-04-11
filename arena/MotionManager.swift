//
//  MotionManager.swift
//  arena
//

import Foundation
import CoreMotion

protocol MotionManagerDelegate: AnyObject {
    func motionManagerDidDetectShot(_ manager: MotionManager)
    func motionManager(_ manager: MotionManager, didUpdateIsPhoneLevel isPhoneLevel: Bool)
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
    private var lastLevelState: Bool?
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
                self.process(userAccel: motionData.userAcceleration, gravity: motionData.gravity)
            }
        } else if motion.isAccelerometerAvailable {
            usesRawAccelerometer = true
            motion.accelerometerUpdateInterval = 1.0 / 60.0
            motion.startAccelerometerUpdates(to: queue) { [weak self] data, _ in
                guard let self, let data else { return }
                self.process(userAccel: data.acceleration, gravity: nil)
            }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        motion.stopAccelerometerUpdates()
        lastLevelState = nil
    }

    private func process(userAccel: CMAcceleration, gravity: CMAcceleration?) {
        let mag = sqrt(userAccel.x * userAccel.x + userAccel.y * userAccel.y + userAccel.z * userAccel.z)
        let threshold = usesRawAccelerometer ? rawAccelerometerThreshold : jumpThreshold
        let level = isPhoneLevel(userAccel: userAccel, gravity: gravity)

        if lastLevelState != level {
            lastLevelState = level
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.motionManager(self, didUpdateIsPhoneLevel: level)
            }
        }

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

    private func isPhoneLevel(userAccel: CMAcceleration, gravity: CMAcceleration?) -> Bool {
        if let gravity {
            let xyMagnitude = sqrt(gravity.x * gravity.x + gravity.y * gravity.y)
            return abs(gravity.z) >= 0.92 && xyMagnitude <= 0.35
        }

        let xyMagnitude = sqrt(userAccel.x * userAccel.x + userAccel.y * userAccel.y)
        return abs(userAccel.z) >= 0.92 && xyMagnitude <= 0.35
    }
}
