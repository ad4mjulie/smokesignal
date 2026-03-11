# smokesignal
An idea for permissionless data communications

Two laptops facing each other, cameras on. One flashes a QR code to the
other. If the other sees it, it flashes the same code back, or it flashes
a code of its own data plus a hash of the data it saw.

A community of laptops in windows could have a mesh of these, with houses
with more than one computer serving as routers.

Scaling wider, telescopes and large screens could potentially enable
point-to-point links many kilometers distant, linking community meshes.

## developer's notes
* once prototype is working, move to javascript frontend and keep python
  running under uwsgi on backend. then it can run on iPhone with iSH.
* needs my fork of zbar for returning bytes from decode

## iOS (Native App)
This repo now includes a native Swift/SwiftUI implementation.

### Do I Need the App Store?
No. To run it on your own iPhone, you can install it directly from Xcode (or with the script below). The App Store/TestFlight is only needed if you want to distribute it to other people at scale.

### What You Get
- `ios/SmokeSignalCore`: a pure Swift library (protocol + CRC32 + fountain codec) with unit tests.
- `ios/SmokeSignalApp`: SwiftUI screens (Send/Receive) + AVFoundation QR scanner + CoreImage QR generator.

### 1) Verify Core Builds (optional but recommended)
```bash
cd ios/SmokeSignalCore
swift test
```

### 2) Open the iOS Project in Xcode
Open `ios/SmokeSignal.xcodeproj`.

### 3) Set Signing (first run only)
1. Select the `SmokeSignal` target.
2. Signing & Capabilities -> enable "Automatically manage signing".
3. Pick your Team.
4. If Xcode asks, change the Bundle Identifier from the default `com.example.smokesignal` to something unique.

### 4) Run on a Real iPhone
The iOS Simulator does not behave like a real camera for this use case.
1. Plug in your iPhone.
2. Select your device in Xcode and Run.

#### One-Command Install (after you sign into Xcode once)
```bash
cd ios
./run_on_iphone.sh
```

### 5) How To Use
1. On phone A: open **Send**, pick a file/photo, tap **Start Transmitting** (it will animate QR frames).
2. On phone B: open **Receive** and point the camera at phone A's screen.
3. When decoding completes, use **Share Received File**.
