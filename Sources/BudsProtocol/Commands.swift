// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Request builders. Payload layouts are in docs/protocol.md.
public enum Commands {
    // MARK: Session

    public static func managerInfo(samsungDevice: Bool = true, androidSDK: UInt8 = 34) -> SPPMessage {
        SPPMessage(id: .managerInfo, payload: [1, samsungDevice ? 1 : 2, androidSDK])
    }

    public static func updateTime(_ date: Date = Date(), timeZone: TimeZone = .current) -> SPPMessage {
        let millis = UInt64(date.timeIntervalSince1970 * 1000)
        let offset = Int32(timeZone.secondsFromGMT(for: date) * 1000)
        var payload: [UInt8] = []
        for i in 0..<8 { payload.append(UInt8((millis >> (8 * UInt64(i))) & 0xFF)) }
        let u = UInt32(bitPattern: offset)
        for i in 0..<4 { payload.append(UInt8((u >> (8 * UInt32(i))) & 0xFF)) }
        return SPPMessage(id: .updateTime, payload: payload)
    }

    // MARK: Sound

    public static func noiseControls(_ mode: NoiseControlMode) -> SPPMessage {
        SPPMessage(id: .noiseControls, payload: [mode.rawValue])
    }

    public static func noiseReduction(_ enabled: Bool) -> SPPMessage { flag(.setNoiseReduction, enabled) }

    public static func ambientMode(_ enabled: Bool) -> SPPMessage { flag(.setAmbientMode, enabled) }

    public static func ambientVolume(_ level: Int) -> SPPMessage {
        SPPMessage(id: .ambientVolume, payload: [UInt8(clamping: level)])
    }

    public static func extraHighAmbient(_ enabled: Bool) -> SPPMessage { flag(.extraHighAmbient, enabled) }

    public static func customizeAmbient(enabled: Bool, left: Int, right: Int, tone: Int) -> SPPMessage {
        SPPMessage(
            id: .customizeAmbientSound,
            payload: [enabled ? 1 : 0, UInt8(clamping: left), UInt8(clamping: right), UInt8(clamping: tone)])
    }

    public static func noiseReductionLevel(high: Bool) -> SPPMessage { flag(.noiseReductionLevel, high) }

    public static func noiseControlsWithOneEarbud(_ enabled: Bool) -> SPPMessage { flag(.setAncWithOneEarbud, enabled) }

    public static func equalizer(_ preset: EqualizerPreset) -> SPPMessage {
        SPPMessage(id: .equalizer, payload: [UInt8(preset.rawValue)])
    }

    public static func customEqualiser(_ gains: [Int]) -> SPPMessage {
        let bands = gains.prefix(9).map { UInt8(bitPattern: Int8(clamping: $0)) }
        return SPPMessage(id: .customEqualizeSend, payload: [UInt8(bands.count)] + bands)
    }

    public static let equalizerCustom = SPPMessage(id: .equalizer, payload: [7])

    public static func stereoBalance(_ value: Int) -> SPPMessage {
        SPPMessage(id: .setHearingEnhancements, payload: [UInt8(clamping: min(max(value, 0), 32))])
    }

    public static func sidetone(_ enabled: Bool) -> SPPMessage { flag(.setSidetone, enabled) }
    public static func adjustSoundSync(_ enabled: Bool) -> SPPMessage { flag(.adjustSoundSync, enabled) }
    public static func speakSeamlessly(_ enabled: Bool) -> SPPMessage { flag(.setSpeakSeamlessly, enabled) }
    public static func detectConversations(_ enabled: Bool) -> SPPMessage { flag(.setDetectConversations, enabled) }
    public static func detectConversationsDuration(_ index: Int) -> SPPMessage {
        SPPMessage(id: .setDetectConversationsDuration, payload: [UInt8(clamping: index)])
    }
    public static func extraClearCallSound(_ enabled: Bool) -> SPPMessage { flag(MessageID(72), enabled) }
    public static func passThrough(_ enabled: Bool) -> SPPMessage { flag(.passThrough, enabled) }
    public static func gameMode(_ enabled: Bool) -> SPPMessage { flag(.gameMode, enabled) }

    // MARK: Touch

    public static func touchActions(left: TouchAction, right: TouchAction, map: TouchMap) -> SPPMessage? {
        guard let l = map.byte(for: left), let r = map.byte(for: right) else { return nil }
        return SPPMessage(id: .setTouchpadOption, payload: [l, r])
    }

    public static func touchLock(
        lockAll: Bool, singleTap: Bool, doubleTap: Bool, tripleTap: Bool, touchHold: Bool,
        doubleTapForCalls: Bool?, touchHoldForCalls: Bool?
    ) -> SPPMessage {
        var payload: [UInt8] = [
            lockAll ? 0 : 1, singleTap ? 1 : 0, doubleTap ? 1 : 0, tripleTap ? 1 : 0, touchHold ? 1 : 0,
        ]
        if let doubleTapForCalls, let touchHoldForCalls {
            payload += [doubleTapForCalls ? 1 : 0, touchHoldForCalls ? 1 : 0]
        }
        return SPPMessage(id: .lockTouchpad, payload: payload)
    }

    public static func touchLock(_ locked: Bool) -> SPPMessage { flag(.lockTouchpad, locked) }

    public static func touchAndHoldNoiseControls(
        left: NoiseControlCycle, right: NoiseControlCycle?, model: BudsModel
    ) -> SPPMessage {
        func triple(_ c: NoiseControlCycle) -> [UInt8] {
            if model >= .buds3 {
                return [(c.noiseCancelling ? 8 : 0) | (c.off ? 4 : 0) | (c.ambientSound ? 1 : 0)]
            }
            return [c.noiseCancelling ? 1 : 0, c.ambientSound ? 1 : 0, c.off ? 1 : 0]
        }
        var payload = triple(left)
        if let right { payload += triple(right) }
        return SPPMessage(id: .setTouchAndHoldNoiseControls, payload: payload)
    }

    public static func outsideDoubleTap(_ enabled: Bool) -> SPPMessage { flag(.outsideDoubleTap, enabled) }

    // MARK: Connection and assistant

    // 0 means enabled on the wire.
    public static func seamlessConnection(_ enabled: Bool) -> SPPMessage { flag(.setSeamlessConnection, !enabled) }
    public static func callPathControl(_ enabled: Bool) -> SPPMessage { flag(.setCallPathControl, !enabled) }
    public static func voiceWakeUp(_ enabled: Bool) -> SPPMessage { flag(.setVoiceWakeUp, enabled) }
    public static func voiceWakeUpLanguage(_ code: Int) -> SPPMessage {
        SPPMessage(id: .voiceWakeUpLanguage, payload: [UInt8(clamping: code)])
    }
    public static func pauseWhenOneBudRemoved(_ enabled: Bool) -> SPPMessage {
        flag(.pauseMediaWhenOneBudRemoved, enabled)
    }

    public static let pairingMode = SPPMessage(id: .pairingMode)

    public static func switchMainBud(toLeft: Bool) -> SPPMessage {
        SPPMessage(id: .mainChange, payload: [toLeft ? 1 : 0])
    }

    // MARK: Find my earbuds

    public static func findMyEarbudsStart(ringWhileWearing: Bool) -> SPPMessage {
        SPPMessage(id: ringWhileWearing ? .findMyEarbudsOnWearingStart : .findMyEarbudsStart)
    }
    public static let findMyEarbudsStop = SPPMessage(id: .findMyEarbudsStop)
    public static func muteEarbuds(left: Bool, right: Bool) -> SPPMessage {
        SPPMessage(id: .muteEarbud, payload: [left ? 1 : 0, right ? 1 : 0])
    }

    // MARK: Diagnostics

    public static let debugSku = SPPMessage(id: .debugSku)
    public static let debugAllData = SPPMessage(id: .debugGetAllData)
    public static let debugBuildInfo = SPPMessage(id: .debugBuildInfo)
    public static let debugSerialNumber = SPPMessage(id: .debugSerialNumber)
    public static let batteryType = SPPMessage(id: .batteryType)
    public static let cradleSerialNumber = SPPMessage(id: .cradleSerialNumber)
    public static let batteryCycles = SPPMessage(id: .socBatteryCycle)
    public static let selfTest = SPPMessage(id: .selfTest)
    public static let versionInfo = SPPMessage(id: .versionInfo)
    public static func fitTest(_ running: Bool) -> SPPMessage { flag(.checkTheFitOfEarbuds, running) }

    public static let factoryReset = SPPMessage(id: .reset)

    // MARK: Head tracking sensor

    public static func spatialAudio(_ enabled: Bool) -> SPPMessage { flag(.setSpatialAudio, enabled) }
    public static func spatialControl(_ control: SpatialAudioControl) -> SPPMessage {
        SPPMessage(id: .spatialAudioControl, payload: [control.rawValue])
    }

    // MARK: Helpers

    public static func flag(_ id: MessageID, _ value: Bool) -> SPPMessage {
        SPPMessage(id: id, payload: [value ? 1 : 0])
    }
}
