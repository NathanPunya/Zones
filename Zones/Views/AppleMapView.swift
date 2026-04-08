import CoreLocation
import MapKit
import SwiftUI
import UIKit

/// MapKit basemap (Apple Maps) with the same overlays and camera behavior as `GoogleMapView`.
struct AppleMapView: UIViewRepresentable {
    @Binding var cameraTarget: CLLocationCoordinate2D?
    /// When true, uses hybrid (satellite imagery with roads, POIs, and labels). Plain `.satellite` hides most “blips”; hybrid matches the usual Maps app experience.
    var satelliteImagery: Bool = false
    var trafficEnabled: Bool
    var routePoints: [CLLocationCoordinate2D]
    var zonePolygons: [ZoneRecord]
    var suggestedRoutes: [[CLLocationCoordinate2D]]
    var routePanelBottomInset: CGFloat = 0

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.mapType = .standard
        mapView.pointOfInterestFilter = .includingAll
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.mapType = satelliteImagery ? .hybrid : .standard
        mapView.showsTraffic = trafficEnabled
        mapView.removeOverlays(mapView.overlays)

        for zone in zonePolygons where zone.polygon.count >= 3 {
            let coords = zone.polygon.map(\.coordinate)
            var closed = coords
            if let first = coords.first, let last = coords.last,
               first.latitude != last.latitude || first.longitude != last.longitude {
                closed.append(first)
            }
            let poly = MKPolygon(coordinates: &closed, count: closed.count)
            poly.title = "zone"
            mapView.addOverlay(poly)
        }

        for suggestion in suggestedRoutes where suggestion.count >= 3 {
            var coords = suggestion
            let line = MKPolyline(coordinates: &coords, count: coords.count)
            line.title = "suggested"
            mapView.addOverlay(line)
        }

        if routePoints.count >= 2 {
            var coords = routePoints
            let line = MKPolyline(coordinates: &coords, count: coords.count)
            line.title = "run"
            mapView.addOverlay(line)
        }

        let coordinator = context.coordinator

        // User-driven recenter wins over fitting the AI route for this update.
        if let target = cameraTarget {
            let region = MKCoordinateRegion(
                center: target,
                latitudinalMeters: 450,
                longitudinalMeters: 450
            )
            mapView.setVisibleMapRect(
                region.boundingMapRect,
                edgePadding: UIEdgeInsets(top: 0, left: 0, bottom: routePanelBottomInset, right: 0),
                animated: true
            )
            DispatchQueue.main.async {
                cameraTarget = nil
            }
        } else if let route = suggestedRoutes.first, route.count >= 3 {
            let sig = Self.routeSignature(route)
            // Refit when the route changes *or* when bottom overlay inset changes (same route, AI panel toggled).
            let fitKey = "\(sig)_\(Int(routePanelBottomInset.rounded()))"
            if fitKey != coordinator.lastRouteFitKey {
                coordinator.lastRouteFitKey = fitKey
                let rect = Self.mapRect(for: route)
                // Include full bottom UI in edge padding (unlike Google, MKMapView has no separate `padding` API).
                let margin: CGFloat = 56
                let padding = UIEdgeInsets(
                    top: 72,
                    left: 48,
                    bottom: routePanelBottomInset + margin,
                    right: 48
                )
                mapView.setVisibleMapRect(rect, edgePadding: padding, animated: true)
            }
        } else {
            coordinator.lastRouteFitKey = nil
        }
    }

    private static func routeSignature(_ route: [CLLocationCoordinate2D]) -> String {
        guard let first = route.first, let last = route.last else { return "" }
        let mid = route[route.count / 2]
        return "\(route.count)_\(first.latitude)_\(first.longitude)_\(mid.latitude)_\(mid.longitude)_\(last.latitude)_\(last.longitude)"
    }

    private static func mapRect(for coordinates: [CLLocationCoordinate2D]) -> MKMapRect {
        guard let first = coordinates.first else { return .null }
        var rect = MKMapRect(origin: MKMapPoint(first), size: MKMapSize(width: 0, height: 0))
        for c in coordinates.dropFirst() {
            let p = MKMapPoint(c)
            rect = rect.union(MKMapRect(origin: p, size: MKMapSize(width: 0, height: 0)))
        }
        return rect
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        /// Route signature plus bottom inset so we refit when the suggested-loop panel toggles without changing geometry.
        var lastRouteFitKey: String?

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polygon = overlay as? MKPolygon {
                let r = MKPolygonRenderer(polygon: polygon)
                r.strokeColor = UIColor.systemBlue.withAlphaComponent(0.9)
                r.fillColor = UIColor.systemBlue.withAlphaComponent(0.18)
                r.lineWidth = 1
                return r
            }
            if let polyline = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: polyline)
                r.lineWidth = polyline.title == "run" ? 5 : 3
                if polyline.title == "run" {
                    r.strokeColor = .systemOrange
                } else {
                    r.strokeColor = UIColor.systemGreen.withAlphaComponent(0.85)
                }
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

private extension MKCoordinateRegion {
    var boundingMapRect: MKMapRect {
        let corners = [
            CLLocationCoordinate2D(
                latitude: center.latitude + span.latitudeDelta / 2,
                longitude: center.longitude - span.longitudeDelta / 2
            ),
            CLLocationCoordinate2D(
                latitude: center.latitude + span.latitudeDelta / 2,
                longitude: center.longitude + span.longitudeDelta / 2
            ),
            CLLocationCoordinate2D(
                latitude: center.latitude - span.latitudeDelta / 2,
                longitude: center.longitude - span.longitudeDelta / 2
            ),
            CLLocationCoordinate2D(
                latitude: center.latitude - span.latitudeDelta / 2,
                longitude: center.longitude + span.longitudeDelta / 2
            )
        ]
        var rect = MKMapRect.null
        for c in corners {
            let p = MKMapPoint(c)
            rect = rect.union(MKMapRect(origin: p, size: MKMapSize(width: 0, height: 0)))
        }
        return rect
    }
}
