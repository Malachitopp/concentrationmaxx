import CommonCrypto
import Foundation

/// PBKDF2-HMAC-SHA256 through CommonCrypto.
enum PBKDF2 {
    enum Failure: Error, Equatable {
        case invalidParameters
        case derivationFailed(Int32)
    }

    static func sha256(password: Data, salt: Data, iterations: Int, keyLength: Int) throws -> Data {
        guard !password.isEmpty, !salt.isEmpty, iterations > 0, iterations <= Int(UInt32.max), keyLength > 0 else {
            throw Failure.invalidParameters
        }
        var derived = Data(count: keyLength)
        let status: Int32 = derived.withUnsafeMutableBytes { (derivedBytes: UnsafeMutableRawBufferPointer) -> Int32 in
            password.withUnsafeBytes { (passwordBytes: UnsafeRawBufferPointer) -> Int32 in
                salt.withUnsafeBytes { (saltBytes: UnsafeRawBufferPointer) -> Int32 in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: CChar.self),
                        password.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        keyLength
                    )
                }
            }
        }
        guard status == Int32(kCCSuccess) else {
            throw Failure.derivationFailed(status)
        }
        return derived
    }
}
