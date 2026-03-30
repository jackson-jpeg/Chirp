import SwiftUI
import CoreLocation

struct LocationAttachmentView: View {
    let text: String              // The "LOC:lat,lon,accuracy" string
    let viewerLocation: CLLocation?  // Current user's location for distance calc

    private var coordinate: CLLocationCoordinate2D? {
        LocationService.decodeLocation(text)
    }

    private var accuracy: Double? {
        LocationService.decodeAccuracy(text)
    }

    private var distanceMeters: CLLocationDistance? {
        guard let coord = coordinate, let viewer = viewerLocation else { return nil }
        return LocationService.distance(from: viewer, to: coord)
    }

    private var bearingDegrees: Double? {
        guard let coord = coordinate, let viewer = viewerLocation else { return nil }
        return LocationService.bearing(from: viewer.coordinate, to: coord)
    }

    private var formattedDistance: String? {
        guard let d = distanceMeters else { return nil }
        if d < 1000 {
            return String(format: "~%.0fm away", d)
        } else {
            return String(format: "~%.1fkm away", d / 1000)
        }
    }

    private var coordinateText: String {
        guard let coord = coordinate else { return "Invalid location" }
        return String(format: "%.6f, %.6f", coord.latitude, coord.longitude)
    }

    private var mapsURL: URL? {
        guard let coord = coordinate else { return nil }
        return URL(string: String(format: "maps:?ll=%.6f,%.6f", coord.latitude, coord.longitude))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with pin icon
            HStack(spacing: 6) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(Constants.Colors.amber)
                    .font(.title3)
                Text("Shared Location")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Constants.Colors.amber)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Shared location")

            // Coordinates
            Text(coordinateText)
                .font(Constants.Typography.mono)
                .foregroundStyle(Constants.Colors.textSecondary)
                .accessibilityLabel("Coordinates: \(coordinateText)")

            // Distance and bearing row
            if let dist = formattedDistance {
                HStack(spacing: 8) {
                    Text(dist)
                        .font(Constants.Typography.caption)
                        .foregroundStyle(Constants.Colors.textPrimary)

                    if let bearing = bearingDegrees {
                        Image(systemName: "location.north.fill")
                            .font(.caption)
                            .foregroundStyle(Constants.Colors.amber)
                            .rotationEffect(.degrees(bearing))
                            .accessibilityLabel("Direction: \(Int(bearing)) degrees")
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(dist)
            }

            // Accuracy if available
            if let acc = accuracy {
                Text(String(format: "Accuracy: ±%.0fm", acc))
                    .font(Constants.Typography.badge)
                    .foregroundStyle(Constants.Colors.textTertiary)
            }

            // Open in Maps button
            if let url = mapsURL {
                Button {
                    UIApplication.shared.open(url)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "map.fill")
                            .font(.caption2)
                        Text("Open in Maps")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(Constants.Colors.amber)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Constants.Colors.glassAmber)
                    .clipShape(Capsule())
                }
                .accessibilityLabel("Open location in Maps")
            }
        }
        .padding(12)
        .background(Constants.Colors.surfaceGlass)
        .clipShape(RoundedRectangle(cornerRadius: Constants.Layout.glassCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Constants.Layout.glassCornerRadius)
                .strokeBorder(Constants.Colors.glassAmberBorder.opacity(0.5), lineWidth: Constants.Layout.glassBorderWidth)
        )
    }
}

#Preview {
    VStack(spacing: 16) {
        LocationAttachmentView(
            text: "LOC:40.758896,-73.985130,10.0",
            viewerLocation: CLLocation(latitude: 40.748817, longitude: -73.985428)
        )

        LocationAttachmentView(
            text: "LOC:37.334886,-122.008988,5.0",
            viewerLocation: nil
        )
    }
    .padding()
    .background(Color.black)
}
