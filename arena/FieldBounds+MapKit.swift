//
//  FieldBounds+MapKit.swift
//  arena
//

import Foundation
import MapKit

extension FieldBounds {
    init(cornerA: CLLocationCoordinate2D, cornerB: CLLocationCoordinate2D) {
        minLatitude = min(cornerA.latitude, cornerB.latitude)
        maxLatitude = max(cornerA.latitude, cornerB.latitude)
        minLongitude = min(cornerA.longitude, cornerB.longitude)
        maxLongitude = max(cornerA.longitude, cornerB.longitude)
    }

    init(region: MKCoordinateRegion) {
        let c = region.center
        let latD = region.span.latitudeDelta
        let lonD = region.span.longitudeDelta
        minLatitude = c.latitude - latD / 2
        maxLatitude = c.latitude + latD / 2
        minLongitude = c.longitude - lonD / 2
        maxLongitude = c.longitude + lonD / 2
    }

    var coordinateRegion: MKCoordinateRegion {
        let minLat = min(minLatitude, maxLatitude)
        let maxLat = max(minLatitude, maxLatitude)
        let minLon = min(minLongitude, maxLongitude)
        let maxLon = max(minLongitude, maxLongitude)
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(maxLat - minLat, 0.0001),
            longitudeDelta: max(maxLon - minLon, 0.0001)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    /// Converts a GPS coordinate into field-local (0...1) coordinates.
    func normalizedPoint(for coordinate: CLLocationCoordinate2D) -> (x: Double, y: Double)? {
        let minLat = min(minLatitude, maxLatitude)
        let maxLat = max(minLatitude, maxLatitude)
        let minLon = min(minLongitude, maxLongitude)
        let maxLon = max(minLongitude, maxLongitude)
        let latSpan = maxLat - minLat
        let lonSpan = maxLon - minLon
        guard latSpan > 0, lonSpan > 0 else { return nil }
        let x = (coordinate.longitude - minLon) / lonSpan
        let y = (coordinate.latitude - minLat) / latSpan
        guard x >= 0, x <= 1, y >= 0, y <= 1 else { return nil }
        return (x, y)
    }

    /// Converts field-local (0...1) coordinates back to GPS coordinates.
    func coordinate(normalizedX: Double, normalizedY: Double) -> CLLocationCoordinate2D {
        let minLat = min(minLatitude, maxLatitude)
        let maxLat = max(minLatitude, maxLatitude)
        let minLon = min(minLongitude, maxLongitude)
        let maxLon = max(minLongitude, maxLongitude)
        let lat = minLat + (maxLat - minLat) * normalizedY
        let lon = minLon + (maxLon - minLon) * normalizedX
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Full play area outline (closed loop): SW → SE → NE → NW.
    var mapPolygonCoordinates: [CLLocationCoordinate2D] {
        let minLat = min(minLatitude, maxLatitude)
        let maxLat = max(minLatitude, maxLatitude)
        let minLon = min(minLongitude, maxLongitude)
        let maxLon = max(minLongitude, maxLongitude)
        let sw = CLLocationCoordinate2D(latitude: minLat, longitude: minLon)
        let se = CLLocationCoordinate2D(latitude: minLat, longitude: maxLon)
        let ne = CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon)
        let nw = CLLocationCoordinate2D(latitude: maxLat, longitude: minLon)
        return [sw, se, ne, nw, sw]
    }

    /// Team A / Team B split polygons for overlay.
    func teamAPolygonCoordinates(splitAxis: TeamSplitAxis) -> [CLLocationCoordinate2D] {
        let minLat = min(minLatitude, maxLatitude)
        let maxLat = max(minLatitude, maxLatitude)
        let minLon = min(minLongitude, maxLongitude)
        let maxLon = max(minLongitude, maxLongitude)
        switch splitAxis {
        case .leftRight:
            let midLon = (minLon + maxLon) / 2
            return [
                CLLocationCoordinate2D(latitude: minLat, longitude: minLon),
                CLLocationCoordinate2D(latitude: minLat, longitude: midLon),
                CLLocationCoordinate2D(latitude: maxLat, longitude: midLon),
                CLLocationCoordinate2D(latitude: maxLat, longitude: minLon),
                CLLocationCoordinate2D(latitude: minLat, longitude: minLon)
            ]
        case .topBottom:
            let midLat = (minLat + maxLat) / 2
            return [
                CLLocationCoordinate2D(latitude: midLat, longitude: minLon),
                CLLocationCoordinate2D(latitude: midLat, longitude: maxLon),
                CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon),
                CLLocationCoordinate2D(latitude: maxLat, longitude: minLon),
                CLLocationCoordinate2D(latitude: midLat, longitude: minLon)
            ]
        }
    }

    func teamBPolygonCoordinates(splitAxis: TeamSplitAxis) -> [CLLocationCoordinate2D] {
        let minLat = min(minLatitude, maxLatitude)
        let maxLat = max(minLatitude, maxLatitude)
        let minLon = min(minLongitude, maxLongitude)
        let maxLon = max(minLongitude, maxLongitude)
        switch splitAxis {
        case .leftRight:
            let midLon = (minLon + maxLon) / 2
            return [
                CLLocationCoordinate2D(latitude: minLat, longitude: midLon),
                CLLocationCoordinate2D(latitude: minLat, longitude: maxLon),
                CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon),
                CLLocationCoordinate2D(latitude: maxLat, longitude: midLon),
                CLLocationCoordinate2D(latitude: minLat, longitude: midLon)
            ]
        case .topBottom:
            let midLat = (minLat + maxLat) / 2
            return [
                CLLocationCoordinate2D(latitude: minLat, longitude: minLon),
                CLLocationCoordinate2D(latitude: minLat, longitude: maxLon),
                CLLocationCoordinate2D(latitude: midLat, longitude: maxLon),
                CLLocationCoordinate2D(latitude: midLat, longitude: minLon),
                CLLocationCoordinate2D(latitude: minLat, longitude: minLon)
            ]
        }
    }
}
