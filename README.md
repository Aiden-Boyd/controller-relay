# Dish iOS

A native iPhone/iPad controller sender for [Satellite](https://github.com/TinkerNorth/satellite).

Dish iOS discovers a Satellite receiver on your LAN, pairs using Satellite's HTTPS control plane, reads physical controllers through Apple's GameController framework, creates an authenticated Satellite session, derives the per-session key, and streams encrypted controller state over UDP.

## Status

### Current implementation

- SwiftUI app shell
- Bonjour discovery for `_satellite._udp`
- Satellite host list
- physical controller discovery through `GameController`
- Android Dish-style dual PIN pairing:
  - probe Satellite first
  - automatically generate/show a 4-digit Dish PIN
  - submit `clientPin` and poll `/api/pair/status` every 2 seconds for up to 2 minutes
  - keep manual entry of the PIN shown by Satellite as a fallback
- TOFU certificate fingerprint pinning for Satellite's self-signed TLS certificate
- pairing key stored in iOS Keychain
- authenticated `PUT /api/connections` session creation
- HMAC-SHA256 proof generation
- HKDF-SHA256 per-session key derivation
- ChaCha20-Poly1305-IETF-compatible packet construction via CryptoKit
- Satellite token/counter/AAD/nonce layout
- XUSB-compatible 12-byte controller reports
- encrypted UDP input streaming on the UDP port advertised by Satellite (default 9876)
- ~250 Hz snapshot loop
- 2-second heartbeat
- encrypted heartbeat ACK parsing
- replay protection for server-to-client packets
- up to 16 controller descriptors, subject to what iOS actually exposes
- basic session-close handling

### Not yet ported from Android Dish

- real-device integration testing against current Satellite
- Android Dish's dynamic per-slot controller PUT/DELETE convergence
- rumble feedback through `GCDeviceHaptics` / controller haptics
- live hot-plug topology updates while already streaming
- dynamic emulation type selection from Satellite's catalog
- motion/battery/touchpad telemetry
- automatic reconnect + heartbeat epoch/bitmap reconciliation
- on-screen virtual controller and touchpad
- polished controller input tester and per-slot UI

## Generate the Xcode project

This repo uses [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/Aiden-Boyd/dish-ios.git
cd dish-ios
xcodegen generate
open DishIOS.xcodeproj
```

Then:

1. Select the `DishIOS` target.
2. Under **Signing & Capabilities**, choose your Apple development team.
3. Connect an iPhone or iPad.
4. Build and run on the physical device.
5. Allow the Local Network permission prompt.
6. Pair a Bluetooth controller with the iPhone/iPad.
7. Run Satellite on the Windows PC.
8. Select the discovered PC in Dish and enter Satellite's 4-digit PIN.
9. Tap **Start Streaming**.

A physical device is strongly recommended because local-network permissions, Bluetooth controllers, and real LAN discovery are central to the app.

## Satellite protocol

Dish iOS currently implements Satellite protocol v1:

- HTTPS control plane: port 9443
- encrypted UDP data plane: port 9876
- mDNS discovery: `_satellite._udp`
- heartbeat cadence: 2 seconds
- INPUT payload: controller index + 12-byte XUSB report

The admin web UI on port 9877 is not a client API and Dish iOS does not use it.

## Important

The transport and crypto implementation has been written against Satellite's current `docs/contract.md`, but it still needs a physical iPhone + real Satellite receiver integration test. The next useful debugging data is any Xcode build error or Satellite log produced by the first run.

## License

Dish iOS is an independent client project and is not an official TinkerNorth product.
