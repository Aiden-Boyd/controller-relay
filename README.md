# Dish iOS

A native iPhone/iPad controller sender for [Satellite](https://github.com/TinkerNorth/satellite).

Dish iOS discovers a Satellite receiver on your LAN, pairs using Satellite's HTTPS control plane, reads physical controllers through Apple's GameController framework, and will stream controller state to Satellite over its encrypted UDP data plane.

## Status

### Milestone 1 — scaffolded

- SwiftUI app shell
- Bonjour discovery for `_satellite._udp`
- Satellite host list
- physical controller discovery through `GameController`
- 4-digit operator-PIN pairing against `POST /api/pair`
- TOFU certificate fingerprint pinning for Satellite's self-signed TLS certificate
- pairing key stored in iOS Keychain
- paired dashboard

### Next

- authenticated session creation via `PUT /api/connections`
- HKDF-SHA256 session-key derivation
- ChaCha20-Poly1305 UDP packet codec
- XUSB-style 12-byte gamepad reports
- 250-ish Hz input streaming
- heartbeat/ACK handling
- multiple controller slots
- rumble feedback

## Generate the Xcode project

This repo uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) so the generated `.xcodeproj` does not need to be hand-maintained.

```bash
brew install xcodegen
git clone https://github.com/Aiden-Boyd/dish-ios.git
cd dish-ios
xcodegen generate
open DishIOS.xcodeproj
```

Select your Apple development team in Xcode, connect an iPhone, and run the `DishIOS` target.

> A physical iPhone/iPad is strongly recommended because local-network permissions, Bluetooth controllers, and real LAN discovery are central to the app.

## Satellite

Run Satellite on the Windows gaming PC. Dish iOS uses the current Satellite protocol v1:

- HTTPS control plane: port 9443
- encrypted UDP data plane: port 9876
- mDNS discovery: `_satellite._udp`

The admin web UI on port 9877 is not a client API and Dish iOS does not use it.

## License

Dish iOS is an independent client project and is not an official TinkerNorth product.
