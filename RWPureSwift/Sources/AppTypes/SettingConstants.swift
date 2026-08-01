//
//  SettingConstants.swift
//  RWPureSwift
//
//  Created by Christopher Hotchkiss on 2/14/26.
//

public let ALBUM_SETTING_KEY = "albumId"
public let CALENDAR_SETTING_KEY = "calendarId"
public let SCREEN_OFF_SETTING_KEY = "screenOffSchedule"
// Legacy per-mode bus pair: SEED-ONLY since TR1.7 - the per-watch columns on
// MonitoredStop/MonitoredRoute own gating now; these exist so an upgrading
// kiosk can inherit its old configuration, nothing reads them at runtime.
public let BUS_WINDOW_SETTING_KEY = "busWindow"
public let BUS_ALERTS_ENABLED_SETTING_KEY = "busAlertsEnabled"
// The drive origin, synced (TR1). Windows are per-watch columns on the
// MonitoredStop/MonitoredRoute rows (TR1.7) - never per-mode keys.
public let HOME_ORIGIN_SETTING_KEY = "homeOrigin"
// HomeKit low-battery alerts (H1). Battery keeps per-mode settings - chips
// aren't per-watch, and the window is optional (nil = always show).
public let BATTERY_ALERTS_ENABLED_SETTING_KEY = "batteryAlertsEnabled"
public let BATTERY_THRESHOLD_SETTING_KEY = "batteryThresholdPercent"
public let BATTERY_WINDOW_SETTING_KEY = "batteryWindow"
public let BATTERY_IGNORED_SETTING_KEY = "batteryIgnoredAccessories"
// Synced descriptors for the device-local pair above; see Descriptors.swift.
public let ALBUM_DESCRIPTOR_SETTING_KEY = "albumDescriptor"
public let CALENDAR_DESCRIPTOR_SETTING_KEY = "calendarDescriptor"
