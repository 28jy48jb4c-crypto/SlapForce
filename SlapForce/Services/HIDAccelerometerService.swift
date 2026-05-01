import Foundation
import IOKit
import IOKit.hid

struct AccelerationSample: Equatable {
    var x: Double
    var y: Double
    var z: Double

    static let zero = AccelerationSample(x: 0, y: 0, z: 0)

    var magnitude: Double {
        sqrt(x * x + y * y + z * z)
    }
}

enum AccelerometerError: LocalizedError {
    case serviceMatchFailed(IOReturn)
    case noAccelerometer
    case openFailed(IOReturn)

    var errorDescription: String? {
        switch self {
        case .serviceMatchFailed(let code):
            return "Could not enumerate AppleSPUHIDDevice services: \(code)."
        case .noAccelerometer:
            return "No AppleSPUHIDDevice accelerometer was found. This must run on an Apple Silicon MacBook with the internal motion sensor."
        case .openFailed(let code):
            return "Could not open AppleSPUHIDDevice accelerometer: \(code)."
        }
    }
}

final class HIDAccelerometerService {
    var onSample: ((AccelerationSample) -> Void)?
    var onStatus: ((String) -> Void)?

    private var devices: [IOHIDDevice] = []
    private var reportBuffers: [NSMutableData] = []
    private var sampleCount = 0
    private var lastRaw = (x: Int32(0), y: Int32(0), z: Int32(0))

    // Apple Silicon MacBook sensors are exposed by the Sensor Processing Unit
    // as AppleSPUHIDDevice services, not as normal mouse/trackpad HID axes.
    private let serviceClass = "AppleSPUHIDDevice"
    private let driverClass = "AppleSPUHIDDriver"
    private let pageVendor: Int64 = 0xFF00
    private let usageAccelerometer: Int64 = 3
    private let reportBufferSize = 4096
    private let imuReportLength = 22
    private let imuDataOffset = 6
    private let reportIntervalUS: Int32 = 1000

    func start() throws {
        guard devices.isEmpty else { return }

        wakeSPUDrivers()
        let accelerometerServices = try findAccelerometerServices()
        guard !accelerometerServices.isEmpty else {
            throw AccelerometerError.noAccelerometer
        }

        for service in accelerometerServices {
            guard let device = IOHIDDeviceCreate(kCFAllocatorDefault, service) else {
                IOObjectRelease(service)
                continue
            }
            let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            guard openResult == kIOReturnSuccess else {
                IOObjectRelease(service)
                throw AccelerometerError.openFailed(openResult)
            }

            let buffer = NSMutableData(length: reportBufferSize)!
            let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            IOHIDDeviceRegisterInputReportCallback(
                device,
                buffer.mutableBytes.assumingMemoryBound(to: UInt8.self),
                buffer.length,
                accelerometerReportReceived,
                context
            )
            IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

            devices.append(device)
            reportBuffers.append(buffer)
            IOObjectRelease(service)
        }

        onStatus?("Listening to AppleSPUHIDDevice accelerometer (\(devices.count) device)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self, !self.devices.isEmpty, self.sampleCount == 0 else { return }
            self.onStatus?("AppleSPUHIDDevice opened, but no Bosch IMU reports arrived. Test on real Apple Silicon MacBook hardware; this SPU HID path may require non-sandboxed/elevated access on this macOS build.")
        }
    }

    func stop() {
        for device in devices {
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        devices.removeAll()
        reportBuffers.removeAll()
        sampleCount = 0
    }

    fileprivate func handle(report: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        guard length >= imuReportLength else { return }
        let data = UnsafeBufferPointer(start: report, count: Int(length))
        let rawX = readInt32LE(data, at: imuDataOffset)
        let rawY = readInt32LE(data, at: imuDataOffset + 4)
        let rawZ = readInt32LE(data, at: imuDataOffset + 8)
        lastRaw = (rawX, rawY, rawZ)

        // The SPU reports raw BMI286 integer samples. Scaling by 100k keeps
        // resting gravity around a visible value and makes impact spikes usable
        // with the UI sensitivity slider.
        let sample = AccelerationSample(
            x: Double(rawX) / 100_000.0,
            y: Double(rawY) / 100_000.0,
            z: Double(rawZ) / 100_000.0
        )

        sampleCount += 1
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.sampleCount % 60 == 0 {
                self.onStatus?(
                    "AppleSPU samples: \(self.sampleCount), raw \(self.lastRaw.x), \(self.lastRaw.y), \(self.lastRaw.z), magnitude \(String(format: "%.3f", sample.magnitude))"
                )
            }
            self.onSample?(sample)
        }
    }

    private func wakeSPUDrivers() {
        guard let matching = IOServiceMatching(driverClass) else { return }
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == kIOReturnSuccess else { return }
        defer { IOObjectRelease(iterator) }

        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            setInt32Property(service, key: "SensorPropertyReportingState", value: 1)
            setInt32Property(service, key: "SensorPropertyPowerState", value: 1)
            setInt32Property(service, key: "ReportInterval", value: reportIntervalUS)
            IOObjectRelease(service)
        }
    }

    private func findAccelerometerServices() throws -> [io_service_t] {
        guard let matching = IOServiceMatching(serviceClass) else { return [] }
        var iterator = io_iterator_t()
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == kIOReturnSuccess else {
            throw AccelerometerError.serviceMatchFailed(result)
        }
        defer { IOObjectRelease(iterator) }

        var services: [io_service_t] = []
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }

            let usagePage = intProperty(service, key: "PrimaryUsagePage")
            let usage = intProperty(service, key: "PrimaryUsage")
            let product = stringProperty(service, key: "Product") ?? serviceClass
            NSLog("SlapForce: SPU candidate \(product), usagePage \(usagePage ?? -1), usage \(usage ?? -1)")

            if usagePage == pageVendor, usage == usageAccelerometer {
                services.append(service)
            } else {
                IOObjectRelease(service)
            }
        }
        return services
    }

    private func intProperty(_ service: io_service_t, key: String) -> Int64? {
        guard let unmanaged = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        let value = unmanaged.takeRetainedValue()
        return (value as? NSNumber)?.int64Value
    }

    private func stringProperty(_ service: io_service_t, key: String) -> String? {
        guard let unmanaged = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        return unmanaged.takeRetainedValue() as? String
    }

    private func setInt32Property(_ service: io_service_t, key: String, value: Int32) {
        var mutableValue = value
        guard let number = CFNumberCreate(kCFAllocatorDefault, .sInt32Type, &mutableValue) else { return }
        IORegistryEntrySetCFProperty(service, key as CFString, number)
    }

    private func readInt32LE(_ data: UnsafeBufferPointer<UInt8>, at offset: Int) -> Int32 {
        guard offset + 3 < data.count else { return 0 }
        let value = UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
        return Int32(bitPattern: value)
    }
}

private func accelerometerReportReceived(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    type: IOHIDReportType,
    reportID: UInt32,
    report: UnsafeMutablePointer<UInt8>,
    reportLength: CFIndex
) {
    guard result == kIOReturnSuccess, let context else { return }
    let service = Unmanaged<HIDAccelerometerService>.fromOpaque(context).takeUnretainedValue()
    service.handle(report: report, length: reportLength)
}
