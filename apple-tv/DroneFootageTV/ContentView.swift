import SwiftUI

struct ContentView: View {
    var body: some View {
        TVWebViewContainer()
            .ignoresSafeArea()
            .background(Color.black)
    }
}

struct TVWebViewContainer: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> TVWebViewController {
        TVWebViewController()
    }
    func updateUIViewController(_ vc: TVWebViewController, context: Context) {}
}
