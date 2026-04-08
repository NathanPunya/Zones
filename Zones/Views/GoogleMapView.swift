import CoreLocation
import GoogleMaps
import SwiftUI
import UIKit

struct GoogleMapView: UIViewRepresentable {
    @Binding var cameraTarget: CLLocationCoordinate2D?
    var mapDisplayMode: MapDisplayMode
    var trafficEnabled: Bool
    var routePoints: [CLLocationCoordinate2D]
    var zonePolygons: [ZoneRecord]
    var suggestedRoutes: [[CLLocationCoordinate2D]]
    /// Insets the map’s “logical” frame so camera center / fit avoid the route-gen bottom panel.
    var routePanelBottomInset: CGFloat = 0

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> GMSMapView {
        let camera = GMSCameraPosition.camera(withLatitude: 37.3349, longitude: -122.0090, zoom: 14)
        let mapView = GMSMapView()
        mapView.camera = camera
        mapView.isMyLocationEnabled = true
        mapView.settings.compassButton = true
        // Custom recenter control in SwiftUI (top-trailing); SDK button is fixed bottom-trailing.
        mapView.settings.myLocationButton = false
        applyMapStyle(mapView)
        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        mapView.padding = UIEdgeInsets(top: 0, left: 0, bottom: routePanelBottomInset, right: 0)
        applyMapStyle(mapView)
        mapView.clear()

        if routePoints.count >= 2 {
            let path = GMSMutablePath()
            for p in routePoints {
                path.add(p)
            }
            let line = GMSPolyline(path: path)
            line.strokeColor = UIColor.systemOrange
            line.strokeWidth = 5
            line.map = mapView
        }

        for zone in zonePolygons {
            let path = GMSMutablePath()
            for p in zone.polygon {
                path.add(p.coordinate)
            }
            let poly = GMSPolygon(path: path)
            poly.strokeColor = UIColor.systemBlue.withAlphaComponent(0.9)
            poly.fillColor = UIColor.systemBlue.withAlphaComponent(0.18)
            poly.map = mapView
        }

        for suggestion in suggestedRoutes where suggestion.count >= 3 {
            let path = GMSMutablePath()
            for p in suggestion {
                path.add(p)
            }
            let line = GMSPolyline(path: path)
            line.strokeColor = UIColor.systemGreen.withAlphaComponent(0.85)
            line.strokeWidth = 3
            line.map = mapView
        }

        let coordinator = context.coordinator

        // User-driven recenter wins over fitting the AI route for this update.
        if let target = cameraTarget {
            let camera = GMSCameraPosition.camera(withTarget: target, zoom: 15)
            mapView.animate(to: camera)
            DispatchQueue.main.async {
                cameraTarget = nil
            }
        } else if let route = suggestedRoutes.first, route.count >= 3 {
            let sig = Self.routeSignature(route)
            let fitKey = "\(sig)_\(Int(routePanelBottomInset.rounded()))"
            if fitKey != coordinator.lastRouteFitKey {
                coordinator.lastRouteFitKey = fitKey
                let bounds = Self.coordinateBounds(for: route)
                let fitBottom: CGFloat = routePanelBottomInset > 0 ? 56 : 200
                let padding = UIEdgeInsets(top: 72, left: 48, bottom: fitBottom, right: 48)
                let update = GMSCameraUpdate.fit(bounds, with: padding)
                mapView.animate(with: update)
            }
        } else {
            coordinator.lastRouteFitKey = nil
        }
    }

    /// Stable id for “this polyline changed” so we only fit once per new suggestion.
    private static func routeSignature(_ route: [CLLocationCoordinate2D]) -> String {
        guard let first = route.first, let last = route.last else { return "" }
        let mid = route[route.count / 2]
        return "\(route.count)_\(first.latitude)_\(first.longitude)_\(mid.latitude)_\(mid.longitude)_\(last.latitude)_\(last.longitude)"
    }

    private static func coordinateBounds(for path: [CLLocationCoordinate2D]) -> GMSCoordinateBounds {
        var bounds = GMSCoordinateBounds(coordinate: path[0], coordinate: path[0])
        for p in path.dropFirst() {
            bounds = bounds.includingCoordinate(p)
        }
        return bounds
    }

    private func applyMapStyle(_ mapView: GMSMapView) {
        switch mapDisplayMode {
        case .standard:
            mapView.mapType = GMSMapViewType.normal
        case .satellite:
            mapView.mapType = GMSMapViewType.satellite
        case .appleMaps, .appleMapsSatellite:
            mapView.mapType = GMSMapViewType.normal
        }
        // Obj-C `trafficEnabled` (getter `isTrafficEnabled`); Swift exposes `isTrafficEnabled`.
        mapView.isTrafficEnabled = trafficEnabled
    }

    final class Coordinator {
        var lastRouteFitKey: String?
    }
}
