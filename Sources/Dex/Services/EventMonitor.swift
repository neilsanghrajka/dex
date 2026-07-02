import ApplicationServices
import AppKit
import Foundation
import QuartzCore

final class EventMonitor {
    var onDoubleOption: (() -> Void)?
    var onCycle: ((CycleDirection, CycleTrigger) -> Void)?
    var onModeHotkey: ((Int) -> Bool)?
    var onEscape: (() -> Void)?
    var onControlDragChanged: ((CGPoint) -> Void)?
    var onControlDragEnded: ((CGPoint) -> Void)?
    var shouldHandleCycle: (() -> Bool)?
    var shouldHandleModeHotkeys: (() -> Bool)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var lastOptionPress: CFTimeInterval = 0
    private var lastCycleTime: CFTimeInterval = 0
    private var accumulatedScrollDelta: Double = 0
    private var optionWasDown = false
    private var isControlDragging = false
    private let doubleTapInterval: CFTimeInterval = 0.55
    private let cycleInterval: CFTimeInterval = 0.38
    private let scrollThreshold: Double = 7

    func start() {
        startNSEventFallbackMonitors()
        guard eventTap == nil else { return }

        let mask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<EventMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = monitor.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }
            return monitor.handle(type: type, event: event)
        }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else { return }
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    func stop() {
        stopNSEventFallbackMonitors()
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        runLoopSource = nil
        eventTap = nil
        lastOptionPress = 0
        accumulatedScrollDelta = 0
        optionWasDown = false
        isControlDragging = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .flagsChanged:
            handleFlagsChanged(event)
        case .keyDown:
            if handleKeyDown(event) { return nil }
        case .scrollWheel:
            if handleScroll(event) { return nil }
        case .leftMouseDragged:
            handleDrag(event)
        case .leftMouseUp:
            handleMouseUp(event)
        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleFlagsChanged(_ event: CGEvent) {
        handleOptionState(event.flags.contains(.maskAlternate))
    }

    private func handleOptionState(_ optionDown: Bool) {
        guard optionDown != optionWasDown else { return }
        optionWasDown = optionDown

        if !optionDown {
            accumulatedScrollDelta = 0
        }

        guard optionDown else { return }
        let now = CACurrentMediaTime()
        if now - lastOptionPress <= doubleTapInterval {
            lastOptionPress = 0
            DispatchQueue.main.async { self.onDoubleOption?() }
        } else {
            lastOptionPress = now
        }
    }

    private func handleKeyDown(_ event: CGEvent) -> Bool {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if keyCode == 53 {
            DispatchQueue.main.async { self.onEscape?() }
            return false
        }
        if shouldHandleModeHotkeys?() != false,
           let slot = modeSlot(from: UInt16(keyCode), flags: event.flags) {
            return onModeHotkey?(slot) ?? false
        }
        if shouldHandleCycle?() == false {
            return false
        }
        guard usesCycleModifier(event.flags) else { return false }
        return handleArrowKey(code: UInt16(keyCode), trigger: .keyboard)
    }

    private func handleScroll(_ event: CGEvent) -> Bool {
        if shouldHandleCycle?() == false {
            return false
        }
        guard usesCycleModifier(event.flags) else { return false }
        if event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0 {
            return true
        }

        let pointDelta = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let fixedDelta = event.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let lineDelta = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let delta: Double
        if pointDelta != 0 {
            delta = Double(pointDelta)
        } else if fixedDelta != 0 {
            delta = Double(fixedDelta) / 65_536
        } else {
            delta = Double(lineDelta)
        }

        guard delta != 0 else { return false }
        handleScrollDelta(delta)
        return true
    }

    private func handleDrag(_ event: CGEvent) {
        guard event.flags.contains(.maskControl) else { return }
        isControlDragging = true
        let point = event.location
        DispatchQueue.main.async { self.onControlDragChanged?(point) }
    }

    private func handleMouseUp(_ event: CGEvent) {
        guard isControlDragging else { return }
        isControlDragging = false
        let point = event.location
        DispatchQueue.main.async { self.onControlDragEnded?(point) }
    }

    private func handleArrowKey(code: UInt16, trigger: CycleTrigger) -> Bool {
        if code == 126 {
            DispatchQueue.main.async { self.onCycle?(.forward, trigger) }
            return true
        }
        if code == 125 {
            DispatchQueue.main.async { self.onCycle?(.backward, trigger) }
            return true
        }
        return false
    }

    private func handleArrowKey(code: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        if shouldHandleCycle?() == false {
            return false
        }
        guard usesCycleModifier(flags) else { return false }
        return handleArrowKey(code: code, trigger: .keyboard)
    }

    private func handleScrollDelta(_ delta: Double) {
        if accumulatedScrollDelta.sign != delta.sign {
            accumulatedScrollDelta = 0
        }
        accumulatedScrollDelta += delta

        let now = CACurrentMediaTime()
        guard abs(accumulatedScrollDelta) >= scrollThreshold,
              now - lastCycleTime >= cycleInterval else {
            return
        }

        let direction: CycleDirection = accumulatedScrollDelta > 0 ? .forward : .backward
        accumulatedScrollDelta = 0
        lastCycleTime = now
        DispatchQueue.main.async { self.onCycle?(direction, .scroll) }
    }

    private func usesCycleModifier(_ flags: CGEventFlags) -> Bool {
        flags.contains(.maskAlternate)
    }

    private func usesCycleModifier(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.contains(.option)
    }

    private func modeSlot(from keyCode: UInt16, flags: CGEventFlags) -> Int? {
        guard flags.contains(.maskAlternate), !flags.contains(.maskShift) else { return nil }
        return modeSlot(from: keyCode)
    }

    private func modeSlot(from keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Int? {
        guard flags.contains(.option), !flags.contains(.shift) else { return nil }
        return modeSlot(from: keyCode)
    }

    private func modeSlot(from keyCode: UInt16) -> Int? {
        switch keyCode {
        case 18: 1
        case 19: 2
        case 20: 3
        case 21: 4
        case 23: 5
        case 22: 6
        case 26: 7
        case 28: 8
        case 25: 9
        default: nil
        }
    }

    private func startNSEventFallbackMonitors() {
        guard globalKeyMonitor == nil else { return }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 {
                self?.onEscape?()
            } else {
                if let slot = self?.modeSlot(from: event.keyCode, flags: event.modifierFlags),
                   self?.shouldHandleModeHotkeys?() != false,
                   self?.onModeHotkey?(slot) == true {
                    return
                }
                _ = self?.handleArrowKey(code: event.keyCode, flags: event.modifierFlags)
            }
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 {
                self?.onEscape?()
                return event
            }
            if let slot = self?.modeSlot(from: event.keyCode, flags: event.modifierFlags),
               self?.shouldHandleModeHotkeys?() != false,
               self?.onModeHotkey?(slot) == true {
                return nil
            }
            if self?.handleArrowKey(code: event.keyCode, flags: event.modifierFlags) == true {
                return nil
            }
            return event
        }
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleOptionState(event.modifierFlags.contains(.option))
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleOptionState(event.modifierFlags.contains(.option))
            return event
        }
    }

    private func stopNSEventFallbackMonitors() {
        [globalKeyMonitor, localKeyMonitor, globalFlagsMonitor, localFlagsMonitor].forEach { monitor in
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        globalKeyMonitor = nil
        localKeyMonitor = nil
        globalFlagsMonitor = nil
        localFlagsMonitor = nil
    }
}
