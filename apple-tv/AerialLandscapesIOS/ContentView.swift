import SwiftUI

struct ContentView: View {
    var body: some View {
        WebView(url: URL(string: "https://drones.pjloury.com")!)
            .ignoresSafeArea()
    }
}
