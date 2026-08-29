import Foundation
import GameController

struct GamepadReport: Equatable {
    var buttons: UInt16 = 0
    var leftTrigger: UInt8 = 0
    var rightTrigger: UInt8 = 0
    var thumbLX: Int16 = 0
    var thumbLY: Int16 = 0
    var thumbRX: Int16 = 0
    var thumbRY: Int16 = 0

    static let size = 12

    func encode() -> Data {
        var data = Data()
        data.appendLE(buttons)
        data.append(leftTrigger)
        data.append(rightTrigger)
        data.appendLE(thumbLX)
        data.appendLE(thumbLY)
        data.appendLE(thumbRX)
        data.appendLE(thumbRY)
        return data
    }

    static func from(_ gamepad: GCExtendedGamepad) -> GamepadReport {
        var report = GamepadReport()

        if gamepad.dpad.up.isPressed { report.buttons |= 0x0001 }
        if gamepad.dpad.down.isPressed { report.buttons |= 0x0002 }
        if gamepad.dpad.left.isPressed { report.buttons |= 0x0004 }
        if gamepad.dpad.right.isPressed { report.buttons |= 0x0008 }

        if gamepad.buttonMenu.isPressed { report.buttons |= 0x0010 }
        if gamepad.buttonOptions?.isPressed == true { report.buttons |= 0x0020 }
        if gamepad.leftThumbstickButton?.isPressed == true { report.buttons |= 0x0040 }
        if gamepad.rightThumbstickButton?.isPressed == true { report.buttons |= 0x0080 }

        if gamepad.leftShoulder.isPressed { report.buttons |= 0x0100 }
        if gamepad.rightShoulder.isPressed { report.buttons |= 0x0200 }

        if gamepad.buttonA.isPressed { report.buttons |= 0x1000 }
        if gamepad.buttonB.isPressed { report.buttons |= 0x2000 }
        if gamepad.buttonX.isPressed { report.buttons |= 0x4000 }
        if gamepad.buttonY.isPressed { report.buttons |= 0x8000 }

        report.leftTrigger = UInt8(clamping: Int(gamepad.leftTrigger.value * 255))
        report.rightTrigger = UInt8(clamping: Int(gamepad.rightTrigger.value * 255))

        report.thumbLX = axis(gamepad.leftThumbstick.xAxis.value)
        report.thumbLY = axis(gamepad.leftThumbstick.yAxis.value)
        report.thumbRX = axis(gamepad.rightThumbstick.xAxis.value)
        report.thumbRY = axis(gamepad.rightThumbstick.yAxis.value)

        return report
    }

    private static func axis(_ value: Float) -> Int16 {
        let clamped = max(-1.0, min(1.0, value))

        if clamped >= 0 {
            return Int16(clamping: Int(clamped * 32767.0))
        } else {
            return Int16(clamping: Int(clamped * 32768.0))
        }
    }
}

extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    mutating func appendBE<T: FixedWidthInteger>(_ value: T) {
        var big = value.bigEndian
        Swift.withUnsafeBytes(of: &big) { append(contentsOf: $0) }
    }
}
