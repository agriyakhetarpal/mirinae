// SPDX-License-Identifier: Apache-2.0
import Foundation

/// One-byte message identifier. Unknown IDs stay representable.
public struct MessageID: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UInt8

    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public init(_ rawValue: UInt8) { self.rawValue = rawValue }

    public var name: String { MessageID.names[rawValue] ?? "UNKNOWN_\(rawValue)" }
    public var hex: String { String(format: "0x%02X", rawValue) }
    public var description: String { "\(name) (\(hex))" }

    // Debug and diagnostics
    public static let hiddenCmdMode = MessageID(18)
    public static let hiddenCmdData = MessageID(19)
    public static let setDebugMode = MessageID(32)
    public static let debugSku = MessageID(34)
    public static let readWaterDetectionHistory = MessageID(35)
    public static let debugGetVersion = MessageID(36)
    public static let debugGetAllData = MessageID(38)
    public static let debugBuildInfo = MessageID(40)
    public static let debugSerialNumber = MessageID(41)
    public static let usageReport = MessageID(64)
    public static let meteringReport = MessageID(65)
    public static let acknowledgement = MessageID(66)
    public static let reset = MessageID(80)
    public static let response = MessageID(81)
    public static let reboot = MessageID(82)
    public static let powerOff = MessageID(83)
    public static let statusAlert = MessageID(87)

    // Status
    public static let statusUpdated = MessageID(96)
    public static let extendedStatusUpdated = MessageID(97)
    public static let connectionUpdated = MessageID(98)
    public static let versionInfo = MessageID(99)
    public static let setBixbyKeyword = MessageID(102)
    public static let pauseMediaWhenOneBudRemoved = MessageID(108)
    public static let setCallPathControl = MessageID(110)
    public static let setAncWithOneEarbud = MessageID(111)
    public static let mainChange = MessageID(112)
    public static let pairingMode = MessageID(114)
    public static let autoSwitchAudioOutput = MessageID(115)
    public static let multipointInfo = MessageID(118)

    // Noise control and ambient sound
    public static let noiseControlsUpdate = MessageID(119)
    public static let noiseControls = MessageID(120)
    public static let setTouchAndHoldNoiseControls = MessageID(121)
    public static let setDetectConversations = MessageID(122)
    public static let setDetectConversationsDuration = MessageID(123)
    public static let setSpatialAudio = MessageID(124)
    public static let setSpeakSeamlessly = MessageID(125)
    public static let setAmplifyAmbientSound = MessageID(126)
    public static let setAmbientMode = MessageID(128)
    public static let ambientModeUpdated = MessageID(129)
    public static let customizeAmbientSound = MessageID(130)
    public static let noiseReductionLevel = MessageID(131)
    public static let ambientVolume = MessageID(132)
    public static let adjustSoundSync = MessageID(133)
    public static let equalizer = MessageID(134)
    public static let gameMode = MessageID(135)
    public static let managerInfo = MessageID(136)
    public static let customEqualizeSend = MessageID(137)
    public static let setInBandRingtone = MessageID(138)
    public static let setSidetone = MessageID(139)
    public static let tapTestMode = MessageID(141)
    public static let setHearingEnhancements = MessageID(143)

    // Touch
    public static let lockTouchpad = MessageID(144)
    public static let touchUpdated = MessageID(145)
    public static let setTouchpadOption = MessageID(146)
    public static let setTouchpadOtherOption = MessageID(147)
    public static let batteryType = MessageID(148)
    public static let outsideDoubleTap = MessageID(149)
    public static let extraHighAmbient = MessageID(150)
    public static let setVoiceWakeUp = MessageID(151)
    public static let setNoiseReduction = MessageID(152)
    public static let voiceWakeUpLanguage = MessageID(153)
    public static let voiceWakeUpEvent = MessageID(154)
    public static let noiseReductionModeUpdate = MessageID(155)
    public static let checkTheFitOfEarbuds = MessageID(157)
    public static let checkTheFitOfEarbudsResult = MessageID(158)
    public static let passThrough = MessageID(159)

    // Find my earbuds
    public static let findMyEarbudsStart = MessageID(160)
    public static let findMyEarbudsStop = MessageID(161)
    public static let muteEarbud = MessageID(162)
    public static let muteEarbudStatusUpdated = MessageID(163)
    public static let findMyEarbudsOnWearingStart = MessageID(166)
    public static let updateTime = MessageID(167)
    public static let selfTest = MessageID(171)
    public static let setFmmConfig = MessageID(172)
    public static let getFmmConfig = MessageID(173)
    public static let setSeamlessConnection = MessageID(175)

    // Spatial audio and sensors
    public static let spatialAudioData = MessageID(194)
    public static let spatialAudioControl = MessageID(195)
    public static let setAdaptiveVolumeEnabled = MessageID(197)
    public static let overheat = MessageID(202)
    public static let cradleSerialNumber = MessageID(205)
    public static let socBatteryCycle = MessageID(206)
    public static let getPersonalName = MessageID(211)
    public static let adaptiveEqControl = MessageID(218)
    public static let adaptiveEqStatus = MessageID(219)
    public static let debugErrorCode = MessageID(241)
    public static let debugEvent = MessageID(242)

    public static let names: [UInt8: String] = [
        1: "UNK_SPP_ALT", 15: "HOT_COMMAND_MANAGE", 16: "SET_MODE_CHANGE", 17: "GET_MODE",
        18: "HIDDEN_CMD_MODE", 19: "HIDDEN_CMD_DATA", 21: "HIDDEN_FACTORYINFO_MODE1",
        22: "HIDDEN_FACTORYINFO_MODE2", 23: "HIDDEN_FACTORYINFO_MODE3", 32: "SET_DEBUG_MODE",
        33: "DEBUG_MODE_LOG", 34: "DEBUG_SKU", 35: "READ_WATER_DETECTION_HISTORY", 36: "DEBUG_GET_VERSION",
        38: "DEBUG_GET_ALL_DATA", 39: "UNKNOWN_39_DISCONNECT", 40: "DEBUG_BUILD_INFO", 41: "DEBUG_SERIAL_NUMBER",
        42: "ACC_SENSOR_LOGGING", 45: "TOUCH_ON_BUDS", 48: "LOG_COREDUMP_COMMIT_SUICIDE",
        49: "LOG_COREDUMP_DATA_SIZE", 50: "LOG_COREDUMP_DATA", 51: "LOG_COREDUMP_COMPLETE",
        52: "LOG_TRACE_START", 53: "LOG_TRACE_DATA", 54: "LOG_TRACE_COMPLETE", 55: "LOG_TRACE_ROLE_SWITCH",
        56: "LOG_COREDUMP_DATA_DONE", 57: "LOG_TRACE_DATA_DONE", 58: "LOG_SESSION_OPEN",
        59: "LOG_SESSION_CLOSE", 60: "LOG_GET_CONFIG", 61: "LOG_SET_CONFIG", 64: "USAGE_REPORT",
        65: "METERING_REPORT", 66: "UNIVERSAL_MSG_ID_ACKNOWLEDGEMENT", 67: "WRITE_PROPERTY",
        68: "READ_PROPERTY", 69: "NOTIFY_PROPERTY", 71: "USAGE_REPORT_V2", 72: "EXTRA_CLEAR_SOUND_CALL",
        74: "AGING_TEST_REPORT", 75: "ACT_TEST_CMD", 80: "RESET", 81: "RESP", 82: "REBOOT", 83: "POWEROFF",
        86: "RFTESTMODE", 87: "STATUS_ALERT", 96: "STATUS_UPDATED", 97: "EXTENDED_STATUS_UPDATED",
        98: "CONNECTION_UPDATED", 99: "VERSION_INFO", 100: "SET_HOT_COMMAND", 102: "SET_BIXBY_KEYWORD",
        103: "SET_HEARING_TEST_RESULT", 104: "VERSION_INFO_LONG", 105: "CUSTOM_EQUALIZE_RECV",
        108: "PAUSE_MEDIA_WHEN_ONE_BUD_REMOVED", 109: "AMBIENT_DURING_CALL_NOTI", 110: "SET_CALL_PATH_CONTROL",
        111: "SET_ANC_WITH_ONE_EARBUD", 112: "MAIN_CHANGE", 113: "PROFILE_CONTROL", 114: "PAIRING_MODE",
        115: "AUTO_SWITCH_AUDIO_OUTPUT", 118: "MULTIPOINT_INFO", 119: "NOISE_CONTROLS_UPDATE",
        120: "NOISE_CONTROLS", 121: "SET_TOUCH_AND_HOLD_NOISE_CONTROLS", 122: "SET_DETECT_CONVERSATIONS",
        123: "SET_DETECT_CONVERSATIONS_DURATION", 124: "SET_SPATIAL_AUDIO", 125: "SET_SPEAK_SEAMLESSLY",
        126: "SET_AMPLIFY_AMBIENT_SOUND", 128: "SET_AMBIENT_MODE", 129: "AMBIENT_MODE_UPDATED",
        130: "CUSTOMIZE_AMBIENT_SOUND", 131: "NOISE_REDUCTION_LEVEL", 132: "AMBIENT_VOLUME",
        133: "ADJUST_SOUND_SYNC", 134: "EQUALIZER", 135: "GAME_MODE", 136: "MANAGER_INFO",
        137: "CUSTOM_EQUALIZE_SEND", 138: "SET_IN_BAND_RINGTONE", 139: "SET_SIDETONE", 141: "TAP_TEST_MODE",
        142: "BUDS_LIGHTING_SYNC", 143: "SET_HEARING_ENHANCEMENTS", 144: "LOCK_TOUCHPAD", 145: "TOUCH_UPDATED",
        146: "SET_TOUCHPAD_OPTION", 147: "SET_TOUCHPAD_OTHER_OPTION", 148: "BATTERY_TYPE",
        149: "OUTSIDE_DOUBLE_TAP", 150: "EXTRA_HIGH_AMBIENT", 151: "SET_VOICE_WAKE_UP", 152: "SET_NOISE_REDUCTION",
        153: "VOICE_WAKE_UP_LANGUAGE", 154: "VOICE_WAKE_UP_EVENT", 155: "NOISE_REDUCTION_MODE_UPDATE",
        156: "VOICE_WAKE_UP_LISTENING_STATUS", 157: "CHECK_THE_FIT_OF_EARBUDS", 158: "CHECK_THE_FIT_OF_EARBUDS_RESULT",
        159: "PASS_THROUGH", 160: "FIND_MY_EARBUDS_START", 161: "FIND_MY_EARBUDS_STOP", 162: "MUTE_EARBUD",
        163: "MUTE_EARBUD_STATUS_UPDATED", 164: "VOICE_NOTI_STATUS", 165: "VOICE_NOTI_STOP",
        166: "FIND_MY_EARBUDS_ON_WEARING_START", 167: "UPDATE_TIME", 168: "START_VOICE_RECORD",
        169: "COUPLING_HELPER_READ", 170: "COUPLING_HELPER_WRITE", 171: "SELF_TEST", 172: "SET_FMM_CONFIG",
        173: "GET_FMM_CONFIG", 175: "SET_SEAMLESS_CONNECTION", 176: "FOTA_V1_SESSION", 177: "FOTA_V1_CONTROL",
        178: "FOTA_V1_DOWNLOAD_DATA", 179: "FOTA_V1_UPDATED", 180: "FOTA_DEVICE_INFO_SW_VERSION",
        181: "FOTA_BACKGROUND_NEED", 182: "FOTA_BACKGROUND_READY", 183: "FOTA_CHANGE_HALL_IC_STATUS",
        185: "FOTA_RESULT", 186: "FOTA_EMERGENCY", 187: "FOTA_OPEN", 188: "FOTA_CONTROL", 189: "FOTA_DOWNLOAD_DATA",
        190: "FOTA_UPDATE", 192: "UPDATE_VOICE_CMD", 193: "SET_VOICE_CMD", 194: "SPATIAL_AUDIO_DATA",
        195: "SPATIAL_AUDIO_CONTROL", 197: "SET_ADAPTIVE_VOLUME_ENABLED", 198: "NECK_POSTURE_CALI_DATA",
        199: "NECK_POSTURE_CONTROL", 200: "NECK_POSTURE_PHONE_DATA", 201: "NECK_POSTURE_SET", 202: "OVERHEAT",
        204: "HEARING_TEST_DATA", 205: "CRADLE_SERIAL_NUMBER", 206: "SOC_BATTERY_CYCLE",
        207: "RESET_BATTERY_SOC_CYCLE", 211: "GET_PERSONAL_NAME", 212: "UNK_DUMP_BONDED_DEVICES",
        214: "UNK_BONDED_DEVICES", 216: "BLUETERM_TX_TRAFFIC", 217: "ADAPTIVE_EQ_VOLUME_CONTROL",
        218: "ADAPTIVE_EQ_CONTROL", 219: "ADAPTIVE_EQ_STATUS", 222: "UASC_SIREN_DETECT", 233: "SD_SPEAKER_RES",
        234: "SD_MIC_RES", 241: "DEBUG_ERROR_CODE", 242: "DEBUG_EVENT", 250: "SD_BATTERY_STATUS",
        251: "SD_CABLE_CHARGING", 252: "SD_WIRELESS_CHARGING", 254: "SD_TOUCH_RES", 255: "SET_TOUCH_TYPE",
    ]
}
