import Foundation

public typealias CLLocationDegrees = Double
public typealias CLLocationDistance = Double
public typealias CLLocationAccuracy = Double
public typealias CLLocationDirection = Double
public typealias CLLocationSpeed = Double

public struct CLLocationCoordinate2D: Sendable, Equatable {
    public var latitude: CLLocationDegrees
    public var longitude: CLLocationDegrees

    public init() {
        self.latitude = 0
        self.longitude = 0
    }

    public init(latitude: CLLocationDegrees, longitude: CLLocationDegrees) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public let kCLLocationCoordinate2DInvalid = CLLocationCoordinate2D(
    latitude: .nan,
    longitude: .nan
)

public func CLLocationCoordinate2DIsValid(_ coordinate: CLLocationCoordinate2D) -> Bool {
    coordinate.latitude.isFinite &&
        coordinate.longitude.isFinite &&
        coordinate.latitude >= -90 &&
        coordinate.latitude <= 90 &&
        coordinate.longitude >= -180 &&
        coordinate.longitude <= 180
}

public enum CLAuthorizationStatus: Int32, Sendable {
    case notDetermined = 0
    case restricted = 1
    case denied = 2
    case authorizedAlways = 3
    case authorizedWhenInUse = 4
}

public enum CLActivityType: Int, Sendable {
    case other = 1
    case automotiveNavigation = 2
    case fitness = 3
    case otherNavigation = 4
    case airborne = 5
}

public struct CLError: Error, Sendable {
    public enum Code: Int, Sendable {
        case locationUnknown = 0
        case denied = 1
        case network = 2
        case headingFailure = 3
        case regionMonitoringDenied = 4
        case regionMonitoringFailure = 5
        case regionMonitoringSetupDelayed = 6
        case regionMonitoringResponseDelayed = 7
        case geocodeFoundNoResult = 8
        case geocodeFoundPartialResult = 9
        case geocodeCanceled = 10
        case deferredFailed = 11
        case deferredNotUpdatingLocation = 12
        case deferredAccuracyTooLow = 13
        case deferredDistanceFiltered = 14
        case deferredCanceled = 15
    }

    public let code: Code

    public init(_ code: Code) {
        self.code = code
    }
}

open class CLRegion: NSObject, @unchecked Sendable {
    public let identifier: String

    public init(identifier: String) {
        self.identifier = identifier
        super.init()
    }
}

open class CLCircularRegion: CLRegion, @unchecked Sendable {
    public let center: CLLocationCoordinate2D
    public let radius: CLLocationDistance

    public init(center: CLLocationCoordinate2D, radius: CLLocationDistance, identifier: String) {
        self.center = center
        self.radius = radius
        super.init(identifier: identifier)
    }

    open func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        CLLocationCoordinate2DIsValid(center) && CLLocationCoordinate2DIsValid(coordinate)
    }
}

open class CLLocation: NSObject, @unchecked Sendable {
    public let coordinate: CLLocationCoordinate2D
    public let altitude: CLLocationDistance
    public let horizontalAccuracy: CLLocationAccuracy
    public let verticalAccuracy: CLLocationAccuracy
    public let course: CLLocationDirection
    public let speed: CLLocationSpeed
    public let timestamp: Date

    public init(latitude: CLLocationDegrees, longitude: CLLocationDegrees) {
        self.coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        self.altitude = 0
        self.horizontalAccuracy = 0
        self.verticalAccuracy = 0
        self.course = -1
        self.speed = -1
        self.timestamp = Date()
        super.init()
    }

    public init(
        coordinate: CLLocationCoordinate2D,
        altitude: CLLocationDistance = 0,
        horizontalAccuracy: CLLocationAccuracy = 0,
        verticalAccuracy: CLLocationAccuracy = 0,
        course: CLLocationDirection = -1,
        speed: CLLocationSpeed = -1,
        timestamp: Date = Date()
    ) {
        self.coordinate = coordinate
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.course = course
        self.speed = speed
        self.timestamp = timestamp
        super.init()
    }

    open func distance(from location: CLLocation) -> CLLocationDistance {
        let latitudeDelta = coordinate.latitude - location.coordinate.latitude
        let longitudeDelta = coordinate.longitude - location.coordinate.longitude
        return sqrt(latitudeDelta * latitudeDelta + longitudeDelta * longitudeDelta) * 111_000
    }
}

open class CLPlacemark: NSObject, @unchecked Sendable {
    public let location: CLLocation?
    public let name: String?
    public let locality: String?
    public let country: String?
    public let isoCountryCode: String?

    public init(
        location: CLLocation? = nil,
        name: String? = nil,
        locality: String? = nil,
        country: String? = nil,
        isoCountryCode: String? = nil
    ) {
        self.location = location
        self.name = name
        self.locality = locality
        self.country = country
        self.isoCountryCode = isoCountryCode
        super.init()
    }
}

open class CLGeocoder: NSObject, @unchecked Sendable {
    private(set) public var isGeocoding: Bool = false

    open func cancelGeocode() {
        isGeocoding = false
    }

    open func geocodeAddressString(
        _ addressString: String,
        completionHandler: @escaping ([CLPlacemark]?, Error?) -> Void
    ) {
        _ = addressString
        completionHandler([], CLError(.geocodeFoundNoResult))
    }

    open func reverseGeocodeLocation(
        _ location: CLLocation,
        completionHandler: @escaping ([CLPlacemark]?, Error?) -> Void
    ) {
        completionHandler([CLPlacemark(location: location)], nil)
    }
}

public protocol CLLocationManagerDelegate: AnyObject {}

open class CLLocationManager: NSObject, @unchecked Sendable {
    public weak var delegate: CLLocationManagerDelegate?
    public var desiredAccuracy: CLLocationAccuracy = 0
    public var distanceFilter: CLLocationDistance = 0
    public var activityType: CLActivityType = .other
    public private(set) var location: CLLocation?

    public override init() {
        super.init()
    }

    open class func locationServicesEnabled() -> Bool { false }
    open class func authorizationStatus() -> CLAuthorizationStatus { .denied }

    open func requestWhenInUseAuthorization() {}
    open func requestAlwaysAuthorization() {}
    open func startUpdatingLocation() {}
    open func stopUpdatingLocation() {}
    open func requestLocation() {}
}
