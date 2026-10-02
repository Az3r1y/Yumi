import Testing
import Foundation

@Suite struct OpenMeteoTests {
    // Shape of a real answer of api.open-meteo.com, shortened.
    private let forecast = Data("""
    {"latitude":48.86,"longitude":2.3599997,"utc_offset_seconds":7200,"timezone":"Europe/Paris",
     "current_units":{"time":"unixtime","interval":"seconds","temperature_2m":"°C","weather_code":"wmo code"},
     "current":{"time":1790861400,"interval":900,"temperature_2m":18.6,"weather_code":2},
     "hourly_units":{"time":"unixtime","precipitation_probability":"%"},
     "hourly":{"time":[1790805600,1790809200,1790812800],"precipitation_probability":[100,null,73]}}
    """.utf8)

    @Test func decodesAForecast() throws {
        let report = try OpenMeteo.decodeForecast(forecast)
        #expect(report.temperature == 18.6)
        #expect(report.code == 2)
        #expect(report.hours.count == 3)
        #expect(report.hours[0] == .init(time: Date(timeIntervalSince1970: 1790805600), rainChance: 100))
        #expect(report.hours[1].rainChance == 0)
    }

    @Test func refusesAnAnswerWithoutCurrentConditions() {
        #expect(throws: (any Error).self) { try OpenMeteo.decodeForecast(Data(#"{"error":true,"reason":"bad"}"#.utf8)) }
    }

    @Test func decodesAPlace() throws {
        let place = try OpenMeteo.decodePlace(Data(#"{"results":[{"id":3031582,"name":"Bordeaux","latitude":44.84124,"longitude":-0.58046}]}"#.utf8))
        #expect(place?.latitude == 44.84124)
        #expect(place?.longitude == -0.58046)
        #expect(try OpenMeteo.decodePlace(Data(#"{"generationtime_ms":0.5}"#.utf8)) == nil)
    }

    @Test func theForecastURLCarriesRoundedCoordinatesAndNoKey() {
        let url = OpenMeteo.forecastURL(latitude: 48.856614, longitude: 2.3522219).absoluteString
        #expect(url.hasPrefix("https://api.open-meteo.com/v1/forecast?"))
        #expect(url.contains("latitude=48.86&longitude=2.35&"))
        #expect(url.contains("timeformat=unixtime"))
        #expect(!url.lowercased().contains("key"))
    }

    @Test func theGeocodingURLEscapesTheCity() {
        #expect(OpenMeteo.geocodingURL(city: "Saint-Étienne du Rouvray").absoluteString.contains("name=Saint-%C3%89tienne%20du%20Rouvray"))
    }
}

@Suite struct WeatherSummaryTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }
    private func date(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }
    private func report(_ temperature: Double, _ code: Int, rain: [(Int, Int, Int)] = []) -> WeatherReport {
        WeatherReport(temperature: temperature, code: code,
                      hours: rain.map { .init(time: date($0.0, $0.1), rainChance: $0.2) })
    }

    @Test func aDryDayWithRainLater() {
        let state = WeatherState.ready(report(19.4, 2, rain: [(1, 12, 80), (1, 16, 20), (1, 18, 60), (1, 20, 90)]))
        let snapshot = WeatherSummary.snapshot(state, now: date(1, 14), calendar: calendar)
        #expect(snapshot.id == "weather")
        #expect(snapshot.status == "19°")
        #expect(snapshot.title == "19° et des éclaircies.")
        #expect(snapshot.subtitle == "Pluie vers 18 h. Prends une veste.")
        #expect(snapshot.primaryAction == "Détail")
        #expect(snapshot.secondaryAction == nil)
    }

    @Test func tomorrowsRainIsNotTodaysProblem() {
        let advice = WeatherSummary.advice(report(12, 3, rain: [(1, 20, 10), (2, 8, 95)]), now: date(1, 14), calendar: calendar)
        #expect(advice == "Pas de pluie en vue aujourd'hui.")
    }

    @Test func rainAndSnowRightNow() {
        #expect(WeatherSummary.advice(report(11, 63), now: date(1, 14), calendar: calendar) == "Il pleut. Prends un parapluie.")
        #expect(WeatherSummary.advice(report(-1, 73), now: date(1, 14), calendar: calendar) == "Il neige. Couvre-toi.")
        #expect(WeatherSummary.snapshot(.ready(report(-0.4, 73)), now: date(1, 14), calendar: calendar).title == "0° et de la neige.")
    }

    @Test func everyCodeHasWords() {
        for code in [0, 1, 2, 3, 45, 48, 51, 56, 61, 66, 71, 77, 80, 85, 95, 99, 1234] {
            #expect(!WeatherSummary.sky(code).isEmpty)
        }
        #expect(WeatherSummary.sky(95) == "de l'orage")
    }

    @Test func statesWithoutAForecast() {
        let ask = WeatherSummary.snapshot(.needsLocation(.notDetermined), now: date(1, 14), calendar: calendar)
        #expect(ask.primaryAction == "Autoriser")
        #expect(WeatherSummary.snapshot(.needsLocation(.denied), now: date(1, 14), calendar: calendar).primaryAction == "Ouvrir les réglages")
        #expect(WeatherSummary.snapshot(.unavailable, now: date(1, 14), calendar: calendar).primaryAction == "Réessayer")
        #expect(WeatherSummary.snapshot(.loading, now: date(1, 14), calendar: calendar).status == "…")
    }
}
