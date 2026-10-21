//
//  PopoverView.swift
//  ffan
//
//  Clean, organized UI with customizable widget dashboard.
//

import SwiftUI

struct PopoverView: View {
    @ObservedObject var viewModel: FanControlViewModel
    @ObservedObject var permissions = PermissionsManager.shared
    @ObservedObject var battery = BatteryMonitor.shared
    @ObservedObject private var dashboardStore = DashboardStore.shared
    var statusBarManager: StatusBarManager?

    @State private var showingQuitConfirm = false
    @State private var showingResetDashboardConfirm = false
    @State private var installError: String?
    @State private var isEditingDashboard = false

    var body: some View {
        VStack(spacing: 0) {
            headerView

            Divider()
                .padding(.horizontal)

            ScrollView {
                VStack(spacing: 14) {
                    if !permissions.isHelperInstalled || permissions.isHelperOutdated {
                        installHelperView
                    } else if !viewModel.hasAccess {
                        noAccessView
                    } else if viewModel.cpuTemperature == nil {
                        noDataView
                    } else {
                        DashboardGridView(
                            store: dashboardStore,
                            viewModel: viewModel,
                            battery: battery,
                            isEditing: $isEditingDashboard
                        )
                    }
                }
                .padding(.vertical, 12)
            }

            Divider()
                .padding(.horizontal)

            footerView
        }
        .frame(width: 340)
        .frame(minHeight: 480, maxHeight: 640)
        .background {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)

                LinearGradient(
                    colors: [Color.blue.opacity(0.03), Color.purple.opacity(0.02)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .onAppear {
            if viewModel.hasAccess && !viewModel.isMonitoring {
                viewModel.startMonitoring()
            }
            battery.startMonitoring()
        }
        .onDisappear {
            battery.stopMonitoring()
        }
        .onChange(of: battery.hasBattery) { _, hasBattery in
            if !hasBattery {
                dashboardStore.removeWidgets(ofKind: .batteryInfo)
            }
        }
        .alert("Reset dashboard?", isPresented: $showingResetDashboardConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    dashboardStore.resetToDefaults(hasBattery: battery.hasBattery)
                }
            }
        } message: {
            Text("Restore the default widget layout. Your custom arrangement will be lost.")
        }
        .alert("Quit SoloFan?", isPresented: $showingQuitConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Quit", role: .destructive) {
                quitApp()
            }
        } message: {
            Text("Fans will be set to automatic mode before quitting.")
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(viewModel.getTemperatureColor().opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: "fan.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(viewModel.getTemperatureColor())
                    .rotationEffect(.degrees(viewModel.currentFanSpeed > 0 ? 360 : 0))
                    .animation(
                        viewModel.currentFanSpeed > 0
                            ? .linear(duration: max(0.3, 3.0 - Double(viewModel.currentFanSpeed) / 2500)).repeatForever(autoreverses: false)
                            : .default,
                        value: viewModel.currentFanSpeed > 0
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("SoloFan")
                    .font(.system(size: 16, weight: .bold))

                Text(viewModel.getTemperatureStatus())
                    .font(.system(size: 11))
                    .foregroundColor(viewModel.getTemperatureColor())
            }

            Spacer()

            Button {
                AppDelegate.shared?.openSettings()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Settings")

            Button {
                showingQuitConfirm = true
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Quit App")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Install / error states

    private var installHelperView: some View {
        VStack(spacing: 8) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 32))
                .foregroundColor(.blue)

            Text(permissions.isHelperOutdated ? "Helper Update Required" : "Helper Tool Required")
                .font(.system(size: 14, weight: .semibold))

            Text(permissions.isHelperOutdated
                 ? "This version of SoloFan includes an updated helper tool. Update it to keep fan control working with the latest fixes."
                 : "To control fans without constant password prompts, a helper tool must be installed.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let error = installError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                installError = nil
                permissions.installHelper { success, error in
                    if !success {
                        installError = error ?? "Installation failed"
                    }
                }
            } label: {
                Text(permissions.isHelperOutdated ? "Update Helper" : "Install Helper")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .padding(.top, 8)
            .padding(.horizontal, 40)

            Text("Helper is installed to /Library/PrivilegedHelperTools")
                .font(.system(size: 9))
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding()
        .liquidGlass()
        .padding(.horizontal)
    }

    private var noAccessView: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundColor(.orange)

            Text("System Access Required")
                .font(.system(size: 14, weight: .semibold))

            Text("The app needs to access the System Management Controller (SMC) to read temperatures.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if let error = viewModel.lastError {
                Text(error)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding()
        .liquidGlass()
        .padding(.horizontal)
    }

    private var noDataView: some View {
        VStack(spacing: 8) {
            Image(systemName: "thermometer.medium.slash")
                .font(.system(size: 32))
                .foregroundColor(.orange)

            Text("No Temperature Data")
                .font(.system(size: 14, weight: .semibold))

            Text("SMC connected but no temperature readings available. This may happen on some Mac models.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .liquidGlass()
        .padding(.horizontal)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack(spacing: 8) {
            Picker("", selection: Binding(
                get: { viewModel.controlMode },
                set: { viewModel.setControlMode($0) }
            )) {
                Text("Manual").tag(ControlMode.manual)
                Text("Auto").tag(ControlMode.automatic)
            }
            .pickerStyle(.segmented)
            .frame(width: 140)
            .disabled(isEditingDashboard)

            Spacer()

            if isEditingDashboard {
                Button("Reset") {
                    showingResetDashboardConfirm = true
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.secondary)
                .help("Restore default widget layout")
            }

            Button(isEditingDashboard ? "Done" : "Edit") {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    isEditingDashboard.toggle()
                }
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .help(isEditingDashboard ? "Finish editing dashboard" : "Customize widgets")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func quitApp() {
        viewModel.resetToSystemControl()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApplication.shared.terminate(nil)
        }
    }
}

// MARK: - Info Row Helper View

struct InfoRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(color)
                .frame(width: 12)

            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundColor(.primary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Compact Info Item (Cold, Minimal)

struct CompactInfoItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 8))
                .foregroundColor(.secondary.opacity(0.7))
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.primary.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Power Card View

struct PowerCardView: View {
    let powerWatts: Double?
    let isCharging: Bool
    let isPluggedIn: Bool

    private var displayValue: String {
        if let power = powerWatts, power > 0.01 {
            return String(format: "%.1f", power)
        }
        return "--"
    }

    private var color: Color {
        if isCharging {
            return .green
        } else if let power = powerWatts {
            if power > 30 { return .red }
            if power > 20 { return .orange }
            if power > 10 { return .yellow }
        }
        return .blue
    }

    private var statusText: String {
        if isCharging { return "Charging" }
        if isPluggedIn { return "Plugged In" }
        return "Battery"
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: isCharging ? "bolt.fill" : "power")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(color.opacity(0.8))

                Text("Power")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                Spacer()

                Text(statusText)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(color)
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(displayValue)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [color, color.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Text("W")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(color.opacity(0.6))

                Spacer()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 4)

                    if let power = powerWatts, power > 0, geo.size.width > 0 {
                        let progress = min(1, power / 50.0)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                LinearGradient(
                                    colors: [color.opacity(0.6), color],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0, geo.size.width * progress), height: 4)
                            .animation(.easeInOut(duration: 0.3), value: power)
                    }
                }
            }
            .frame(height: 4)
        }
        .padding(12)
        .liquidGlass()
    }
}

#Preview {
    PopoverView(viewModel: FanControlViewModel())
        .background(Color.black)
}
