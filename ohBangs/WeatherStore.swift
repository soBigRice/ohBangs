import Combine
import CoreLocation
import Foundation
import MapKit

struct WeatherHour: Identifiable, Sendable {
    let id: String
    let time: String
    let symbolName: String
    let temperature: Int
    let isCurrent: Bool
}

struct WeatherDay: Identifiable, Sendable {
    let id: String
    let weekday: String
    let symbolName: String
    let high: Int
    let low: Int
}

struct WeatherSnapshot: Sendable {
    let city: String
    let temperature: Int
    let condition: String
    let feelsLike: Int
    let humidity: Int
    let airQuality: String
    let precipitationChance: Int
    let windSpeed: Int
    let hourly: [WeatherHour]
    let daily: [WeatherDay]

    static let placeholder = WeatherSnapshot(
        city: "定位中",
        temperature: 24,
        condition: "获取天气中",
        feelsLike: 24,
        humidity: 60,
        airQuality: "空气良",
        precipitationChance: 15,
        windSpeed: 8,
        hourly: [
            .init(id: "now", time: "现在", symbolName: "cloud.sun.fill", temperature: 24, isCurrent: true),
            .init(id: "13", time: "13:00", symbolName: "cloud.sun.fill", temperature: 25, isCurrent: false),
            .init(id: "15", time: "15:00", symbolName: "sun.max.fill", temperature: 25, isCurrent: false),
            .init(id: "17", time: "17:00", symbolName: "sun.max.fill", temperature: 23, isCurrent: false),
            .init(id: "19", time: "19:00", symbolName: "moon.stars.fill", temperature: 21, isCurrent: false)
        ],
        daily: [
            .init(id: "wed", weekday: "周三", symbolName: "cloud.sun.fill", high: 24, low: 18),
            .init(id: "thu", weekday: "周四", symbolName: "sun.max.fill", high: 26, low: 19),
            .init(id: "fri", weekday: "周五", symbolName: "cloud.rain.fill", high: 22, low: 17)
        ]
    )
}

@MainActor
final class WeatherStore: NSObject, ObservableObject {
    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var errorMessage: String?

    private let locationManager = CLLocationManager()
    private let weatherClient = OpenMeteoWeatherClient()
    private var refreshTask: Task<Void, Never>?
    private var fetchTask: Task<Void, Never>?
    private var didStart = false
    private var latestCoordinate: CLLocationCoordinate2D?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        locationManager.distanceFilter = 5_000
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        authorizationStatus = locationManager.authorizationStatus

        guard CLLocationManager.locationServicesEnabled() else {
            errorMessage = "系统定位服务不可用"
            return
        }

        requestAuthorizationIfNeeded()
        startRefreshLoop()
    }

    func refresh() {
        if let latestCoordinate {
            fetchWeather(for: latestCoordinate)
        } else {
            requestAuthorizationIfNeeded()
        }
    }

    private func requestAuthorizationIfNeeded() {
        authorizationStatus = locationManager.authorizationStatus

        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            errorMessage = nil
            locationManager.requestLocation()
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied:
            errorMessage = "未开启定位权限"
        case .restricted:
            errorMessage = "定位权限受限"
        @unknown default:
            errorMessage = "定位状态未知"
        }
    }

    private func startRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1_200))
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    private func fetchWeather(for coordinate: CLLocationCoordinate2D) {
        latestCoordinate = coordinate
        fetchTask?.cancel()

        fetchTask = Task { [weak self] in
            guard let self else { return }

            do {
                async let forecast = weatherClient.fetchForecast(latitude: coordinate.latitude, longitude: coordinate.longitude)
                async let airQuality = weatherClient.fetchAirQuality(latitude: coordinate.latitude, longitude: coordinate.longitude)
                async let city = reverseGeocodeCity(for: coordinate)

                let result = try await forecast
                let air = try? await airQuality
                let cityName = (try? await city) ?? snapshot?.city ?? "当前位置"
                let snapshot = makeSnapshot(
                    forecast: result,
                    airQualityIndex: air?.current.us_aqi,
                    city: cityName
                )

                self.snapshot = snapshot
                self.errorMessage = nil
            } catch {
                if self.snapshot == nil {
                    self.snapshot = .placeholder
                }
                self.errorMessage = "天气更新失败"
            }
        }
    }

    private func reverseGeocodeCity(for coordinate: CLLocationCoordinate2D) async throws -> String {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else {
            return "当前位置"
        }

        let item = try await request.mapItems.first
        let address = item?.addressRepresentations
        return address?.cityName
            ?? item?.name
            ?? "当前位置"
    }

    private func makeSnapshot(
        forecast: OpenMeteoWeatherClient.ForecastResponse,
        airQualityIndex: Double?,
        city: String
    ) -> WeatherSnapshot {
        let current = forecast.current
        let currentDate = forecast.date(from: current.time) ?? Date()
        let hourlyEntries = makeHourlyEntries(from: forecast, currentDate: currentDate)
        let dailyEntries = makeDailyEntries(from: forecast)
        let airQuality = airQualityLabel(for: airQualityIndex)
        let descriptor = weatherDescriptor(code: current.weather_code, isDay: current.is_day == 1)

        return WeatherSnapshot(
            city: city,
            temperature: Int(current.temperature_2m.rounded()),
            condition: descriptor.text,
            feelsLike: Int(current.apparent_temperature.rounded()),
            humidity: Int((current.relative_humidity_2m ?? 0).rounded()),
            airQuality: airQuality,
            precipitationChance: Int((current.precipitation_probability ?? 0).rounded()),
            windSpeed: Int(current.wind_speed_10m.rounded()),
            hourly: hourlyEntries,
            daily: dailyEntries
        )
    }

    private func makeHourlyEntries(
        from forecast: OpenMeteoWeatherClient.ForecastResponse,
        currentDate: Date
    ) -> [WeatherHour] {
        let times = forecast.hourly.time.compactMap(forecast.date(from:))
        let hourlyCount = min(times.count, min(forecast.hourly.temperature_2m.count, forecast.hourly.weather_code.count))
        guard hourlyCount > 0 else { return WeatherSnapshot.placeholder.hourly }

        let baseIndex = times.prefix(hourlyCount).enumerated().first(where: { $0.element >= currentDate })?.offset ?? 0
        var entries: [WeatherHour] = [
            WeatherHour(
                id: "current",
                time: "现在",
                symbolName: weatherDescriptor(code: forecast.current.weather_code, isDay: forecast.current.is_day == 1).symbolName,
                temperature: Int(forecast.current.temperature_2m.rounded()),
                isCurrent: true
            )
        ]

        var nextIndex = baseIndex + 1
        while entries.count < 5 && nextIndex < hourlyCount {
            let date = times[nextIndex]
            let descriptor = weatherDescriptor(
                code: forecast.hourly.weather_code[nextIndex],
                isDay: forecast.isDay(at: nextIndex)
            )
            entries.append(
                WeatherHour(
                    id: forecast.hourly.time[nextIndex],
                    time: forecast.hourFormatter.string(from: date),
                    symbolName: descriptor.symbolName,
                    temperature: Int(forecast.hourly.temperature_2m[nextIndex].rounded()),
                    isCurrent: false
                )
            )
            nextIndex += 2
        }

        nextIndex = baseIndex + 2
        while entries.count < 5 && nextIndex < hourlyCount {
            let date = times[nextIndex]
            let descriptor = weatherDescriptor(
                code: forecast.hourly.weather_code[nextIndex],
                isDay: forecast.isDay(at: nextIndex)
            )
            entries.append(
                WeatherHour(
                    id: forecast.hourly.time[nextIndex],
                    time: forecast.hourFormatter.string(from: date),
                    symbolName: descriptor.symbolName,
                    temperature: Int(forecast.hourly.temperature_2m[nextIndex].rounded()),
                    isCurrent: false
                )
            )
            nextIndex += 1
        }

        return Array(entries.prefix(5))
    }

    private func makeDailyEntries(from forecast: OpenMeteoWeatherClient.ForecastResponse) -> [WeatherDay] {
        let count = min(3, min(forecast.daily.time.count, min(forecast.daily.temperature_2m_max.count, min(forecast.daily.temperature_2m_min.count, forecast.daily.weather_code.count))))
        guard count > 0 else { return WeatherSnapshot.placeholder.daily }

        return (0..<count).map { index in
            let date = forecast.date(from: forecast.daily.time[index]) ?? Date()
            let descriptor = weatherDescriptor(code: forecast.daily.weather_code[index], isDay: true)

            return WeatherDay(
                id: forecast.daily.time[index],
                weekday: forecast.weekdayFormatter.string(from: date),
                symbolName: descriptor.symbolName,
                high: Int(forecast.daily.temperature_2m_max[index].rounded()),
                low: Int(forecast.daily.temperature_2m_min[index].rounded())
            )
        }
    }

    private func weatherDescriptor(code: Int, isDay: Bool) -> (text: String, symbolName: String) {
        switch code {
        case 0:
            return isDay ? ("晴朗", "sun.max.fill") : ("晴夜", "moon.stars.fill")
        case 1, 2:
            return isDay ? ("晴间多云", "cloud.sun.fill") : ("多云夜", "cloud.moon.fill")
        case 3:
            return ("阴天", "cloud.fill")
        case 45, 48:
            return ("有雾", "cloud.fog.fill")
        case 51, 53, 55:
            return ("毛毛雨", "cloud.drizzle.fill")
        case 56, 57:
            return ("冻毛毛雨", "cloud.sleet.fill")
        case 61, 63, 65:
            return ("降雨", "cloud.rain.fill")
        case 66, 67:
            return ("冻雨", "cloud.sleet.fill")
        case 71, 73, 75, 77:
            return ("降雪", "cloud.snow.fill")
        case 80, 81, 82:
            return ("阵雨", "cloud.heavyrain.fill")
        case 85, 86:
            return ("阵雪", "cloud.snow.fill")
        case 95:
            return ("雷暴", "cloud.bolt.rain.fill")
        case 96, 99:
            return ("冰雹雷暴", "cloud.bolt.rain.fill")
        default:
            return ("天气变化", "cloud.fill")
        }
    }

    private func airQualityLabel(for aqi: Double?) -> String {
        guard let aqi else { return "空气未知" }

        switch aqi {
        case ..<51:
            return "空气优"
        case ..<101:
            return "空气良"
        case ..<151:
            return "敏感人群注意"
        case ..<201:
            return "空气差"
        case ..<301:
            return "空气很差"
        default:
            return "空气污染严重"
        }
    }
}

extension WeatherStore: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            self?.authorizationStatus = manager.authorizationStatus
            self?.requestAuthorizationIfNeeded()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }

        Task { @MainActor [weak self] in
            self?.fetchWeather(for: coordinate)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.errorMessage = "定位失败"
        }
    }
}

private struct OpenMeteoWeatherClient {
    struct ForecastResponse: Decodable {
        struct Current: Decodable {
            let time: String
            let temperature_2m: Double
            let relative_humidity_2m: Double?
            let apparent_temperature: Double
            let precipitation_probability: Double?
            let weather_code: Int
            let wind_speed_10m: Double
            let is_day: Int
        }

        struct Hourly: Decodable {
            let time: [String]
            let temperature_2m: [Double]
            let weather_code: [Int]
            let is_day: [Int]?
        }

        struct Daily: Decodable {
            let time: [String]
            let weather_code: [Int]
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
        }

        let timezone: String
        let current: Current
        let hourly: Hourly
        let daily: Daily

        func date(from value: String) -> Date? {
            if value.count == 10 {
                return dayFormatter.date(from: value)
            }
            return hourParser.date(from: value)
        }

        func isDay(at index: Int) -> Bool {
            hourly.is_day?[safe: index] == 1
        }

        var hourFormatter: DateFormatter {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "HH:mm"
            formatter.timeZone = TimeZone(identifier: timezone) ?? .autoupdatingCurrent
            return formatter
        }

        var weekdayFormatter: DateFormatter {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "E"
            formatter.timeZone = TimeZone(identifier: timezone) ?? .autoupdatingCurrent
            return formatter
        }

        private var dayFormatter: DateFormatter {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(identifier: timezone) ?? .autoupdatingCurrent
            return formatter
        }

        private var hourParser: ISO8601DateFormatter {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
            formatter.timeZone = TimeZone(identifier: timezone) ?? .autoupdatingCurrent
            return formatter
        }
    }

    struct AirQualityResponse: Decodable {
        struct Current: Decodable {
            let us_aqi: Double?
        }

        let current: Current
    }

    func fetchForecast(latitude: Double, longitude: Double) async throws -> ForecastResponse {
        let queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "3"),
            URLQueryItem(name: "current", value: "temperature_2m,relative_humidity_2m,apparent_temperature,precipitation_probability,weather_code,wind_speed_10m,is_day"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min")
        ]

        return try await fetch(
            baseURL: "https://api.open-meteo.com/v1/forecast",
            queryItems: queryItems,
            responseType: ForecastResponse.self
        )
    }

    func fetchAirQuality(latitude: Double, longitude: Double) async throws -> AirQualityResponse {
        let queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "current", value: "us_aqi")
        ]

        return try await fetch(
            baseURL: "https://air-quality-api.open-meteo.com/v1/air-quality",
            queryItems: queryItems,
            responseType: AirQualityResponse.self
        )
    }

    private func fetch<Response: Decodable>(
        baseURL: String,
        queryItems: [URLQueryItem],
        responseType: Response.Type
    ) async throws -> Response {
        guard var components = URLComponents(string: baseURL) else {
            throw URLError(.badURL)
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(Response.self, from: data)
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
