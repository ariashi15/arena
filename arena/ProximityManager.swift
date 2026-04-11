//
//  ProximityManager.swift
//  arena
//

import Foundation
import CoreBluetooth

/// Estimates which known players are within shoot range using BLE advertisement RSSI.
final class ProximityManager: NSObject, ObservableObject {
    @Published private(set) var lastRSSIByPlayerId: [UUID: Int] = [:]
    @Published private(set) var bluetoothState: CBManagerState = .unknown

    private var central: CBCentralManager!
    private var peripheralManager: CBPeripheralManager!

    private let serviceUUID: CBUUID
    private var playerId: UUID

    private var isRunning = false

    override init() {
        self.serviceUUID = CBUUID(string: GameConstants.proximityServiceUUIDString)
        self.playerId = UUID()
        super.init()
        self.central = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: true])
        self.peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: nil)
    }

    func configure(playerId: UUID) {
        self.playerId = playerId
        if isRunning {
            stop()
            start()
        }
    }

    func start() {
        isRunning = true
        restartAdvertisingIfPossible()
        restartScanningIfPossible()
    }

    func stop() {
        isRunning = false
        peripheralManager.stopAdvertising()
        central.stopScan()
        DispatchQueue.main.async {
            self.lastRSSIByPlayerId.removeAll()
        }
    }

    func isPlayerInShootRange(_ id: UUID) -> Bool {
        guard id != playerId else { return false }
        guard let rssi = lastRSSIByPlayerId[id] else { return false }
        return rssi >= GameConstants.shootRSSIThreshold
    }

    // MARK: - Internals

    private func restartAdvertisingIfPossible() {
        guard isRunning else { return }
        guard peripheralManager.state == .poweredOn else { return }

        let uuidData = withUnsafeBytes(of: playerId.uuid) { Data($0) }
        var adv: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
            CBAdvertisementDataLocalNameKey: playerId.uuidString
        ]
        if uuidData.count == 16 {
            adv[CBAdvertisementDataServiceDataKey] = [serviceUUID: uuidData]
        }

        peripheralManager.startAdvertising(adv)
    }

    private func restartScanningIfPossible() {
        guard isRunning else { return }
        guard central.state == .poweredOn else { return }
        central.scanForPeripherals(withServices: [serviceUUID], options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: true
        ])
    }

    private func parsePlayerId(from peripheral: CBPeripheral, advertisementData: [String: Any]) -> UUID? {
        if let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String,
           let u = UUID(uuidString: name) {
            return u
        }
        if let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
           let data = serviceData[serviceUUID], data.count == 16 {
            return data.withUnsafeBytes { raw in
                UUID(uuid: raw.load(as: uuid_t.self))
            }
        }
        return nil
    }
}

extension ProximityManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async {
            self.bluetoothState = central.state
        }
        switch central.state {
        case .poweredOn:
            restartScanningIfPossible()
        default:
            central.stopScan()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let other = parsePlayerId(from: peripheral, advertisementData: advertisementData), other != playerId else { return }
        let value = RSSI.intValue
        guard value < 0, value != 127 else { return }

        DispatchQueue.main.async {
            self.lastRSSIByPlayerId[other] = value
        }
    }
}

extension ProximityManager: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            restartAdvertisingIfPossible()
        default:
            peripheral.stopAdvertising()
        }
    }
}
