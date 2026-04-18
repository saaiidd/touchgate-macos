import Foundation
import LocalAuthentication

// Stateless — a fresh LAContext is created for every authentication request.
// @unchecked Sendable is safe here because there are no stored mutable properties.
final class AuthenticationManager: @unchecked Sendable {

    enum AuthError: Error, LocalizedError {
        case userCancelled
        case systemCancelled
        case biometryLockout
        case noPasscode
        case underlying(Error)

        var errorDescription: String? {
            switch self {
            case .userCancelled:    return "Authentication was cancelled."
            case .systemCancelled:  return "Authentication was interrupted by the system."
            case .biometryLockout:  return "Touch ID is locked. Please use your password."
            case .noPasscode:       return "No passcode is set on this device."
            case .underlying(let e): return e.localizedDescription
            }
        }
    }

    // SECURITY: Uses .deviceOwnerAuthentication so password is always available as fallback.
    // The system handles all biometric UI — we never build custom auth screens.
    func authenticate(reason: String) async throws -> Bool {
        let context = LAContext()

        return try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
                if let error {
                    continuation.resume(throwing: Self.mapError(error))
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    private static func mapError(_ error: Error) -> AuthError {
        guard let laError = error as? LAError else {
            return .underlying(error)
        }
        switch laError.code {
        case .userCancel:               return .userCancelled
        case .systemCancel:             return .systemCancelled
        case .biometryLockout:          return .biometryLockout
        case .passcodeNotSet:           return .noPasscode
        default:                        return .underlying(laError)
        }
    }
}
