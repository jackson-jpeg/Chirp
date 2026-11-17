import SwiftUI
import UIKit

// Small shared pieces for the four covers over the tabs (Find, Meetup,
// RollCall, CatchUp). Named `Cover*` so they cannot collide with the shared kit.
// Their colors live in `Theme`.

/// A bird drawn at the file's own `translate(cx cy) scale(s)` inside a box of
/// `size`. The tail may poke past the box, as it does in the files.
/// `showLegs: false` hides the legs for files whose symbol has none.
struct CoverBirdCanvas: View {
    var palette: BirdPalette
    var size: CGSize
    var center: CGPoint
    var scale: CGFloat
    var showLegs = true

    private let bleed: CGFloat = 12

    var body: some View {
        Canvas { ctx, _ in
            ctx.translateBy(x: bleed, y: bleed)
            if !showLegs {
                ctx.clip(to: Path(CGRect(x: -bleed, y: -bleed, width: size.width + 2 * bleed,
                                         height: center.y + 99 * scale + bleed)))
            }
            BirdRenderer.draw(&ctx, palette: palette, beakOpen: false, center: center, scale: scale)
        }
        .frame(width: size.width + 2 * bleed, height: size.height + 2 * bleed)
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }
}

/// A round avatar: the palette's well and the bird at the file's transform.
struct CoverBirdDisc: View {
    var palette: BirdPalette
    var diameter: CGFloat
    var center: CGPoint
    var scale: CGFloat
    var well: Color? = nil

    var body: some View {
        ZStack {
            Circle().fill(well ?? Theme.well(palette))
            CoverBirdCanvas(palette: palette, size: CGSize(width: diameter, height: diameter),
                            center: center, scale: scale, showLegs: false)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

/// "< Chat", "< Talk": the files' plain back control (16 pt heavy, 44 pt tall).
struct CoverBackButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 20, height: 20)
                Text(title).font(.nunito(16, .heavy, relativeTo: .body))
            }
            .foregroundStyle(Theme.ink)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to \(title)")
    }
}

/// The round 44 pt close control (Find's "Stop finding").
struct CoverCloseButton: View {
    var label: String
    var tint: Color = Theme.ink
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// A small rounded status chip ("There", "OK · 10:12").
struct CoverChip: View {
    var text: String
    var fill: Color
    var foreground: Color
    var verticalPadding: CGFloat = 4
    var cornerRadius: CGFloat = 12

    var body: some View {
        Text(text)
            .font(.nunito(13, .black, relativeTo: .footnote))
            .foregroundStyle(foreground)
            .padding(.vertical, verticalPadding)
            .padding(.horizontal, 10)
            .background(fill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
