import CoreLocation
import SwiftUI

struct RootView: View {
    @State private var locationManager = CLLocationManager()

    var body: some View {
        VStack {
            Text("round not started")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if locationManager.authorizationStatus == .notDetermined {
                locationManager.requestWhenInUseAuthorization()
            }
        }
    }
}

#Preview {
    RootView()
}
