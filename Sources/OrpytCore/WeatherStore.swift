import AppKit
import Combine
import CoreLocation
import EventKit
import Security
import ServiceManagement
import SwiftUI
import WeatherKit

@MainActor
public final class WeatherStore: ObservableObject {
    public static let shared = WeatherStore()

    @Published private(set) var primaryState: WeatherState = .idle
    @Published private(set) var secondaryState: WeatherState = .idle
    @Published private(set) var attribution: WeatherAttributionSnapshot?

    private let weatherService = WeatherService()
    private let urlSession = URLSession(configuration: .ephemeral)
    private let canUseWeatherKit = WeatherKitAvailability.isEnabledForCurrentProcess
    private var refreshTask: Task<Void, Never>?
    private var geocodeCache: [String: CLLocation] = [:]
    private static let sharedTemperatureFormatter: MeasurementFormatter = {
        let f = MeasurementFormatter()
        f.unitOptions = .providedUnit
        f.numberFormatter.maximumFractionDigits = 0
        return f
    }()

    public func refresh(for settings: ClockSettingsStore) {
        let configuration = WeatherRefreshConfiguration(settings: settings)
        refreshTask?.cancel()

        guard configuration.enableWeather else {
            disable()
            return
        }

        if configuration.showPrimaryClock {
            primaryState = .loading
        } else {
            primaryState = .idle
        }

        if configuration.showSecondaryClock {
            secondaryState = .loading
        } else {
            secondaryState = .idle
        }

        refreshTask = Task {
            let primaryResult = configuration.showPrimaryClock
                ? await fetchWeather(
                    query: configuration.primaryQuery,
                    fallbackTimeZoneID: configuration.primaryTimeZoneID
                )
                : .idle

            let secondaryResult = configuration.showSecondaryClock
                ? await fetchWeather(
                    query: configuration.secondaryQuery,
                    fallbackTimeZoneID: configuration.secondaryTimeZoneID
                )
                : .idle

            let attribution = canUseWeatherKit ? await fetchAttribution() : nil

            guard !Task.isCancelled else { return }

            await MainActor.run {
                self.primaryState = primaryResult
                self.secondaryState = secondaryResult
                self.attribution = attribution
            }
        }
    }

    public func disable() {
        refreshTask?.cancel()
        primaryState = .idle
        secondaryState = .idle
        attribution = nil
    }

    public func state(for slot: ClockSlot) -> WeatherState {
        switch slot {
        case .primary:
            return primaryState
        case .secondary:
            return secondaryState
        }
    }

    public func swapClockStates() {
        let originalPrimary = primaryState
        primaryState = secondaryState
        secondaryState = originalPrimary
    }

    private func fetchWeather(query: String, fallbackTimeZoneID: String) async -> WeatherState {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedFallbackCityName = TimeZoneCatalog.option(for: fallbackTimeZoneID)?.cityName ?? fallbackCityName(for: fallbackTimeZoneID)

        if trimmedQuery.isEmpty,
           let representativeLocation = TimeZoneCatalog.representativeLocation(for: fallbackTimeZoneID) {
            return await fetchCurrentWeather(
                at: representativeLocation,
                resolvedLocationName: resolvedFallbackCityName
            )
        }

        let resolvedQuery = trimmedQuery.isEmpty
            ? TimeZoneCatalog.weatherLookupName(for: fallbackTimeZoneID)
            : trimmedQuery
        let cacheKey = resolvedQuery.lowercased()

        if let cachedLocation = await MainActor.run(body: { geocodeCache[cacheKey] }) {
            return await fetchCurrentWeather(at: cachedLocation, resolvedLocationName: resolvedQuery)
        }

        if let openMeteoLocation = try? await fetchOpenMeteoLocation(for: resolvedQuery) {
            await MainActor.run { geocodeCache[cacheKey] = openMeteoLocation.location }
            return await fetchCurrentWeather(
                at: openMeteoLocation.location,
                resolvedLocationName: openMeteoLocation.displayName
            )
        }

        do {
            let geocoder = CLGeocoder()
            let placemarks = try await geocoder.geocodeAddressString(resolvedQuery)

            guard let placemark = placemarks.first, let location = placemark.location else {
                return .failed("Location not found")
            }

            await MainActor.run { geocodeCache[cacheKey] = location }

            return await fetchCurrentWeather(
                at: location,
                resolvedLocationName: placemark.locality ?? placemark.name ?? resolvedQuery
            )
        } catch {
            if trimmedQuery.isEmpty,
               let representativeLocation = TimeZoneCatalog.representativeLocation(for: fallbackTimeZoneID) {
                return await fetchCurrentWeather(
                    at: representativeLocation,
                    resolvedLocationName: resolvedFallbackCityName
                )
            }
            return .failed(userFacingMessage(for: error))
        }
    }

    private func fetchCurrentWeather(at location: CLLocation, resolvedLocationName: String) async -> WeatherState {
        if !canUseWeatherKit, let fallbackSnapshot = try? await fetchOpenMeteoWeather(at: location, resolvedLocationName: resolvedLocationName) {
            return .loaded(fallbackSnapshot)
        }

        do {
            let currentWeather = try await weatherService.weather(for: location, including: .current)

            let temperatureFormatter = WeatherStore.sharedTemperatureFormatter

            return .loaded(
                WeatherSnapshot(
                    symbolName: currentWeather.symbolName,
                    temperatureText: temperatureFormatter.string(from: currentWeather.temperature),
                    conditionText: currentWeather.condition.description,
                    feelsLikeText: temperatureFormatter.string(from: currentWeather.apparentTemperature),
                    resolvedLocationName: resolvedLocationName
                )
            )
        } catch {
            if let fallbackSnapshot = try? await fetchOpenMeteoWeather(at: location, resolvedLocationName: resolvedLocationName) {
                return .loaded(fallbackSnapshot)
            }

            return .failed(userFacingMessage(for: error))
        }
    }

    private func fetchOpenMeteoLocation(for query: String) async throws -> OpenMeteoGeocodeResult {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search") ?? URLComponents()
        components.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json"),
        ]

        guard let url = components.url else {
            throw NSError(domain: "OpenMeteoGeocoding", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        let (data, _) = try await urlSession.data(from: url)
        let response = try JSONDecoder().decode(OpenMeteoGeocodeResponse.self, from: data)

        guard let result = response.results?.first else {
            throw NSError(domain: "OpenMeteoGeocoding", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "Location not found",
            ])
        }

        return result
    }

    private func fetchOpenMeteoWeather(at location: CLLocation, resolvedLocationName: String) async throws -> WeatherSnapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast") ?? URLComponents()
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(location.coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,is_day,weather_code"),
            URLQueryItem(name: "temperature_unit", value: "celsius"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "1"),
        ]

        guard let url = components.url else {
            throw NSError(domain: "OpenMeteoForecast", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        let (data, _) = try await urlSession.data(from: url)
        let response = try JSONDecoder().decode(OpenMeteoForecastResponse.self, from: data)

        guard let current = response.current,
              let temperature = current.temperature2m,
              let apparentTemperature = current.apparentTemperature,
              let weatherCode = current.weatherCode else {
            throw NSError(domain: "OpenMeteoForecast", code: 500, userInfo: [
                NSLocalizedDescriptionKey: "Weather unavailable",
            ])
        }

        let isDay = (current.isDay ?? 1) == 1
        let condition = OpenMeteoWeatherCatalog.condition(for: weatherCode, isDay: isDay)

        return WeatherSnapshot(
            symbolName: condition.symbolName,
            temperatureText: String(format: "%.0f°C", temperature),
            conditionText: condition.description,
            feelsLikeText: String(format: "%.0f°C", apparentTemperature),
            resolvedLocationName: resolvedLocationName
        )
    }

    private func fetchAttribution() async -> WeatherAttributionSnapshot? {
        do {
            let attribution = try await weatherService.attribution
            return WeatherAttributionSnapshot(
                combinedMarkLightURL: attribution.combinedMarkLightURL,
                combinedMarkDarkURL: attribution.combinedMarkDarkURL,
                legalPageURL: attribution.legalPageURL
            )
        } catch {
            return nil
        }
    }

    private func fallbackCityName(for timeZoneID: String) -> String {
        timeZoneID.split(separator: "/").last?
            .replacingOccurrences(of: "_", with: " ") ?? timeZoneID
    }

    private func userFacingMessage(for error: Error) -> String {
        let nsError = error as NSError

        if nsError.domain == kCLErrorDomain {
            return "Location lookup failed"
        }

        if nsError.domain.localizedCaseInsensitiveContains("weather") {
            return "Weather unavailable right now"
        }

        let message = nsError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.isEmpty {
            return "Weather unavailable"
        }

        return message
    }
}

public enum WeatherKitAvailability {
    public static let isEnabledForCurrentProcess: Bool = {
        guard let task = SecTaskCreateFromSelf(nil) else {
            return false
        }

        let entitlement = "com.apple.developer.weatherkit" as CFString
        guard let rawValue = SecTaskCopyValueForEntitlement(task, entitlement, nil) else {
            return false
        }

        if CFGetTypeID(rawValue) == CFBooleanGetTypeID() {
            return CFBooleanGetValue((rawValue as! CFBoolean))
        }

        return false
    }()
}

public struct OpenMeteoGeocodeResponse: Decodable {
    public let results: [OpenMeteoGeocodeResult]?
}

public struct OpenMeteoGeocodeResult: Decodable {
    public let name: String
    public let latitude: Double
    public let longitude: Double
    public let admin1: String?
    public let country: String?

    public var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    public var displayName: String {
        [name, admin1, country]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

public struct OpenMeteoForecastResponse: Decodable {
    public let current: OpenMeteoCurrentWeather?
}

public struct OpenMeteoCurrentWeather: Decodable {
    public let temperature2m: Double?
    public let apparentTemperature: Double?
    public let isDay: Int?
    public let weatherCode: Int?

    enum CodingKeys: String, CodingKey {
        case temperature2m = "temperature_2m"
        case apparentTemperature = "apparent_temperature"
        case isDay = "is_day"
        case weatherCode = "weather_code"
    }
}

public enum OpenMeteoWeatherCatalog {
    public static func condition(for code: Int, isDay: Bool) -> (description: String, symbolName: String) {
        switch code {
        case 0:
            return (isDay ? "Clear" : "Clear", isDay ? "sun.max.fill" : "moon.stars.fill")
        case 1, 2:
            return (isDay ? "Partly cloudy" : "Partly cloudy", isDay ? "cloud.sun.fill" : "cloud.moon.fill")
        case 3:
            return ("Overcast", "cloud.fill")
        case 45, 48:
            return ("Fog", "cloud.fog.fill")
        case 51, 53, 55, 56, 57:
            return ("Drizzle", "cloud.drizzle.fill")
        case 61, 63, 65, 66, 67, 80, 81, 82:
            return ("Rain", "cloud.rain.fill")
        case 71, 73, 75, 77, 85, 86:
            return ("Snow", "snowflake")
        case 95, 96, 99:
            return ("Thunderstorm", "cloud.bolt.rain.fill")
        default:
            return ("Weather", "cloud.fill")
        }
    }
}
