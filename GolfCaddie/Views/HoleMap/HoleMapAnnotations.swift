import CoreLocation
import MapKit
import UIKit

/// Fixed colours for map chrome: the map is satellite imagery in both
/// appearances, so these are the light-palette tokens (Palette.swift).
enum HoleMapColors {
    static let ink = UIColor(red: 0x1B / 255.0, green: 0x3A / 255.0, blue: 0x29 / 255.0, alpha: 1)
    static let paper = UIColor(red: 0xEF / 255.0, green: 0xE6 / 255.0, blue: 0xD2 / 255.0, alpha: 1)
    static let flag = UIColor(red: 0xC2 / 255.0, green: 0x4A / 255.0, blue: 0x2D / 255.0, alpha: 1)
    /// Course-map line for a hole at or under par.
    static let cream = UIColor(red: 0xF4 / 255.0, green: 0xEB / 255.0, blue: 0xD6 / 255.0, alpha: 1)
    /// Course-map line for a hole over par.
    static let amber = UIColor(red: 0xE8 / 255.0, green: 0xA3 / 255.0, blue: 0x5A / 255.0, alpha: 1)
}

// MARK: - Overlays

/// Shots joined in playing order (plus the green on a past hole).
final class HoleMapShotLine: MKPolyline {}
/// Live hole: "you" → green, dashed flag orange.
final class HoleMapAimLine: MKPolyline {}
/// Course mode: one hole's tee → shots → green.
final class HoleMapCourseLine: MKPolyline {
    var holeNumber = 0
    var isOverPar = false
}

// MARK: - Annotations

/// How a shot pin looks; a change reconfigures the view in place.
struct HoleMapPinStyle: Equatable {
    var number: Int
    var club: String?
    var isSelected: Bool
    var isDraggable: Bool
}

/// KVO-compliant coordinate so MapKit's drag machinery can move it.
final class HoleMapShotAnnotation: NSObject, MKAnnotation {
    /// Latest copy of the shot (the snapper needs its hole).
    var shot: Shot
    var style: HoleMapPinStyle
    @objc dynamic var coordinate: CLLocationCoordinate2D

    var shotID: UUID { shot.id }

    init(shot: Shot, style: HoleMapPinStyle, coordinate: CLLocationCoordinate2D) {
        self.shot = shot
        self.style = style
        self.coordinate = coordinate
        super.init()
    }
}

final class HoleMapGreenAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        super.init()
    }
}

final class HoleMapBadgeAnnotation: NSObject, MKAnnotation {
    let holeNumber: Int
    let score: Int?
    let isOverPar: Bool
    let coordinate: CLLocationCoordinate2D

    init(outline: CourseHoleOutline, coordinate: CLLocationCoordinate2D) {
        self.holeNumber = outline.number
        self.score = outline.score
        self.isOverPar = outline.isOverPar
        self.coordinate = coordinate
        super.init()
    }
}

// MARK: - Views

/// Shot pin: 28 pt numbered ink dot (flag orange + halo when selected) inside
/// a 44 pt tap target, club tag underneath — the canvas pin.
final class HoleMapPinView: MKAnnotationView {
    static let reuseID = "HoleMapPin"
    private static let target: CGFloat = 44
    private static let dotSize: CGFloat = 28
    private static let haloSize: CGFloat = 40

    private let halo = UIView()
    private let dot = UIView()
    private let numberLabel = UILabel()
    private let clubTag = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        let side = Self.target
        frame = CGRect(x: 0, y: 0, width: side, height: side)
        backgroundColor = .clear
        clipsToBounds = false
        displayPriority = .required
        canShowCallout = false

        halo.frame = CGRect(x: (side - Self.haloSize) / 2, y: (side - Self.haloSize) / 2,
                            width: Self.haloSize, height: Self.haloSize)
        halo.layer.cornerRadius = Self.haloSize / 2
        halo.backgroundColor = HoleMapColors.flag.withAlphaComponent(0.28)
        halo.isUserInteractionEnabled = false
        addSubview(halo)

        dot.frame = CGRect(x: (side - Self.dotSize) / 2, y: (side - Self.dotSize) / 2,
                           width: Self.dotSize, height: Self.dotSize)
        dot.layer.cornerRadius = Self.dotSize / 2
        dot.layer.borderWidth = 1.5
        dot.layer.borderColor = HoleMapColors.paper.cgColor
        dot.isUserInteractionEnabled = false
        addSubview(dot)

        numberLabel.frame = dot.bounds
        numberLabel.textAlignment = .center
        numberLabel.font = .monospacedSystemFont(ofSize: 12, weight: .bold)
        numberLabel.textColor = HoleMapColors.paper
        dot.addSubview(numberLabel)

        clubTag.font = .monospacedSystemFont(ofSize: 10, weight: .bold)
        clubTag.backgroundColor = HoleMapColors.paper.withAlphaComponent(0.92)
        clubTag.textAlignment = .center
        addSubview(clubTag)

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 2
        layer.shadowOffset = CGSize(width: 0, height: 1)

        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ style: HoleMapPinStyle) {
        halo.isHidden = !style.isSelected
        dot.backgroundColor = style.isSelected ? HoleMapColors.flag : HoleMapColors.ink
        numberLabel.text = "\(style.number)"

        let club = style.club?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        clubTag.isHidden = club.isEmpty
        clubTag.text = club
        clubTag.textColor = style.isSelected ? HoleMapColors.flag : HoleMapColors.ink
        let fitted = clubTag.sizeThatFits(CGSize(width: 120, height: 20))
        let width = fitted.width + 10
        clubTag.frame = CGRect(x: (Self.target - width) / 2, y: 40, width: width, height: fitted.height + 2)

        isDraggable = style.isDraggable
        accessibilityLabel = HoleMapAccessibility.shotLabel(number: style.number, club: style.club,
                                                           selected: style.isSelected)
        accessibilityHint = style.isDraggable ? HoleMapAccessibility.shotHintDraggable : HoleMapAccessibility.shotHint
        accessibilityTraits = style.isSelected ? [.button, .selected] : .button
    }
}

/// "You": paper dot with a thick flag-orange ring and a soft halo.
final class HoleMapYouView: MKAnnotationView {
    static let reuseID = "HoleMapYou"

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 36, height: 36)
        backgroundColor = .clear
        let halo = UIView(frame: bounds)
        halo.layer.cornerRadius = 18
        halo.backgroundColor = HoleMapColors.flag.withAlphaComponent(0.18)
        halo.isUserInteractionEnabled = false
        addSubview(halo)
        let ring = UIView(frame: CGRect(x: 6, y: 6, width: 24, height: 24))
        ring.layer.cornerRadius = 12
        ring.layer.borderWidth = 5
        ring.layer.borderColor = HoleMapColors.flag.cgColor
        ring.backgroundColor = HoleMapColors.paper
        ring.isUserInteractionEnabled = false
        addSubview(ring)
        canShowCallout = false
        isAccessibilityElement = true
        accessibilityLabel = HoleMapAccessibility.youLabel
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Course mode: hole number in a paper circle, score beside it.
final class HoleMapBadgeView: MKAnnotationView {
    static let reuseID = "HoleMapBadge"
    private let numberLabel = UILabel()
    private let scoreLabel = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        clipsToBounds = false
        displayPriority = .required
        canShowCallout = false

        numberLabel.textAlignment = .center
        numberLabel.font = .monospacedSystemFont(ofSize: 11, weight: .bold)
        numberLabel.textColor = HoleMapColors.ink
        numberLabel.backgroundColor = HoleMapColors.paper
        numberLabel.layer.cornerRadius = 12
        numberLabel.layer.borderWidth = 1.5
        numberLabel.layer.borderColor = HoleMapColors.ink.cgColor
        numberLabel.layer.masksToBounds = true
        addSubview(numberLabel)

        scoreLabel.font = UIFont(name: "Georgia-Bold", size: 12) ?? .boldSystemFont(ofSize: 12)
        scoreLabel.layer.shadowColor = HoleMapColors.ink.cgColor
        scoreLabel.layer.shadowOpacity = 1
        scoreLabel.layer.shadowRadius = 1
        scoreLabel.layer.shadowOffset = .zero
        addSubview(scoreLabel)

        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ badge: HoleMapBadgeAnnotation) {
        numberLabel.text = "\(badge.holeNumber)"
        scoreLabel.text = badge.score.map { String($0) } ?? ""
        scoreLabel.textColor = badge.isOverPar ? HoleMapColors.amber : HoleMapColors.cream
        let scoreWidth = badge.score == nil ? 0 : scoreLabel.sizeThatFits(CGSize(width: 40, height: 20)).width + 2
        // 44 pt tap target; the number circle centred on the hole's start.
        let width = max(44, 24 + scoreWidth * 2)
        frame = CGRect(x: 0, y: 0, width: width, height: 44)
        numberLabel.frame = CGRect(x: (width - 24) / 2, y: 10, width: 24, height: 24)
        scoreLabel.frame = CGRect(x: numberLabel.frame.maxX + 2, y: 10, width: max(0, scoreWidth - 2), height: 24)
        accessibilityLabel = HoleMapAccessibility.holeBadgeLabel(number: badge.holeNumber, score: badge.score)
        accessibilityIdentifier = CourseMapAccessibilityID.badge(badge.holeNumber)
    }
}
