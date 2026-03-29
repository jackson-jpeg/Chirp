import Foundation

/// Shamir's Secret Sharing over GF(256).
/// Splits a secret into n shares where any k can reconstruct the original.
enum ShamirSplitter {

    struct Share: Codable, Sendable {
        let x: UInt8  // Share index (1-255, never 0)
        let y: Data    // Share data (same length as secret)
    }

    /// Split a secret into n shares with threshold k.
    /// Any k shares can reconstruct the secret. Fewer than k reveals nothing.
    static func split(secret: Data, threshold k: Int, shares n: Int) -> [Share]? {
        guard k >= 2, n >= k, n <= 255, !secret.isEmpty else { return nil }

        // Pre-generate random coefficients for all bytes at once to avoid
        // regenerating them per-share (coefficients must be the same for all shares
        // evaluating the same polynomial per byte position).
        var polynomials: [[UInt8]] = []
        for byteIndex in 0..<secret.count {
            var coefficients = [UInt8](repeating: 0, count: k)
            coefficients[0] = secret[byteIndex]
            for j in 1..<k {
                coefficients[j] = UInt8.random(in: 0...255)
            }
            polynomials.append(coefficients)
        }

        var result: [Share] = []

        for i in 1...n {
            let x = UInt8(i)
            var shareBytes = Data(count: secret.count)

            for byteIndex in 0..<secret.count {
                shareBytes[byteIndex] = evaluatePolynomial(polynomials[byteIndex], at: x)
            }

            result.append(Share(x: x, y: shareBytes))
        }

        return result
    }

    /// Reconstruct the secret from k or more shares using Lagrange interpolation in GF(256).
    static func reconstruct(shares: [Share]) -> Data? {
        guard !shares.isEmpty else { return nil }
        let secretLength = shares[0].y.count
        guard shares.allSatisfy({ $0.y.count == secretLength }) else { return nil }

        var secret = Data(count: secretLength)

        for byteIndex in 0..<secretLength {
            // Lagrange interpolation at x=0 to recover the constant term
            var value: UInt8 = 0

            for i in 0..<shares.count {
                let xi = shares[i].x
                let yi = shares[i].y[byteIndex]

                // Compute Lagrange basis polynomial L_i(0)
                var basis: UInt8 = 1
                for j in 0..<shares.count where j != i {
                    let xj = shares[j].x
                    // L_i(0) = product of (0 - xj) / (xi - xj) for j != i
                    // In GF(256): 0 - xj = xj (additive inverse = identity in GF(256))
                    let num = xj
                    let den = gf256Sub(xi, xj)
                    basis = gf256Mul(basis, gf256Div(num, den))
                }

                value = gf256Add(value, gf256Mul(yi, basis))
            }

            secret[byteIndex] = value
        }

        return secret
    }

    // MARK: - GF(256) Arithmetic

    // GF(256) with irreducible polynomial x^8 + x^4 + x^3 + x + 1 (0x11B)

    private static func evaluatePolynomial(_ coeffs: [UInt8], at x: UInt8) -> UInt8 {
        var result: UInt8 = 0
        var xPower: UInt8 = 1 // x^0 = 1

        for coeff in coeffs {
            result = gf256Add(result, gf256Mul(coeff, xPower))
            xPower = gf256Mul(xPower, x)
        }

        return result
    }

    private static func gf256Add(_ a: UInt8, _ b: UInt8) -> UInt8 { a ^ b }
    private static func gf256Sub(_ a: UInt8, _ b: UInt8) -> UInt8 { a ^ b } // Same as add in GF(256)

    private static func gf256Mul(_ a: UInt8, _ b: UInt8) -> UInt8 {
        guard a != 0 && b != 0 else { return 0 }
        return expTable[Int(logTable[Int(a)]) + Int(logTable[Int(b)])]
    }

    private static func gf256Div(_ a: UInt8, _ b: UInt8) -> UInt8 {
        guard b != 0 else { return 0 }
        guard a != 0 else { return 0 }
        return expTable[Int(logTable[Int(a)]) + 255 - Int(logTable[Int(b)])]
    }

    // Precomputed log/exp tables for GF(256) with generator 2 and polynomial 0x11B.
    // expTable has 512 entries so that (logA + logB) can index directly without modulo.
    private static let expTable: [UInt8] = {
        var table = [UInt8](repeating: 0, count: 512)
        var x: UInt16 = 1
        for i in 0..<255 {
            table[i] = UInt8(x)
            x = x << 1
            if x >= 256 { x ^= 0x11B }
        }
        // Duplicate the cycle for overflow-safe lookup
        for i in 255..<512 {
            table[i] = table[i - 255]
        }
        return table
    }()

    private static let logTable: [UInt8] = {
        var table = [UInt8](repeating: 0, count: 256)
        for i in 0..<255 {
            table[Int(expTable[i])] = UInt8(i)
        }
        return table
    }()
}
