import AudioToolbox
import CoreAudio
import Foundation
import Observation

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let transportType: UInt32

    /// SF Symbol for this kind of output.
    var symbolName: String {
        switch transportType {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            if name.contains("AirPods Max") { return "airpodsmax" }
            if name.contains("AirPods Pro") { return "airpodspro" }
            if name.contains("AirPods") { return "airpods" }
            if name.contains("Beats") { return "beats.headphones" }
            return "headphones"
        case kAudioDeviceTransportTypeAirPlay:
            return "airplayaudio"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
            return "tv"
        case kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeFireWire, kAudioDeviceTransportTypeThunderbolt:
            return "hifispeaker"
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate:
            return "waveform"
        case kAudioDeviceTransportTypeBuiltIn:
            return name.localizedCaseInsensitiveContains("headphone") ? "headphones" : "laptopcomputer"
        default:
            return "speaker.wave.2.fill"
        }
    }

    var isBuiltInSpeaker: Bool {
        transportType == kAudioDeviceTransportTypeBuiltIn && !name.localizedCaseInsensitiveContains("headphone")
    }
}

/// Default output device, its volume/mute, and the list of output devices, via CoreAudio.
/// Everything is kept current with property listeners rather than polling.
@Observable
@MainActor
final class AudioController {
    private(set) var devices: [AudioDevice] = []
    private(set) var currentDevice: AudioDevice?
    private(set) var volume: Double = 0
    private(set) var isMuted = false
    /// False for devices with no software volume (HDMI, some USB DACs).
    private(set) var hasVolumeControl = false
    private(set) var hasMuteControl = false

    @ObservationIgnored private var listenedDeviceID: AudioDeviceID?
    @ObservationIgnored private var deviceListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    init() {
        addSystemListener(kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in self?.refreshDefaultDevice() }
        addSystemListener(kAudioHardwarePropertyDevices) { [weak self] in self?.refreshDevices() }
        refreshDevices()
        refreshDefaultDevice()
    }

    // MARK: - Actions

    func setVolume(_ value: Double) {
        guard let id = currentDevice?.id, hasVolumeControl else { return }
        var v = Float32(min(max(value, 0), 1))
        var addr = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)
        AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
        volume = Double(v)
        if isMuted && v > 0 { setMuted(false) }
    }

    func setMuted(_ muted: Bool) {
        guard let id = currentDevice?.id, hasMuteControl else { return }
        var v: UInt32 = muted ? 1 : 0
        var addr = Self.address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput)
        AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v)
        isMuted = muted
    }

    func toggleMute() { setMuted(!isMuted) }

    func setDefaultDevice(_ device: AudioDevice) {
        var id = device.id
        var addr = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
                                   UInt32(MemoryLayout<AudioDeviceID>.size), &id)
    }

    // MARK: - Refreshing

    private func refreshDevices() {
        devices = Self.outputDeviceIDs().compactMap(Self.makeDevice)
        if let id = currentDevice?.id { currentDevice = devices.first { $0.id == id } ?? currentDevice }
    }

    private func refreshDefaultDevice() {
        var id = AudioDeviceID(0)
        guard Self.get(AudioObjectID(kAudioObjectSystemObject), Self.address(kAudioHardwarePropertyDefaultOutputDevice), &id),
              id != kAudioObjectUnknown else {
            currentDevice = nil
            return
        }
        currentDevice = devices.first { $0.id == id } ?? Self.makeDevice(id)
        listenToDevice(id)
        refreshVolume()
    }

    private func refreshVolume() {
        guard let id = currentDevice?.id else { return }
        let volumeAddr = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)
        let muteAddr = Self.address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput)

        var v = Float32(0)
        hasVolumeControl = Self.isSettable(id, volumeAddr) && Self.get(id, volumeAddr, &v)
        volume = hasVolumeControl ? Double(v) : 1

        var m = UInt32(0)
        hasMuteControl = Self.isSettable(id, muteAddr) && Self.get(id, muteAddr, &m)
        isMuted = hasMuteControl && m != 0
    }

    private func listenToDevice(_ id: AudioDeviceID) {
        guard id != listenedDeviceID else { return }
        if let old = listenedDeviceID {
            for (addr, block) in deviceListeners {
                var a = addr
                AudioObjectRemovePropertyListenerBlock(old, &a, .main, block)
            }
        }
        deviceListeners.removeAll()
        listenedDeviceID = id

        for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute] {
            var addr = Self.address(selector, kAudioDevicePropertyScopeOutput)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.refreshVolume() }
            }
            if AudioObjectAddPropertyListenerBlock(id, &addr, .main, block) == noErr {
                deviceListeners.append((addr, block))
            }
        }
    }

    private func addSystemListener(_ selector: AudioObjectPropertySelector, _ handler: @escaping @MainActor () -> Void) {
        var addr = Self.address(selector)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main) { _, _ in
            MainActor.assumeIsolated { handler() }
        }
    }

    // MARK: - CoreAudio helpers

    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func get<T: BitwiseCopyable>(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress, _ value: inout T) -> Bool {
        var addr = address
        guard AudioObjectHasProperty(id, &addr) else { return false }
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr
    }

    private static func isSettable(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var addr = address
        guard AudioObjectHasProperty(id, &addr) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(id, &addr, &settable) == noErr && settable.boolValue
    }

    private static func outputDeviceIDs() -> [AudioDeviceID] {
        var addr = address(kAudioHardwarePropertyDevices)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.filter { id in
            var streamsAddr = address(kAudioDevicePropertyStreams, kAudioDevicePropertyScopeOutput)
            var streamsSize: UInt32 = 0
            AudioObjectGetPropertyDataSize(id, &streamsAddr, 0, nil, &streamsSize)
            var hidden = UInt32(0)
            _ = get(id, address(kAudioDevicePropertyIsHidden), &hidden)
            return streamsSize > 0 && hidden == 0
        }
    }

    private static func makeDevice(_ id: AudioDeviceID) -> AudioDevice? {
        var addr = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &name) == noErr,
              let cfName = name?.takeRetainedValue() else { return nil }
        var transport = UInt32(0)
        _ = get(id, address(kAudioDevicePropertyTransportType), &transport)
        return AudioDevice(id: id, name: cfName as String, transportType: transport)
    }
}
