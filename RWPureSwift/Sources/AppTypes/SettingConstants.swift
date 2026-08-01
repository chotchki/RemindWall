//
//  SettingConstants.swift
//  RWPureSwift
//
//  Created by Christopher Hotchkiss on 2/14/26.
//

public let ALBUM_SETTING_KEY = "albumId"
public let CALENDAR_SETTING_KEY = "calendarId"
public let SCREEN_OFF_SETTING_KEY = "screenOffSchedule"
public let BUS_WINDOW_SETTING_KEY = "busWindow"
public let BUS_ALERTS_ENABLED_SETTING_KEY = "busAlertsEnabled"
// Traffic's own AlertWindow, synced like the bus one (TR1).
public let TRAFFIC_WINDOW_SETTING_KEY = "trafficWindow"
// HomeKit low-battery alerts (H1).
public let BATTERY_ALERTS_ENABLED_SETTING_KEY = "batteryAlertsEnabled"
public let BATTERY_THRESHOLD_SETTING_KEY = "batteryThresholdPercent"
// Synced descriptors for the device-local pair above; see Descriptors.swift.
public let ALBUM_DESCRIPTOR_SETTING_KEY = "albumDescriptor"
public let CALENDAR_DESCRIPTOR_SETTING_KEY = "calendarDescriptor"
