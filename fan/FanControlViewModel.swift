//
//  FanControlViewModel.swift
//  ffan
//
//  Created by mohamad on 11/1/2026.
//  Fixed bindings and added proper state management
//

import Foundation
import Combine
import SwiftUI
import AppKit

@MainActor
class FanControlViewModel: ObservableObject {
    // Temperature readings
    @Published var cpuTemperature: Double?
    @Published var gpuTemperature: Double?
    
    // Fan data
    @Published var fanSpeeds: [Int] = []
    @Published var fanMinSpeeds: [Int] = []
    @Published var fanMaxSpeeds: [Int] = []
    @Published var numberOfFans: Int = 0
    @Published var currentFanSpeed: Int = 0
    
    // Control state
    @Published var controlMode: ControlMode = .manual
    @Published var manualSpeed: Int = 2000
    @Published var autoThreshold: Double = 60.0
    @Published var autoMaxSpeed: Int = 4500
    @Published var autoAggressiveness: Double = 1.5

    /// When true (manual mode), each fan uses its own target RPM from `manualSpeeds`.
    @Published var perFanManualControl: Bool = false
    @Published var manualSpeeds: [Int] = []
    
    // Status
    @Published var isMonitoring = false
    @Published var hasAccess = false
    @Published var lastError: String?
    @Published var statusMessage: String = ""
    @Published var launchAtLogin = false
    @Published var lastWriteSuccess = false
    
    // Settings
    @Published var statusBarDisplayMode: String = "temperature"
    @Published var enableNotifications = true
    @Published var highTempAlert: Double = 85.0
    @Published var autoSwitchMode = false
    
    // Demo mode
    @Published var isDemoMode = false
    
    private let systemMonitor = SystemMonitor()
    let fanController: FanController
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        self.fanController = FanController(systemMonitor: systemMonitor)
        self.launchAtLogin = LaunchAtLoginManager.shared.isEnabled
        self.isDemoMode = UserDefaults.standard.bool(forKey: "showDemoData")
        
        // Load settings from UserDefaults
        self.statusBarDisplayMode = UserDefaults.standard.string(forKey: "statusBarDisplayMode") ?? "temperature"
        self.enableNotifications = UserDefaults.standard.object(forKey: "enableNotifications") as? Bool ?? true
        self.highTempAlert = UserDefaults.standard.double(forKey: "highTempAlert") > 0 ? UserDefaults.standard.double(forKey: "highTempAlert") : 85.0
        self.autoSwitchMode = UserDefaults.standard.object(forKey: "autoSwitchMode") as? Bool ?? false
        
        setupBindings()
        setupSettingsObservers()
        setupSleepWakeNotifications()
    }
    
    private func setupSettingsObservers() {
        // Observe status bar display mode changes
        $statusBarDisplayMode
            .sink { [weak self] mode in
                // Update status bar manager with new display mode
                // This will be accessed via AppDelegate reference if available
            }
            .store(in: &cancellables)
        
        // Observe high temp alert for notifications
        $highTempAlert
            .sink { [weak self] temp in
                guard let self = self else { return }
                if self.enableNotifications, let cpuTemp = self.cpuTemperature, cpuTemp > temp {
                    self.showHighTempNotification(cpuTemp)
                }
            }
            .store(in: &cancellables)
        
        // Observe auto switch mode for automatic mode activation
        $cpuTemperature
            .sink { [weak self] temp in
                guard let self = self else { return }
                if self.autoSwitchMode, let cpuTemp = temp, cpuTemp > self.highTempAlert {
                    if self.controlMode != .automatic {
                        print("Auto-switching to automatic mode due to high temperature: \(cpuTemp)°C")
                        self.setControlMode(.automatic)
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    private func showHighTempNotification(_ temperature: Double) {
        let notification = NSUserNotification()
        notification.title = "High Temperature Alert"
        notification.subtitle = String(format: "CPU temperature: %.1f°C", temperature)
        notification.informativeText = "Consider switching to automatic fan control or check your system."
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
    }
    
    private func setupBindings() {
        // System monitor bindings
        systemMonitor.$cpuTemperature
            .receive(on: DispatchQueue.main)
            .assign(to: &$cpuTemperature)
        
        systemMonitor.$gpuTemperature
            .receive(on: DispatchQueue.main)
            .assign(to: &$gpuTemperature)
        
        systemMonitor.$fanSpeeds
            .receive(on: DispatchQueue.main)
            .assign(to: &$fanSpeeds)
        
        systemMonitor.$fanMinSpeeds
            .receive(on: DispatchQueue.main)
            .assign(to: &$fanMinSpeeds)
        
        systemMonitor.$fanMaxSpeeds
            .receive(on: DispatchQueue.main)
            .assign(to: &$fanMaxSpeeds)
        
        systemMonitor.$numberOfFans
            .receive(on: DispatchQueue.main)
            .assign(to: &$numberOfFans)
        
        systemMonitor.$isMonitoring
            .receive(on: DispatchQueue.main)
            .assign(to: &$isMonitoring)
        
        systemMonitor.$hasAccess
            .receive(on: DispatchQueue.main)
            .assign(to: &$hasAccess)
        
        systemMonitor.$lastError
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastError)
        
        // Fan controller bindings
        fanController.$mode
            .receive(on: DispatchQueue.main)
            .assign(to: &$controlMode)
        
        fanController.$manualSpeed
            .receive(on: DispatchQueue.main)
            .assign(to: &$manualSpeed)

        fanController.$perFanManualControl
            .receive(on: DispatchQueue.main)
            .assign(to: &$perFanManualControl)

        fanController.$manualSpeeds
            .receive(on: DispatchQueue.main)
            .assign(to: &$manualSpeeds)
        
        fanController.$autoThreshold
            .receive(on: DispatchQueue.main)
            .assign(to: &$autoThreshold)
        
        fanController.$autoMaxSpeed
            .receive(on: DispatchQueue.main)
            .assign(to: &$autoMaxSpeed)
        
        fanController.$autoAggressiveness
            .receive(on: DispatchQueue.main)
            .assign(to: &$autoAggressiveness)
        
        fanController.$statusMessage
            .receive(on: DispatchQueue.main)
            .assign(to: &$statusMessage)
        
        fanController.$lastWriteSuccess
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastWriteSuccess)
        
        // Average reported RPM across detected fans (display / menu bar).
        Publishers.CombineLatest($fanSpeeds, $numberOfFans)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] speeds, n in
                guard let self = self else { return }
                guard !speeds.isEmpty, n > 0 else {
                    self.currentFanSpeed = 0
                    return
                }
                let slice = min(speeds.count, Int(n))
                let sum = speeds.prefix(slice).reduce(0, +)
                self.currentFanSpeed = Int(round(Double(sum) / Double(slice)))
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Monitoring Control
    
    private func setupSleepWakeNotifications() {
        // Register for sleep notification
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        
        // Register for wake notification
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        
        // Register for screen lock notification (screen saver/display sleep)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        
        // Register for screen wake notification
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        
        // Register for session unlock notification (user logged back in)
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )
        
        // Also register for session active notification
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
    }
    
    private func removeSleepWakeNotifications() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    
    @objc private func systemWillSleep() {
        print("FanControl: System going to sleep/lock - restoring system control")
        fanController.restoreAutomaticControl()
    }
    
    @objc private func systemDidWake() {
        print("FanControl: System woke up - reapplying user settings")
        // Give the system a moment to stabilize
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.fanController.reapplySettings()
        }
    }
    
    // MARK: - Monitoring Control
    
    func startMonitoring() {
        systemMonitor.startMonitoring()
    }
    
    func stopMonitoring() {
        systemMonitor.stopMonitoring()
    }
    
    // MARK: - Fan Control
    
    func setManualSpeed(_ speed: Int) {
        fanController.setManualSpeed(speed)
    }

    func setPerFanManualControl(_ enabled: Bool) {
        fanController.setPerFanManualControl(enabled)
    }

    func setManualSpeedForFan(index: Int, speed: Int) {
        fanController.setManualSpeed(fanIndex: index, speed: speed)
    }

    /// Lower bound for unified sliders when SMC minima are known.
    var effectiveUnifiedMinRPM: Int {
        guard !fanMinSpeeds.isEmpty else { return FanRPMBounds.fallbackMinWhenSMCUnreadable }
        return fanMinSpeeds.min() ?? FanRPMBounds.fallbackMinWhenSMCUnreadable
    }

    /// Upper bound for unified sliders when SMC maxima are known.
    var effectiveUnifiedMaxRPM: Int {
        guard !fanMaxSpeeds.isEmpty else { return FanRPMBounds.fallbackMaxWhenSMCUnreadable }
        return fanMaxSpeeds.max() ?? FanRPMBounds.fallbackMaxWhenSMCUnreadable
    }

    func minRPM(atFan index: Int) -> Int {
        guard index >= 0, index < fanMinSpeeds.count else { return FanRPMBounds.fallbackMinWhenSMCUnreadable }
        return fanMinSpeeds[index]
    }

    func maxRPM(atFan index: Int) -> Int {
        guard index >= 0, index < fanMaxSpeeds.count else { return FanRPMBounds.fallbackMaxWhenSMCUnreadable }
        return fanMaxSpeeds[index]
    }

    /// Mean fan utilization in \([0,100]\) using each fan's SMC min/max span.
    var averageFanLoadPercent: Int {
        guard !fanSpeeds.isEmpty else {
            let ref = fanMaxSpeeds.max() ?? FanRPMBounds.fallbackMaxWhenSMCUnreadable
            guard ref > 0 else { return 0 }
            return min(100, max(0, Int(round(Double(currentFanSpeed) / Double(ref) * 100))))
        }
        var sum = 0.0
        var count = 0
        for i in 0..<fanSpeeds.count {
            let mn = i < fanMinSpeeds.count ? fanMinSpeeds[i] : FanRPMBounds.fallbackMinWhenSMCUnreadable
            guard i < fanMaxSpeeds.count else { continue }
            let mx = fanMaxSpeeds[i]
            guard mx > mn else { continue }
            let p = Double(fanSpeeds[i] - mn) / Double(mx - mn)
            sum += min(1.0, max(0.0, p))
            count += 1
        }
        guard count > 0 else { return 0 }
        return Int(min(100, max(0, round(sum / Double(count) * 100))))
    }
    
    func setControlMode(_ mode: ControlMode) {
        fanController.setMode(mode)
    }
    
    func resetToSystemControl() {
        fanController.resetToSystemControl()
    }
    
    func setAutoThreshold(_ threshold: Double) {
        fanController.setAutoThreshold(threshold)
    }
    
    func setAutoMaxSpeed(_ speed: Int) {
        fanController.setAutoMaxSpeed(speed)
    }
    
    func setAutoAggressiveness(_ value: Double) {
        fanController.setAutoAggressiveness(value)
    }
    
    // MARK: - Access Control
    
    func checkAccess() -> Bool {
        return systemMonitor.checkAccess()
    }
    
    func requestPermissions() {
        // Permissions are handled via smc-helper installation
        // The helper is installed from the app's "Install Helper" prompt
        PermissionsManager.shared.checkInstallation()
    }
    
    // MARK: - Demo Mode
    
    func toggleDemoMode() {
        isDemoMode.toggle()
        UserDefaults.standard.set(isDemoMode, forKey: "showDemoData")
        
        // Restart monitoring to apply demo mode
        stopMonitoring()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.startMonitoring()
        }
    }
    
    // MARK: - Helper Functions
    
    func getMaxTemperature() -> Double {
        return max(cpuTemperature ?? 0, gpuTemperature ?? 0)
    }
    
    func getTemperatureColor() -> Color {
        let maxTemp = getMaxTemperature()
        if maxTemp <= 0 {
            return .gray
        } else if maxTemp < 50 {
            return .blue
        } else if maxTemp < 70 {
            return .yellow
        } else if maxTemp < 85 {
            return .orange
        } else {
            return .red
        }
    }
    
    func getTemperatureStatus() -> String {
        let maxTemp = getMaxTemperature()
        if maxTemp <= 0 {
            return "No data"
        } else if maxTemp < 50 {
            return "Cool"
        } else if maxTemp < 70 {
            return "Normal"
        } else if maxTemp < 85 {
            return "Warm"
        } else {
            return "Hot!"
        }
    }
    
    func getFanSpeedPercent() -> Double {
        guard numberOfFans > 0, !fanSpeeds.isEmpty else { return 0 }

        var sum = 0.0
        var count = 0
        let n = min(numberOfFans, fanSpeeds.count, fanMaxSpeeds.count)

        for i in 0..<n {
            let mn = i < fanMinSpeeds.count ? fanMinSpeeds[i] : fanMinSpeeds.first ?? FanRPMBounds.fallbackMinWhenSMCUnreadable
            let mx = fanMaxSpeeds[i]
            guard mx > mn else { continue }
            let p = Double(fanSpeeds[i] - mn) / Double(mx - mn)
            sum += min(1.0, max(0.0, p))
            count += 1
        }

        guard count > 0 else { return 0 }
        let avg = sum / Double(count)
        if avg.isNaN || avg.isInfinite { return 0 }
        return min(1.0, max(0.0, avg))
    }
}
