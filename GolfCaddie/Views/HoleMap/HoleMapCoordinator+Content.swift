import CoreLocation
import MapKit
import UIKit

/// What `HoleMap` draws: pins, flag, shot line, aim line, trail (live/hole)
/// or one line + badge per hole (course). Each piece is diffed so a SwiftUI
/// update only touches what changed.
extension HoleMapCoordinator {
    var placedShots: [Shot] {
        parent.shots.filter { $0.latitude != nil && $0.longitude != nil }
    }

    var shotCoordinates: [CLLocationCoordinate2D] {
        placedShots.compactMap(Self.coordinate(of:))
    }

    static func coordinate(of shot: Shot) -> CLLocationCoordinate2D? {
        guard let lat = shot.latitude, let lng = shot.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    static func same(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Bool {
        a.latitude == b.latitude && a.longitude == b.longitude
    }

    // MARK: Mode switch

    func enterMode(_ mode: HoleMapMode, on map: MKMapView) {
        map.showsUserLocation = mode.showsUser
        if mode == .course {
            removeHoleContent(from: map)
        } else {
            removeCourseContent(from: map)
        }
        if mode != .live {
            let aim = map.overlays.filter { $0 is HoleMapAimLine }
            if !aim.isEmpty { map.removeOverlays(aim) }
            lastAimUserCoord = nil
            lastAimGreen = nil
        }
    }

    private func removeHoleContent(from map: MKMapView) {
        map.removeAnnotations(map.annotations.filter { $0 is HoleMapShotAnnotation || $0 is HoleMapGreenAnnotation })
        map.removeOverlays(map.overlays.filter { $0 is HoleMapShotLine || $0 is HoleMapAimLine })
        MapTrailStyle.sync([], in: map, lastKey: &lastTrailKey)
        lastShotLineKey = nil
        lastAimUserCoord = nil
        lastAimGreen = nil
    }

    private func removeCourseContent(from map: MKMapView) {
        map.removeAnnotations(map.annotations.filter { $0 is HoleMapBadgeAnnotation })
        map.removeOverlays(map.overlays.filter { $0 is HoleMapCourseLine })
        map.cameraBoundary = nil
        lastCourseKey = nil
    }

    // MARK: Live / past hole

    func syncHoleContent(_ map: MKMapView) {
        syncShotPins(map)
        syncGreen(map)
        syncShotLine(map)
        syncAimLine(map)
        MapTrailStyle.sync(parent.trail, in: map, lastKey: &lastTrailKey)
        syncMapKitSelection(map)
    }

    private func syncShotPins(_ map: MKMapView) {
        let existing = map.annotations.compactMap { $0 as? HoleMapShotAnnotation }
        let placed = placedShots
        let ids = Set(placed.map(\.id))
        let stale = existing.filter { !ids.contains($0.shotID) }
        if !stale.isEmpty { map.removeAnnotations(stale) }
        var byID: [UUID: HoleMapShotAnnotation] = [:]
        for annotation in existing where ids.contains(annotation.shotID) {
            byID[annotation.shotID] = annotation
        }

        for shot in placed {
            guard let coordinate = Self.coordinate(of: shot) else { continue }
            let style = HoleMapPinStyle(number: shot.sequenceNumber, club: parent.clubLabels[shot.id],
                                        isSelected: parent.selectedShotID == shot.id,
                                        isDraggable: parent.mode.allowsPinDrag)
            guard let annotation = byID[shot.id] else {
                map.addAnnotation(HoleMapShotAnnotation(shot: shot, style: style, coordinate: coordinate))
                continue
            }
            annotation.shot = shot
            // Never move the pin under the player's finger.
            if draggingShotID != shot.id, !Self.same(annotation.coordinate, coordinate) {
                annotation.coordinate = coordinate
            }
            if annotation.style != style {
                annotation.style = style
                (map.view(for: annotation) as? HoleMapPinView)?.configure(style)
            }
        }
    }

    /// MapKit keeps a tapped pin selected; drop that when the screen's
    /// selection moved on, so the pin can be tapped again.
    private func syncMapKitSelection(_ map: MKMapView) {
        guard draggingShotID == nil else { return }
        for annotation in map.selectedAnnotations {
            guard let shot = annotation as? HoleMapShotAnnotation, shot.shotID != parent.selectedShotID else { continue }
            map.deselectAnnotation(shot, animated: false)
        }
    }

    private func syncGreen(_ map: MKMapView) {
        let existing = map.annotations.compactMap { $0 as? HoleMapGreenAnnotation }.first
        switch (existing, parent.green) {
        case let (annotation?, green?):
            if !Self.same(annotation.coordinate, green) { annotation.coordinate = green }
        case let (nil, green?):
            map.addAnnotation(HoleMapGreenAnnotation(coordinate: green))
        case let (annotation?, nil):
            map.removeAnnotation(annotation)
        case (nil, nil):
            break
        }
    }

    /// Shots joined in order; on a past hole the line runs on to the green.
    private func syncShotLine(_ map: MKMapView) {
        var coords = shotCoordinates
        if parent.mode == .hole, !coords.isEmpty, let green = parent.green { coords.append(green) }
        let key = coords.map { Self.key($0) }.joined(separator: ";")
        guard key != lastShotLineKey else { return }
        lastShotLineKey = key
        let old = map.overlays.filter { $0 is HoleMapShotLine }
        if !old.isEmpty { map.removeOverlays(old) }
        guard coords.count >= 2 else { return }
        map.addOverlay(HoleMapShotLine(coordinates: coords, count: coords.count), level: .aboveRoads)
    }

    /// Live hole: "you" → green, redrawn when the green moves or the player
    /// walks `walkReframeMeters` (keeps overlay churn bounded).
    func syncAimLine(_ map: MKMapView) {
        let existing = map.overlays.compactMap { $0 as? HoleMapAimLine }
        guard parent.mode == .live, let green = parent.green, let user = userCoordinate(map) else {
            if !existing.isEmpty { map.removeOverlays(existing) }
            lastAimUserCoord = nil
            lastAimGreen = nil
            return
        }
        let sameGreen = lastAimGreen.map { Self.same($0, green) } ?? false
        if sameGreen, !existing.isEmpty, let last = lastAimUserCoord,
           Distance.meters(from: last, to: user) < Self.walkReframeMeters {
            return
        }
        if !existing.isEmpty { map.removeOverlays(existing) }
        map.addOverlay(HoleMapAimLine(coordinates: [user, green], count: 2), level: .aboveRoads)
        lastAimUserCoord = user
        lastAimGreen = green
    }

    // MARK: Course

    func syncCourse(_ map: MKMapView) {
        let holes = parent.courseHoles
        let key = holes.map(\.syncKey).joined(separator: "#")
        guard key != lastCourseKey else { return }
        lastCourseKey = key
        map.removeOverlays(map.overlays.filter { $0 is HoleMapCourseLine })
        map.removeAnnotations(map.annotations.filter { $0 is HoleMapBadgeAnnotation })
        for hole in holes {
            let route = hole.route
            if route.count >= 2 {
                let line = HoleMapCourseLine(coordinates: route, count: route.count)
                line.holeNumber = hole.number
                line.isOverPar = hole.isOverPar
                map.addOverlay(line, level: .aboveRoads)
            }
            if let at = hole.badgeCoordinate {
                map.addAnnotation(HoleMapBadgeAnnotation(outline: hole, coordinate: at))
            }
        }
        // Keep panning near the course (generous: the framed centre is offset
        // towards the free side of the window).
        if let region = HoleFraming.courseRegion(holes, paddingFraction: 1) {
            map.cameraBoundary = MKMapView.CameraBoundary(coordinateRegion: region)
        } else {
            map.cameraBoundary = nil
        }
    }

    // MARK: Views and renderers

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if annotation is MKUserLocation {
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: HoleMapYouView.reuseID)
                ?? HoleMapYouView(annotation: annotation, reuseIdentifier: HoleMapYouView.reuseID)
            view.annotation = annotation
            return view
        }
        if let shot = annotation as? HoleMapShotAnnotation {
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: HoleMapPinView.reuseID) as? HoleMapPinView)
                ?? HoleMapPinView(annotation: annotation, reuseIdentifier: HoleMapPinView.reuseID)
            view.annotation = annotation
            view.configure(shot.style)
            return view
        }
        if let badge = annotation as? HoleMapBadgeAnnotation {
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: HoleMapBadgeView.reuseID)
                as? HoleMapBadgeView)
                ?? HoleMapBadgeView(annotation: annotation, reuseIdentifier: HoleMapBadgeView.reuseID)
            view.annotation = annotation
            view.configure(badge)
            return view
        }
        if annotation is HoleMapGreenAnnotation {
            let identifier = "HoleMapGreen"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            view.glyphImage = UIImage(systemName: "flag.fill")
            view.markerTintColor = HoleMapColors.flag
            view.displayPriority = .required
            view.animatesWhenAdded = false
            view.isDraggable = false
            view.canShowCallout = false
            view.accessibilityLabel = HoleMapAccessibility.greenLabel
            return view
        }
        return nil
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let aim = overlay as? HoleMapAimLine {
            let renderer = MKPolylineRenderer(polyline: aim)
            renderer.strokeColor = HoleMapColors.flag
            renderer.lineWidth = 2.5
            renderer.lineDashPattern = [8, 6]
            return renderer
        }
        if let course = overlay as? HoleMapCourseLine {
            let renderer = MKPolylineRenderer(polyline: course)
            renderer.strokeColor = course.isOverPar ? HoleMapColors.amber : HoleMapColors.cream
            renderer.lineWidth = 3
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }
        if let line = overlay as? HoleMapShotLine {
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.strokeColor = HoleMapColors.paper.withAlphaComponent(0.9)
            renderer.lineWidth = 2.5
            renderer.lineJoin = .round
            return renderer
        }
        if let trail = overlay as? TrailPolyline {
            return MapTrailStyle.renderer(for: trail)
        }
        return MKOverlayRenderer(overlay: overlay)
    }
}
