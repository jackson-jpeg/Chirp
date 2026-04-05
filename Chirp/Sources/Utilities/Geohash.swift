import Foundation

/// Pure Swift geohash encoder/decoder.
///
/// Geohashes map 2-D coordinates onto a 1-D string using a base-32 alphabet.
/// They have the useful property that nearby points share a common prefix, which
/// makes them ideal for coarse-area routing in the dead-drop system.
enum Geohash {

    // MARK: - Alphabet

    /// Standard base-32 alphabet used by the geohash specification.
    private static let base32 = Array("0123456789bcdefghjkmnpqrstuvwxyz")

    /// Reverse lookup: character -> 5-bit value.
    private static let base32Decode: [Character: Int] = {
        var map: [Character: Int] = [:]
        for (i, c) in base32.enumerated() { map[c] = i }
        return map
    }()

    // MARK: - Encode

    /// Encode a coordinate to a geohash string at a given precision (1-12).
    ///
    /// Default precision 7 yields roughly 153 m x 153 m cells.
    static func encode(latitude: Double, longitude: Double, precision: Int = 7) -> String {
        let precision = max(1, min(precision, 12))

        var latRange = (-90.0, 90.0)
        var lonRange = (-180.0, 180.0)

        var hash = ""
        hash.reserveCapacity(precision)

        var isEven = true          // longitude first
        var bit = 0
        var charIndex = 0

        while hash.count < precision {
            if isEven {
                let mid = (lonRange.0 + lonRange.1) / 2
                if longitude >= mid {
                    charIndex |= (1 << (4 - bit))
                    lonRange.0 = mid
                } else {
                    lonRange.1 = mid
                }
            } else {
                let mid = (latRange.0 + latRange.1) / 2
                if latitude >= mid {
                    charIndex |= (1 << (4 - bit))
                    latRange.0 = mid
                } else {
                    latRange.1 = mid
                }
            }
            isEven.toggle()
            bit += 1

            if bit == 5 {
                hash.append(base32[charIndex])
                bit = 0
                charIndex = 0
            }
        }

        return hash
    }

    // MARK: - Decode

    /// Decode a geohash string back to the center coordinate of its cell.
    ///
    /// Returns `nil` for empty or invalid input.
    static func decode(_ hash: String) -> (latitude: Double, longitude: Double)? {
        guard !hash.isEmpty else { return nil }

        var latRange = (-90.0, 90.0)
        var lonRange = (-180.0, 180.0)
        var isEven = true

        for char in hash {
            guard let value = base32Decode[char] else { return nil }
            for bit in stride(from: 4, through: 0, by: -1) {
                let mask = 1 << bit
                if isEven {
                    let mid = (lonRange.0 + lonRange.1) / 2
                    if value & mask != 0 {
                        lonRange.0 = mid
                    } else {
                        lonRange.1 = mid
                    }
                } else {
                    let mid = (latRange.0 + latRange.1) / 2
                    if value & mask != 0 {
                        latRange.0 = mid
                    } else {
                        latRange.1 = mid
                    }
                }
                isEven.toggle()
            }
        }

        let latitude = (latRange.0 + latRange.1) / 2
        let longitude = (lonRange.0 + lonRange.1) / 2
        return (latitude, longitude)
    }

    // MARK: - Neighbors

    /// Return the 8 neighboring geohash cells (N, NE, E, SE, S, SW, W, NW).
    static func neighbors(of hash: String) -> [String] {
        guard !hash.isEmpty else { return [] }
        return CardinalDirection.allCases.compactMap { adjacent(hash, direction: $0) }
    }

    // MARK: - Internal neighbor logic

    /// Cardinal + ordinal directions for the 8-neighbor calculation.
    private enum CardinalDirection: CaseIterable {
        case north, northeast, east, southeast, south, southwest, west, northwest
    }

    /// Compute the adjacent geohash in a given direction.
    private static func adjacent(_ hash: String, direction: CardinalDirection) -> String? {
        switch direction {
        case .north:     return adjacentCardinal(hash, direction: .north)
        case .south:     return adjacentCardinal(hash, direction: .south)
        case .east:      return adjacentCardinal(hash, direction: .east)
        case .west:      return adjacentCardinal(hash, direction: .west)
        case .northeast:
            guard let n = adjacentCardinal(hash, direction: .north) else { return nil }
            return adjacentCardinal(n, direction: .east)
        case .northwest:
            guard let n = adjacentCardinal(hash, direction: .north) else { return nil }
            return adjacentCardinal(n, direction: .west)
        case .southeast:
            guard let s = adjacentCardinal(hash, direction: .south) else { return nil }
            return adjacentCardinal(s, direction: .east)
        case .southwest:
            guard let s = adjacentCardinal(hash, direction: .south) else { return nil }
            return adjacentCardinal(s, direction: .west)
        }
    }

    /// Internal axis direction for the neighbor lookup tables.
    private enum Axis { case north, south, east, west }

    // Neighbor and border lookup tables from the canonical geohash algorithm.
    // Index 0 = even-length hash, index 1 = odd-length hash.

    private static let neighborLookup: [Axis: (even: String, odd: String)] = [
        .north: ("p0r21436x8zb9dcf5h7kjnmqesgutwvy", "bc01fg45238967deuvhjyznpkmstqrwx"),
        .south: ("14365h7k9dcfesgujnmqp0r2twvyx8zb", "238967debc01afgh4567kmstuvhjyznpqrwx"),
        .east:  ("bc01fg45238967deuvhjyznpkmstqrwx", "p0r21436x8zb9dcf5h7kjnmqesgutwvy"),
        .west:  ("238967debc01afgh4567kmstuvhjyznpqrwx", "14365h7k9dcfesgujnmqp0r2twvyx8zb"),
    ]

    private static let borderLookup: [Axis: (even: String, odd: String)] = [
        .north: ("prxz",     "bcfguvyz"),
        .south: ("028b",     "0145hjnp"),
        .east:  ("bcfguvyz", "prxz"),
        .west:  ("0145hjnp", "028b"),
    ]

    /// Return the geohash cell adjacent to `hash` in the given cardinal direction.
    private static func adjacentCardinal(_ hash: String, direction: Axis) -> String? {
        guard !hash.isEmpty else { return nil }

        guard let lastChar = hash.last else { return nil }
        var parent = String(hash.dropLast())
        let isEven = hash.count % 2 == 0

        guard let neighborEntry = neighborLookup[direction],
              let borderEntry = borderLookup[direction] else { return nil }

        let border = isEven ? borderEntry.even : borderEntry.odd
        let neighbor = isEven ? neighborEntry.even : neighborEntry.odd

        // If the last character sits on this cell's border we must recurse
        // into the parent hash to find the correct neighbor prefix.
        if border.contains(lastChar) {
            guard !parent.isEmpty else { return nil }
            guard let adjacentParent = adjacentCardinal(parent, direction: direction) else { return nil }
            parent = adjacentParent
        }

        guard let index = neighbor.firstIndex(of: lastChar) else { return nil }
        let pos = neighbor.distance(from: neighbor.startIndex, to: index)
        return parent + String(base32[pos])
    }
}
