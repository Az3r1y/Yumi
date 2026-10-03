import AppKit
import CoreLocation

/// The weather where the Mac is, from Open-Meteo. The place comes from Location Services once the
/// user allowed it, or from a city name stored under the `weatherCity` default.
/// No request is made before a place is known.
@MainActor
final class WeatherModule: NSObject, YumiModule {
    let id = "weather"

    /// UserDefaults key of a city typed by the user. It takes precedence over Location Services.
    static let cityKey = "weatherCity"
    private static let refreshInterval: TimeInterval = 30 * 60

    private let defaults: UserDefaults
    private var state: WeatherState = .loading
    private var onChange: (@MainActor () -> Void)?
    private var locationManager: CLLocationManager?
    private var refreshing: Task<Void, Never>?
    private var fetching: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var snapshot: ModuleSnapshot { WeatherSummary.snapshot(state, now: Date()) }

    /// The weather on screen, nil while there is none.
    var currentReport: WeatherReport? {
        guard onChange != nil, case .ready(let report) = state else { return nil }
        return report
    }

    private var access: PermissionState {
        switch locationManager?.authorizationStatus ?? .notDetermined {
        case .authorizedAlways, .authorized: return .granted
        case .notDetermined:                 return .notDetermined
        default:                             return .denied
        }
    }

    // MARK: Lifecycle

    func start(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        locationManager = manager
        refreshing = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.refresh()
                try? await Task.sleep(for: .seconds(Self.refreshInterval), tolerance: .seconds(60))
            }
        }
    }

    func stop() {
        onChange = nil
        refreshing?.cancel()
        refreshing = nil
        fetching?.cancel()
        fetching = nil
        locationManager?.delegate = nil
        locationManager = nil
        state = .loading
    }

    private func set(_ newState: WeatherState) {
        guard newState != state, onChange != nil else { return }
        state = newState
        onChange?()
    }

    // MARK: Actions

    func perform(_ action: ModuleAction) {
        guard action == .primary else { return }
        switch state {
        case .needsLocation(.notDetermined):
            locationManager?.requestWhenInUseAuthorization()
        case .needsLocation:
            NSWorkspace.shared.open(PrivacySettings.location)
        case .unavailable:
            refresh()
        case .loading, .ready:
            guard let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.weather") else { return }
            NSWorkspace.shared.openApplication(at: application, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        }
    }

    // MARK: Place, then forecast

    private func refresh() {
        let city = (defaults.string(forKey: Self.cityKey) ?? "").trimmingCharacters(in: .whitespaces)
        if !city.isEmpty {
            fetch { try await Self.coordinates(of: city) }
        } else if access == .granted {
            locationManager?.requestLocation()
        } else {
            set(.needsLocation(access))
        }
    }

    /// Finds the place, then loads its forecast. A previous request still running is dropped.
    private func fetch(place: @escaping @Sendable () async throws -> (latitude: Double, longitude: Double)?) {
        fetching?.cancel()
        fetching = Task { [weak self] in
            let result: WeatherState
            do {
                if let (latitude, longitude) = try await place() {
                    let url = OpenMeteo.forecastURL(latitude: latitude, longitude: longitude)
                    result = .ready(try OpenMeteo.decodeForecast(try await Self.load(url)))
                } else {
                    result = .unavailable
                }
            } catch {
                result = .unavailable
            }
            guard !Task.isCancelled, let self else { return }
            // A forecast already on screen is better than an error after one failed refresh.
            if result == .unavailable, case .ready = self.state { return }
            self.set(result)
        }
    }

    private nonisolated static func coordinates(of city: String) async throws -> (latitude: Double, longitude: Double)? {
        try OpenMeteo.decodePlace(try await load(OpenMeteo.geocodingURL(city: city)))
    }

    private nonisolated static func load(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 10))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }
}

extension WeatherModule: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.refresh() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        let latitude = coordinate.latitude, longitude = coordinate.longitude
        Task { @MainActor in self.fetch { (latitude, longitude) } }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if case .ready = self.state { return }
            self.set(.unavailable)
        }
    }
}
