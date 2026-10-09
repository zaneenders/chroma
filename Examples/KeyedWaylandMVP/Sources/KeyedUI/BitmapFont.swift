// Small original 5x7 ASCII font, expanded into ordinary colored quads.
enum BitmapFont {
    static func bits(_ character: UInt8) -> UInt64 {
        let c = character >= 97 && character <= 122 ? character - 32 : character
        switch c {
        case 65: return 0x4631fc62e // A
        case 66: return 0x3e317c62f // B
        case 67: return 0x78210843e // C
        case 68: return 0x3e318c62f // D
        case 69: return 0x7c217843f // E
        case 70: return 0x4217843f // F
        case 71: return 0x7a31e843e // G
        case 72: return 0x4631fc631 // H
        case 73: return 0x7c842109f // I
        case 74: return 0x19284211c // J
        case 75: return 0x452519531 // K
        case 76: return 0x7c2108421 // L
        case 77: return 0x4631ad771 // M
        case 78: return 0x4631cd671 // N
        case 79: return 0x3a318c62e // O
        case 80: return 0x4217c62f // P
        case 81: return 0x59358c62e // Q
        case 82: return 0x45257c62f // R
        case 83: return 0x3e107043e // S
        case 84: return 0x10842109f // T
        case 85: return 0x3a318c631 // U
        case 86: return 0x11518c631 // V
        case 87: return 0x4775ac631 // W
        case 88: return 0x462a22a31 // X
        case 89: return 0x108422a31 // Y
        case 90: return 0x7c222221f // Z
        case 48: return 0x3a33ae62e // 0
        case 49: return 0x3884210c4 // 1
        case 50: return 0x7c444422e // 2
        case 51: return 0x3e107420f // 3
        case 52: return 0x211f4a988 // 4
        case 53: return 0x3e107843f // 5
        case 54: return 0x3a317842e // 6
        case 55: return 0x8422221f // 7
        case 56: return 0x3a317462e // 8
        case 57: return 0x3a10f462e // 9
        case 45: return 0xf8000 // -
        case 43: return 0x84f9080 // +
        case 58: return 0x8401080 // :
        case 47: return 0x42222210 // /
        case 46: return 0x108000000 // .
        default: return 0
        }
    }
}
