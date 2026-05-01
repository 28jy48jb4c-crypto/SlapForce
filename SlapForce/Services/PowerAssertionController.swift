import Foundation
import IOKit.pwr_mgt

@MainActor
final class PowerAssertionController: ObservableObject {
    @Published private(set) var isActive = false

    private var assertionID = IOPMAssertionID(0)

    func update(shouldKeepAwake: Bool, isListening: Bool) {
        if shouldKeepAwake && isListening {
            acquire()
        } else {
            release()
        }
    }

    func acquire() {
        guard !isActive else { return }
        let reason = "SlapForce is monitoring accelerometer events" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoIdleSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )
        isActive = result == kIOReturnSuccess
    }

    func release() {
        guard isActive else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isActive = false
    }

    deinit {
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
        }
    }
}

