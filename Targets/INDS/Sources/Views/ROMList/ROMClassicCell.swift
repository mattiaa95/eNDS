import SwiftUI

/// Classic-mode library card: a retro DS-cartridge silhouette (shell → label
/// sticker with the banner icon → game-code band → info row). Adapted from
/// iGBA's `ROMClassicCell`, simplified to one fixed DS-cartridge shell color
/// since — unlike iGBA's GBA/GBC/GB — there's only one platform here; the
/// game code takes the platform band's place instead (more DS-flavored than
/// a redundant "NDS" tag).
struct ROMClassicCell: View {
    let rom: ROMFile
    let onFavoriteToggle: () -> Void

    private let shellColor = Color(red: 0.16, green: 0.16, blue: 0.19)
    private let labelColor = Color(red: 0.24, green: 0.24, blue: 0.30)

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(shellColor)

                VStack(spacing: 0) {
                    // Top notch, DS cartridge-style.
                    HStack {
                        Spacer()
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.black.opacity(0.3))
                            .frame(width: 26, height: 6)
                        Spacer()
                    }
                    .padding(.top, 4)

                    ZStack {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(labelColor)

                        VStack(spacing: 4) {
                            ROMIconView(rom: rom, cornerRadius: 4)
                                .frame(height: 58)
                                .padding(.horizontal, 8)

                            Text(rom.displayName)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 4)
                        }
                        .padding(.vertical, 6)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 2)

                    Text(rom.gameCode)
                        .font(.system(size: 7, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.55))
                        .padding(.horizontal, 8)
                        .padding(.top, 4)

                    Spacer(minLength: 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.black.opacity(0.25))
                        .frame(height: 8)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 4)
                }
            }
            .aspectRatio(0.72, contentMode: .fit)
            .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)

            HStack(spacing: 4) {
                HStack(spacing: 2) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 7))
                    Text(rom.formattedPlayTime)
                        .font(.system(size: 8, weight: .medium))
                }
                .foregroundStyle(.secondary)

                Spacer()

                if rom.hasAnySaveState {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.green)
                }

                Button(action: onFavoriteToggle) {
                    Image(systemName: rom.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 10))
                        .foregroundStyle(rom.isFavorite ? .yellow : .gray.opacity(0.6))
                        .motionBounceSymbolEffect(value: rom.isFavorite)
                        // Same reason as ROMGridCell: a 10pt glyph inside the
                        // NavigationLink that opens the game, so a near-miss
                        // boots the emulator instead of toggling a star.
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(rom.isFavorite ? "Remove from Favorites" : "Add to Favorites")
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
        }
    }
}
