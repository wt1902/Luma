import MapKit
import SwiftUI

struct LocationMessagePreview: View {
    let location: GeoLocation

    var body: some View {
        Button(action: openInMaps) {
            ZStack(alignment: .bottomLeading) {
                Map(initialPosition: cameraPosition, interactionModes: []) {
                    Marker("Геопозиция", coordinate: coordinate)
                        .tint(.red)
                }
                .allowsHitTesting(false)

                HStack(spacing: 7) {
                    Image(systemName: "location.fill")
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Геопозиция")
                            .font(.subheadline.weight(.semibold))
                        Text("Открыть в Картах")
                            .font(.caption)
                            .opacity(0.82)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 11))
                .padding(9)
            }
            .frame(width: 252, height: 170)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Геопозиция")
        .accessibilityHint("Открывает точку в Картах")
    }

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
    }

    private var cameraPosition: MapCameraPosition {
        .region(
            MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 1_500,
                longitudinalMeters: 1_500
            )
        )
    }

    private func openInMaps() {
        let item = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), address: nil)
        item.name = "Геопозиция из Luma"
        item.openInMaps()
    }
}

#Preview {
    LocationMessagePreview(
        location: GeoLocation(latitude: 55.7558, longitude: 37.6173)!
    )
}
