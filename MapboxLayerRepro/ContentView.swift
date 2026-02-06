import SwiftUI
import MapboxMaps

struct ContentView: View {
    @State private var lastUpdateTime: Date?
    @State private var statusMessage = "Tap a button to test layer color updates"

    var body: some View {
        VStack(spacing: 0) {
            MapViewRepresentable(
                lastUpdateTime: $lastUpdateTime,
                statusMessage: $statusMessage
            )

            VStack(spacing: 12) {
              Spacer()
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if let updateTime = lastUpdateTime {
                    Text("Last update: \(updateTime, formatter: timeFormatter)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 8) {
                    Button("Change Feature Color (USA)") {
                        NotificationCenter.default.post(
                            name: .changeFeatureColor,
                            object: nil
                        )
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Change All Colors") {
                        NotificationCenter.default.post(
                            name: .changeAllColors,
                            object: nil
                        )
                    }
                    .buttonStyle(.bordered)

                    Button("Reset Colors") {
                        NotificationCenter.default.post(
                            name: .resetColors,
                            object: nil
                        )
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 16)
            .background(Color(.systemBackground))
            .frame(height: 300)
        }
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter
    }
}

extension Notification.Name {
    static let changeFeatureColor = Notification.Name("changeFeatureColor")
    static let changeAllColors = Notification.Name("changeAllColors")
    static let resetColors = Notification.Name("resetColors")
}

struct MapViewRepresentable: UIViewRepresentable {
    @Binding var lastUpdateTime: Date?
    @Binding var statusMessage: String

    func makeUIView(context: Context) -> MapView {
        let mapView = MapView(frame: .zero)

        // Set initial camera to show USA
        let cameraOptions = CameraOptions(
            center: CLLocationCoordinate2D(latitude: 39.8283, longitude: -98.5795),
            zoom: 3
        )
        mapView.mapboxMap.setCamera(to: cameraOptions)

        // Load the map and setup layers
        mapView.mapboxMap.onStyleLoaded.observeNext { _ in
            context.coordinator.setupLayers(mapView: mapView)
        }.store(in: &context.coordinator.cancelables)

        // Setup notification observers
        context.coordinator.setupNotifications(
            mapView: mapView,
            lastUpdateTime: $lastUpdateTime,
            statusMessage: $statusMessage
        )

        return mapView
    }

    func updateUIView(_ uiView: MapView, context: Context) {
        // No updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var cancelables: [AnyCancelable] = []
        private var observers: [NSObjectProtocol] = []

        deinit {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
        }

        func setupLayers(mapView: MapView) {
            do {
                // Add Mapbox country boundaries source
                var source = VectorSource(id: "countries")
                source.url = "mapbox://mapbox.country-boundaries-v1"
                source.promoteId2 = .global(.constant("iso_3166_1"))  // Use iso_3166_1 as feature ID (e.g., "US")
                try mapView.mapboxMap.addSource(source)

                // Create fill layer with feature-state expression for color
                var fillLayer = FillLayer(id: "country-fills", source: "countries")
                fillLayer.sourceLayer = "country_boundaries"

                // Color expression based on feature state
                fillLayer.fillColor = .expression(
                    Exp(.switchCase) {
                        Exp(.boolean) {
                            Exp(.featureState) { "isHighlighted" }
                            false
                        }
                        UIColor.red.withAlphaComponent(0.6)
                        UIColor.gray.withAlphaComponent(0.2)
                    }
                )

                fillLayer.fillOpacity = .constant(1.0)

                try mapView.mapboxMap.addLayer(fillLayer)

                print("✅ Layers setup complete")
            } catch {
                print("❌ Error setting up layers: \(error)")
            }
        }

        func setupNotifications(
            mapView: MapView,
            lastUpdateTime: Binding<Date?>,
            statusMessage: Binding<String>
        ) {
            let changeFeatureObserver = NotificationCenter.default.addObserver(
                forName: .changeFeatureColor,
                object: nil,
                queue: .main
            ) { _ in
                self.changeFeatureColor(
                    mapView: mapView,
                    lastUpdateTime: lastUpdateTime,
                    statusMessage: statusMessage
                )
            }

            let changeAllObserver = NotificationCenter.default.addObserver(
                forName: .changeAllColors,
                object: nil,
                queue: .main
            ) { _ in
                self.changeAllColors(
                    mapView: mapView,
                    lastUpdateTime: lastUpdateTime,
                    statusMessage: statusMessage
                )
            }

            let resetObserver = NotificationCenter.default.addObserver(
                forName: .resetColors,
                object: nil,
                queue: .main
            ) { _ in
                self.resetColors(
                    mapView: mapView,
                    lastUpdateTime: lastUpdateTime,
                    statusMessage: statusMessage
                )
            }

            observers = [changeFeatureObserver, changeAllObserver, resetObserver]
        }

        private func changeFeatureColor(
            mapView: MapView,
            lastUpdateTime: Binding<Date?>,
            statusMessage: Binding<String>
        ) {
            let timestamp = Date()
            lastUpdateTime.wrappedValue = timestamp

            print("🔵 [\(timestamp)] Setting feature state for USA to highlighted")

            mapView.mapboxMap.setFeatureState(
                sourceId: "countries",
                sourceLayerId: "country_boundaries",
                featureId: "US",
                state: ["isHighlighted": true]
            ) { result in
                if case .failure(let error) = result {
                    print("❌ Error setting feature state: \(error)")
                    statusMessage.wrappedValue = "Error: \(error.localizedDescription)"
                } else {
                    print("✅ Feature state set successfully")
                    statusMessage.wrappedValue = "Color changed at \(timestamp.formatted(date: .omitted, time: .standard))\n⚠️ If you don't see red USA, try zooming the map"
                }
            }
        }

        private func changeAllColors(
            mapView: MapView,
            lastUpdateTime: Binding<Date?>,
            statusMessage: Binding<String>
        ) {
            let timestamp = Date()
            lastUpdateTime.wrappedValue = timestamp

            let countries = ["US", "CA", "MX", "BR", "GB", "FR", "DE", "CN", "IN", "AU"]

            print("🔵 [\(timestamp)] Setting feature state for \(countries.count) countries")

            var successCount = 0
            var errorCount = 0

            for countryId in countries {
                mapView.mapboxMap.setFeatureState(
                    sourceId: "countries",
                    sourceLayerId: "country_boundaries",
                    featureId: countryId,
                    state: ["isHighlighted": true]
                ) { result in
                    if case .failure(let error) = result {
                        errorCount += 1
                        print("❌ Error setting feature state for \(countryId): \(error)")
                    } else {
                        successCount += 1
                    }

                    if successCount + errorCount == countries.count {
                        print("✅ Feature states set: \(successCount) succeeded, \(errorCount) failed")
                        statusMessage.wrappedValue = "Changed \(successCount) countries at \(timestamp.formatted(date: .omitted, time: .standard))\n⚠️ If you don't see red countries, try zooming the map"
                    }
                }
            }
        }

        private func resetColors(
            mapView: MapView,
            lastUpdateTime: Binding<Date?>,
            statusMessage: Binding<String>
        ) {
            let timestamp = Date()
            lastUpdateTime.wrappedValue = timestamp

            print("🔵 [\(timestamp)] Resetting all feature states")

            let countries = ["US", "CA", "MX", "BR", "GB", "FR", "DE", "CN", "IN", "AU"]

            var resetCount = 0

            for countryId in countries {
                mapView.mapboxMap.removeFeatureState(
                    sourceId: "countries",
                    sourceLayerId: "country_boundaries",
                    featureId: countryId,
                    stateKey: nil
                ) { result in
                    resetCount += 1

                    if resetCount == countries.count {
                        print("✅ All feature states reset")
                        statusMessage.wrappedValue = "Colors reset at \(timestamp.formatted(date: .omitted, time: .standard))\n⚠️ If colors don't clear, try panning/zooming the map"
                    }
                }
            }
        }
    }
}
