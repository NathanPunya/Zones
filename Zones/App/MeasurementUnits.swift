import SwiftUI

/// Distance and area display preference for the app.
enum MeasurementUnits: String, CaseIterable, Identifiable, Hashable {
    case metric
    case imperialUS

    var id: String { rawValue }

    var title: String {
        switch self {
        case .metric: return "Metric"
        case .imperialUS: return "Imperial (US)"
        }
    }
}

enum UnitsFormat {
    private static func areaValueString(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = .current
        f.maximumFractionDigits = value < 100 ? 1 : 0
        return f.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
    }

    static func distance(meters: Double, units: MeasurementUnits) -> String {
        guard meters > 0 else { return "—" }
        switch units {
        case .metric:
            if meters >= 1000 { return String(format: "%.2f km", meters / 1000) }
            return String(format: "%.0f m", meters)
        case .imperialUS:
            let miles = meters / 1609.344
            if miles >= 0.25 { return String(format: "%.2f mi", miles) }
            let ft = meters * 3.28084
            return String(format: "%.0f ft", ft)
        }
    }

    /// Area is always **m²** (metric) or **ft²** (imperial), with grouped digits for large values.
    static func area(squareMeters: Double, units: MeasurementUnits) -> String {
        guard squareMeters > 0 else { return "—" }
        switch units {
        case .metric:
            return "\(areaValueString(squareMeters)) m²"
        case .imperialUS:
            let ft2 = squareMeters * 10.76391041671
            return "\(areaValueString(ft2)) ft²"
        }
    }

    static func targetRadius(meters: Double, units: MeasurementUnits) -> String {
        guard meters > 0 else { return "—" }
        switch units {
        case .metric:
            if meters >= 1000 { return String(format: "%.2f km", meters / 1000) }
            return String(format: "%.0f m", meters)
        case .imperialUS:
            let mi = meters / 1609.344
            if mi >= 0.1 { return String(format: "%.2f mi", mi) }
            return String(format: "%.0f ft", meters * 3.28084)
        }
    }

    // MARK: - Route duration (typical paces; not personalized)

    /// Walking ~5 km/h, running ~10 km/h — common easy training paces for estimates.
    private static let estimateWalkSpeedMPS = 5.0 / 3.6
    private static let estimateRunSpeedMPS = 10.0 / 3.6

    /// Whole minutes at each pace; at least 1 when distance is positive.
    static func routeWalkRunMinutes(pathMeters: Double) -> (walk: Int, run: Int)? {
        guard pathMeters > 0 else { return nil }
        let walkMin = max(1, Int((pathMeters / estimateWalkSpeedMPS / 60).rounded()))
        let runMin = max(1, Int((pathMeters / estimateRunSpeedMPS / 60).rounded()))
        return (walkMin, runMin)
    }

    /// When duration is 60+ minutes, show decimal hours (e.g. `~1.5 hr`); otherwise minutes.
    private static func routeEstimateDurationFragment(minutes: Int) -> String {
        guard minutes > 0 else { return "—" }
        if minutes >= 60 {
            let hours = Double(minutes) / 60.0
            return String(format: "~%.1f hr", hours)
        }
        return "~\(minutes) min"
    }

    /// Short label for UI, e.g. `~45 min walk · ~22 min run` or `~1.5 hr walk · ~0.8 hr run`.
    static func routeWalkRunEstimateLabel(pathMeters: Double) -> String {
        guard let (w, r) = routeWalkRunMinutes(pathMeters: pathMeters) else { return "—" }
        let walkPart = routeEstimateDurationFragment(minutes: w)
        let runPart = routeEstimateDurationFragment(minutes: r)
        return "\(walkPart) walk · \(runPart) run"
    }
}

private struct MeasurementUnitsKey: EnvironmentKey {
    static let defaultValue: MeasurementUnits = .metric
}

extension EnvironmentValues {
    var measurementUnits: MeasurementUnits {
        get { self[MeasurementUnitsKey.self] }
        set { self[MeasurementUnitsKey.self] = newValue }
    }
}
