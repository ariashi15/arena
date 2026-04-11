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

        // Never use `CBAdvertisementDataServiceDataKey` here. On multiple iOS versions,
        // CoreBluetooth crashes inside `startAdvertising` with
        // `-[CBUUID UTF8String]` while serializing that dictionary (nested CBUUID keys).
        // Scan still filters by `CBAdvertisementDataServiceUUIDsKey`; identity uses local name
        // (and optional manufacturer payload below if the name is absent in the ad packet).
        var adv: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
            CBAdvertisementDataLocalNameKey: playerId.uuidString
        ]
        let uuidData = withUnsafeBytes(of: playerId.uuid) { Data($0) }
        if uuidData.count == 16 {
            adv[CBAdvertisementDataManufacturerDataKey] = GameConstants.proximityManufacturerData(prefixing: uuidData)
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
        if let data = serviceDataPayload(from: advertisementData[CBAdvertisementDataServiceDataKey]),
           data.count == 16 {
            return data.withUnsafeBytes { raw in
                UUID(uuid: raw.load(as: uuid_t.self))
            }
        }
        if let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            return GameConstants.playerIdFromProximityManufacturerData(mfg)
        }
        return nil
    }

    /// Advertisement service-data may appear as NSDictionary with CBUUID or String keys depending on OS / bridge.
    private func serviceDataPayload(from raw: Any?) -> Data? {
        guard let raw else { return nil }
        if let dict = raw as? [CBUUID: Data] {
            return dict[serviceUUID]
        }
        guard let ns = raw as? NSDictionary else { return nil }
        if let any = ns.object(forKey: serviceUUID) {
            if let d = any as? Data { return d }
            if let d = any as? NSData { return d as Data }
        }
        let target = GameConstants.proximityServiceUUIDString.lowercased()
        for (key, value) in ns {
            let data: Data?
            if let d = value as? Data {
                data = d
            } else if let d = value as? NSData {
                data = d as Data
            } else {
                data = nil
            }
            guard let data else { continue }
            if let u = key as? CBUUID, u == serviceUUID { return data }
            if let s = key as? String, s.lowercased() == target { return data }
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
