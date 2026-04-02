import SwiftUI

struct SettingsView: View {
    @AppStorage("measurementUnits") private var unitsRaw = MeasurementUnits.metric.rawValue
    @AppStorage("routeSurfacePreference") private var routeSurfaceRaw = RouteSurfacePreference.streetsAndSidewalks.rawValue
    @AppStorage("mapDisplayMode") private var mapDisplayModeRaw = MapDisplayMode.standard.rawValue
    @AppStorage("mapTrafficEnabled") private var mapTrafficEnabled = false

    private var unitsBinding: Binding<MeasurementUnits> {
        Binding(
            get: { MeasurementUnits(rawValue: unitsRaw) ?? .metric },
            set: { unitsRaw = $0.rawValue }
        )
    }

    private var routeSurfaceBinding: Binding<RouteSurfacePreference> {
        Binding(
            get: { RouteSurfacePreference(rawValue: routeSurfaceRaw) ?? .streetsAndSidewalks },
            set: { routeSurfaceRaw = $0.rawValue }
        )
    }

    private var mapDisplayModeBinding: Binding<MapDisplayMode> {
        Binding(
            get: { MapDisplayMode(rawValue: mapDisplayModeRaw) ?? .standard },
            set: { mapDisplayModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("Map type", selection: mapDisplayModeBinding) {
                    ForEach(MapDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                Toggle("Show traffic", isOn: $mapTrafficEnabled)
            } header: {
                Text("Map")
            } footer: {
                Text(
                    "Satellite shows aerial imagery. Traffic highlights road congestion when data is available from Google."
                )
                .font(.caption)
            }

            Section {
                Picker("Route style", selection: routeSurfaceBinding) {
                    ForEach(RouteSurfacePreference.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Suggested routes")
            } footer: {
                Text(
                    "Roads only uses a compact loop (fewer stops) on Google’s walking network. "
                        + "Roads & hikes adds more intermediate stops so routes can use parks and trails where maps include them. "
                        + "Suggested loops always start and end at your current location."
                )
                .font(.caption)
            }

            Section {
                Picker("Units", selection: unitsBinding) {
                    ForEach(MeasurementUnits.allCases) { u in
                        Text(u.title).tag(u)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Measurements")
            } footer: {
                Text(
                    "Distances use meters and kilometers (metric) or feet and miles (US). "
                        + "Areas are shown in square meters (m²) or square feet (ft²)."
                )
                .font(.caption)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
