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
