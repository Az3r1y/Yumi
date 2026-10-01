import Foundation

/// What Yumi keeps from a forecast.
struct WeatherReport: Equatable, Sendable {
    struct Hour: Equatable, Sendable {
        var time: Date
        /// Chance of rain or snow during that hour, 0 to 100.
        var rainChance: Int
    }

    /// Degrees Celsius.
    var temperature: Double
    /// WMO weather code of the current conditions.
    var code: Int
    var hours: [Hour]
}

/// Open-Meteo (open-meteo.com): a free forecast API that needs no key and no account.
enum OpenMeteo {
    /// Coordinates are rounded to two decimals, about one kilometre: enough for a forecast,
    /// and the exact position never leaves the Mac.
    static func forecastURL(latitude: Double, longitude: Double) -> URL {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "hourly", value: "precipitation_probability"),
            URLQueryItem(name: "forecast_days", value: "2"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
        ]
        return components.url!
    }

    static func geocodingURL(city: String) -> URL {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: city),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: "fr"),
            URLQueryItem(name: "format", value: "json"),
        ]
        return components.url!
    }

    static func decodeForecast(_ data: Data) throws -> WeatherReport {
        struct Response: Decodable {
            struct Current: Decodable { let temperature_2m: Double; let weather_code: Int }
            struct Hourly: Decodable { let time: [Double]; let precipitation_probability: [Int?] }
            let current: Current
            let hourly: Hourly?
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        let hours = zip(response.hourly?.time ?? [], response.hourly?.precipitation_probability ?? []).map {
            WeatherReport.Hour(time: Date(timeIntervalSince1970: $0), rainChance: $1 ?? 0)
        }
        return WeatherReport(temperature: response.current.temperature_2m, code: response.current.weather_code, hours: hours)
    }

    /// Coordinates of the first place found, or nil when the city is unknown.
    static func decodePlace(_ data: Data) throws -> (latitude: Double, longitude: Double)? {
        struct Response: Decodable {
            struct Place: Decodable { let latitude: Double; let longitude: Double }
            let results: [Place]?
        }
        guard let place = try JSONDecoder().decode(Response.self, from: data).results?.first else { return nil }
        return (place.latitude, place.longitude)
    }
}

enum WeatherState: Equatable, Sendable {
    /// No place to ask the weather for; the associated value is the location permission.
    case needsLocation(PermissionState)
    case loading
    case unavailable
    case ready(WeatherReport)
}

enum WeatherSummary {
    /// From this chance on, rain is worth mentioning.
    private static let likely = 50

    /// The sky, as the end of "19° et …". Codes are the WMO ones Open-Meteo returns.
    static func sky(_ code: Int) -> String {
        switch code {
        case 0:          return "un grand soleil"
        case 1:          return "un ciel dégagé"
        case 2:          return "des éclaircies"
        case 3:          return "un ciel couvert"
        case 45, 48:     return "du brouillard"
        case 51...57:    return "de la bruine"
        case 61...67:    return "de la pluie"
        case 71...77:    return "de la neige"
        case 80...82:    return "des averses"
        case 85, 86:     return "des averses de neige"
        case 95...99:    return "de l'orage"
        default:         return "un ciel changeant"
        }
    }

    private static func isRain(_ code: Int) -> Bool {
        (51...67).contains(code) || (80...82).contains(code) || (95...99).contains(code)
    }

    private static func isSnow(_ code: Int) -> Bool {
        (71...77).contains(code) || code == 85 || code == 86
    }

    /// One piece of advice for the rest of the day.
    static func advice(_ report: WeatherReport, now: Date, calendar: Calendar = .current) -> String {
        if isRain(report.code) { return "Il pleut, prends un parapluie" }
        if isSnow(report.code) { return "Il neige, couvre-toi bien" }
        let later = report.hours.first {
            $0.time > now && calendar.isDate($0.time, inSameDayAs: now) && $0.rainChance >= likely
        }
        guard let later else { return "Pas de pluie prévue aujourd'hui" }
        return "Pluie vers \(FrenchText.spokenHour(later.time, calendar: calendar)), prends une veste"
    }

    static func snapshot(_ state: WeatherState, now: Date, calendar: Calendar = .current) -> ModuleSnapshot {
        var snapshot = ModuleSnapshot(id: "weather", name: "Météo", colorHex: "#7FD0FF", status: "…",
                                      title: "Je regarde le ciel", subtitle: "Un instant",
                                      primaryAction: "Détail", secondaryAction: nil)
        switch state {
        case .loading:
            break
        case .needsLocation(let permission):
            snapshot.status = "où ?"
            snapshot.title = "Météo sans adresse"
            if permission == .denied {
                snapshot.subtitle = "La position est refusée dans Réglages Système"
                snapshot.primaryAction = "Ouvrir les réglages"
            } else {
                snapshot.subtitle = "Autorise la position pour la météo d'ici"
                snapshot.primaryAction = "Autoriser"
            }
        case .unavailable:
            snapshot.status = "hors ligne"
            snapshot.title = "Météo indisponible"
            snapshot.subtitle = "Je réessaie dans un moment"
            snapshot.primaryAction = "Réessayer"
        case .ready(let report):
            let degrees = "\(Int(report.temperature.rounded()))°"
            snapshot.status = degrees
            snapshot.title = "\(degrees) et \(sky(report.code))"
            snapshot.subtitle = advice(report, now: now, calendar: calendar)
        }
        return snapshot
    }
}
