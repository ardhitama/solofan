//
//  PermissionsManager.swift
//  ffan
//
//  Created by mohamad on 11/1/2026.
//  Manages installation of the helper tool
//

import Foundation
import Security
import AppKit
import Combine

class PermissionsManager: ObservableObject {
    static let shared = PermissionsManager()
    
    @Published var isHelperInstalled = false
    /// The installed helper differs from the one bundled with this app.
    @Published var isHelperOutdated = false
    
    /// sudoers grants passwordless root to whatever file sits at this path, so
    /// every directory on it must be writable only by root. /usr/local/bin is
    /// not safe for this: Homebrew makes it user-writable on Intel Macs.
    nonisolated static let helperPath = "/Library/PrivilegedHelperTools/solofan-smc-helper"
    /// Earlier releases installed here (setuid root via scripts/install.sh).
    nonisolated private static let legacyHelperPath = "/usr/local/bin/smc-helper"
    nonisolated private static let sudoersPath = "/etc/sudoers.d/smc-fan-helper"
    
    private init() {
        checkInstallation()
    }
    
    func checkInstallation() {
        // Run on background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let fileManager = FileManager.default
            let helperExists = fileManager.fileExists(atPath: Self.helperPath)
            
            if !helperExists {
                DispatchQueue.main.async {
                    self.isHelperInstalled = false
                    self.isHelperOutdated = false
                }
                return
            }
            
            let bundledPath = Bundle.main.url(forResource: "smc-helper", withExtension: nil)?.path
            let outdated = Self.helperNeedsUpdate(installedPath: Self.helperPath, bundledPath: bundledPath)
            
            // If helper exists, assume it's installed (sudoers verification can be flaky from GUI apps)
            // The actual passwordless sudo will be tested when FanController runs
            DispatchQueue.main.async {
                self.isHelperInstalled = true
                self.isHelperOutdated = outdated
            }
        }
    }
    
    private func verifySudoAccess() -> Bool {
        // This check can fail from sandboxed GUI apps even when sudoers is correct
        // So we just check if helper binary exists and trust the installation
        return FileManager.default.fileExists(atPath: Self.helperPath)
    }
    
    func installHelper(completion: @escaping (Bool, String?) -> Void) {
        // 1. Locate the helper in the App Bundle
        guard let bundledHelperURL = Bundle.main.url(forResource: "smc-helper", withExtension: nil) else {
            completion(false, "App Bundle missing smc-helper. Re-build app.")
            return
        }
        
        // 2. Construct the installation script
        // We handle everything in one root shell script behind a single prompt.
        let script = Self.administratorScript(Self.installCommand(bundledHelperPath: bundledHelperURL.path))
        
        // 3. Execute
        DispatchQueue.global(qos: .userInitiated).async {
             var error: NSDictionary?
             if let scriptObject = NSAppleScript(source: script) {
                 _ = scriptObject.executeAndReturnError(&error)
                 
                 DispatchQueue.main.async {
                     if let error = error {
                         let msg = error["NSAppleScriptErrorMessage"] as? String ?? "Unknown error"
                         completion(false, msg)
                     } else {
                         self.checkInstallation() // Refresh state
                         completion(true, nil)
                     }
                 }
             } else {
                 DispatchQueue.main.async {
                     completion(false, "Failed to create installation script")
                 }
             }
        }
    }
    
    /// Whether the root-owned helper differs from the copy bundled with this
    /// app. An app update can ship a fixed helper, but the installed copy only
    /// changes when the user reinstalls it, so a difference asks for an update.
    nonisolated static func helperNeedsUpdate(installedPath: String, bundledPath: String?) -> Bool {
        // Never prompt to install a bundled helper whose signature is broken.
        guard let bundledPath, let bundledHash = codeHash(atPath: bundledPath) else { return false }
        // A missing, unsigned, or tampered installed helper has no hash: repair it.
        return codeHash(atPath: installedPath) != bundledHash
    }
    
    /// CDHash of validly signed code at `path`, or nil. It covers the code and
    /// signing identity but not the signing time, so re-signing an unchanged
    /// helper for each release does not trigger an update prompt.
    nonisolated static func codeHash(atPath path: String) -> Data? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess,
              let code,
              SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, [], &info) == errSecSuccess else { return nil }
        return (info as? [String: Any])?[kSecCodeInfoUnique as String] as? Data
    }
    
    /// Root shell script that installs the bundled helper, points the sudoers
    /// rule at it, and removes the legacy /usr/local/bin helper.
    nonisolated static func installCommand(bundledHelperPath: String) -> String {
        // Every interpolated value is shell-quoted: the bundle path is
        // user-controlled (the app can live anywhere) and runs as root here.
        let helper = shellQuoted(helperPath)
        let rule = shellQuoted("%admin ALL=(root) NOPASSWD: \(helperPath)")
        return [
            "set -e",
            "mkdir -p \(shellQuoted((helperPath as NSString).deletingLastPathComponent))",
            "install -o root -g wheel -m 755 \(shellQuoted(bundledHelperPath)) \(helper)",
            // Validate the rule before it goes live: a malformed file in
            // sudoers.d breaks sudo for the whole system.
            "rule=$(mktemp)",
            "trap 'rm -f \"$rule\"' EXIT",
            "printf '%s\\n' \(rule) > \"$rule\"",
            "visudo -c -q -f \"$rule\"",
            "mkdir -p /etc/sudoers.d",
            "install -o root -g wheel -m 440 \"$rule\" \(shellQuoted(sudoersPath))",
            "rm -f \(shellQuoted(legacyHelperPath))",
        ].joined(separator: "\n")
    }
    
    /// Single-quotes `value` for /bin/sh so it stays one literal word, even if
    /// it contains spaces, quotes, or `$`.
    nonisolated static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
    
    /// AppleScript source that runs `command` with /bin/sh as root after an
    /// admin password prompt.
    nonisolated static func administratorScript(_ command: String) -> String {
        let literal = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(literal)\" with administrator privileges"
    }
}
