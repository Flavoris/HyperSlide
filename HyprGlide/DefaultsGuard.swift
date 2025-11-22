//
//  DefaultsGuard.swift
//  HyprGlide
//
//  Provides a tiny helper for wrapping UserDefaults access in a try/catch style block
//  so we can gracefully fall back to safe defaults when persistence fails.
//

import Foundation

enum DefaultsGuardError: Error, LocalizedError {
    case missingValue(key: String)
    case invalidValue(key: String)
    
    var errorDescription: String? {
        switch self {
        case .missingValue(let key):
            return "Missing UserDefaults value for key \(key)"
        case .invalidValue(let key):
            return "Invalid UserDefaults value for key \(key)"
        }
    }
}

enum DefaultsGuard {
    @discardableResult
    static func read<T>(from defaults: UserDefaults,
                        _ block: (UserDefaults) throws -> T) -> T? {
        do {
            return try block(defaults)
        } catch {
#if DEBUG
            debugPrint("⚠️ UserDefaults read failure: \(error)")
#endif
            return nil
        }
    }
    
    @discardableResult
    static func write(on defaults: UserDefaults,
                      _ block: (UserDefaults) throws -> Void) -> Bool {
        do {
            try block(defaults)
            return true
        } catch {
#if DEBUG
            debugPrint("⚠️ UserDefaults write failure: \(error)")
#endif
            return false
        }
    }
}


