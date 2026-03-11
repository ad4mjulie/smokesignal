import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            SendView()
                .tabItem { Label("Send", systemImage: "qrcode") }
            ReceiveView()
                .tabItem { Label("Receive", systemImage: "camera.viewfinder") }
        }
    }
}

