import CoreLocation
import Combine
import Foundation
import MapKit
import SwiftUI

@MainActor
struct LocationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locationProvider = LocationProvider()
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedCoordinate: CLLocationCoordinate2D?

    let onSend: (GeoLocation) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Map(position: $cameraPosition) {
                    UserAnnotation()
                }
                .mapStyle(.standard(elevation: .realistic))
                .onMapCameraChange(frequency: .onEnd) { context in
                    selectedCoordinate = context.region.center
                }

                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.accentColor)
                    .shadow(color: .black.opacity(0.28), radius: 4, y: 2)
                    .offset(y: -20)
                    .allowsHitTesting(false)

                VStack {
                    if let message = locationProvider.errorMessage {
                        Text(message)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: Capsule())
                            .padding()
                    }

                    Spacer()

                    HStack {
                        Spacer()
                        Button(action: centerOnCurrentLocation) {
                            Group {
                                if locationProvider.isLocating {
                                    ProgressView()
                                } else {
                                    Image(systemName: "location.fill")
                                }
                            }
                            .frame(width: 44, height: 44)
                            .background(.regularMaterial, in: Circle())
                            .shadow(color: .black.opacity(0.16), radius: 5, y: 2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Показать мою геопозицию")
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Text(coordinateText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Button(action: sendSelection) {
                        Label("Отправить эту геопозицию", systemImage: "location.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedCoordinate == nil)
                }
                .padding(16)
                .background(.regularMaterial)
            }
            .navigationTitle("Геопозиция")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
        .onAppear {
            locationProvider.requestCurrentLocation()
        }
        .onReceive(locationProvider.$location.compactMap { $0 }) { location in
            selectedCoordinate = location.coordinate
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: location.coordinate,
                    latitudinalMeters: 1_200,
                    longitudinalMeters: 1_200
                )
            )
        }
    }

    private var coordinateText: String {
        guard let selectedCoordinate else { return "Переместите карту, чтобы выбрать точку" }
        return String(
            format: "%.6f, %.6f",
            locale: Locale(identifier: "en_US_POSIX"),
            selectedCoordinate.latitude,
            selectedCoordinate.longitude
        )
    }

    private func centerOnCurrentLocation() {
        if let location = locationProvider.location {
            selectedCoordinate = location.coordinate
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: location.coordinate,
                    latitudinalMeters: 1_200,
                    longitudinalMeters: 1_200
                )
            )
        } else {
            locationProvider.requestCurrentLocation()
        }
    }

    private func sendSelection() {
        guard let selectedCoordinate,
              let location = GeoLocation(
                latitude: selectedCoordinate.latitude,
                longitude: selectedCoordinate.longitude
              ) else { return }
        onSend(location)
        dismiss()
    }
}

#Preview {
    LocationPickerView { _ in }
}
