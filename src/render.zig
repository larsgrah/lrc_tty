const std = @import("std");
const lyrics = @import("lyrics.zig");

const Range = struct { lo: u21, hi: u21 };

// Sorted ranges of zero-width codepoints (combining marks, format characters, etc.)
const zero_width_ranges = [_]Range{
    .{ .lo = 0x00AD, .hi = 0x00AD }, // soft hyphen
    .{ .lo = 0x0300, .hi = 0x036F }, // combining diacritical marks
    .{ .lo = 0x0483, .hi = 0x0489 }, // cyrillic combining
    .{ .lo = 0x0591, .hi = 0x05BD }, // hebrew combining
    .{ .lo = 0x05BF, .hi = 0x05BF },
    .{ .lo = 0x05C1, .hi = 0x05C2 },
    .{ .lo = 0x05C4, .hi = 0x05C5 },
    .{ .lo = 0x05C7, .hi = 0x05C7 },
    .{ .lo = 0x0600, .hi = 0x0605 }, // arabic format
    .{ .lo = 0x0610, .hi = 0x061A }, // arabic combining
    .{ .lo = 0x064B, .hi = 0x065F },
    .{ .lo = 0x0670, .hi = 0x0670 },
    .{ .lo = 0x06D6, .hi = 0x06E4 },
    .{ .lo = 0x06E7, .hi = 0x06E8 },
    .{ .lo = 0x06EA, .hi = 0x06ED },
    .{ .lo = 0x070F, .hi = 0x070F },
    .{ .lo = 0x0711, .hi = 0x0711 },
    .{ .lo = 0x0730, .hi = 0x074A }, // syriac
    .{ .lo = 0x07A6, .hi = 0x07B0 }, // thaana
    .{ .lo = 0x07EB, .hi = 0x07F3 }, // nko
    .{ .lo = 0x0816, .hi = 0x0819 }, // samaritan
    .{ .lo = 0x081B, .hi = 0x0823 },
    .{ .lo = 0x0825, .hi = 0x0827 },
    .{ .lo = 0x0829, .hi = 0x082D },
    .{ .lo = 0x0859, .hi = 0x085B }, // mandaic
    .{ .lo = 0x08D3, .hi = 0x0902 }, // arabic extended-a
    .{ .lo = 0x093A, .hi = 0x093C }, // devanagari
    .{ .lo = 0x093E, .hi = 0x094F },
    .{ .lo = 0x0951, .hi = 0x0957 },
    .{ .lo = 0x0962, .hi = 0x0963 },
    .{ .lo = 0x0981, .hi = 0x0983 }, // bengali
    .{ .lo = 0x09BC, .hi = 0x09BC },
    .{ .lo = 0x09BE, .hi = 0x09CD },
    .{ .lo = 0x09D7, .hi = 0x09D7 },
    .{ .lo = 0x09E2, .hi = 0x09E3 },
    .{ .lo = 0x09FE, .hi = 0x09FE },
    .{ .lo = 0x0A01, .hi = 0x0A03 }, // gurmukhi
    .{ .lo = 0x0A3C, .hi = 0x0A3C },
    .{ .lo = 0x0A3E, .hi = 0x0A42 },
    .{ .lo = 0x0A47, .hi = 0x0A48 },
    .{ .lo = 0x0A4B, .hi = 0x0A4D },
    .{ .lo = 0x0A51, .hi = 0x0A51 },
    .{ .lo = 0x0A70, .hi = 0x0A71 },
    .{ .lo = 0x0A75, .hi = 0x0A75 },
    .{ .lo = 0x0A81, .hi = 0x0A83 }, // gujarati
    .{ .lo = 0x0ABC, .hi = 0x0ABC },
    .{ .lo = 0x0ABE, .hi = 0x0ACD },
    .{ .lo = 0x0AE2, .hi = 0x0AE3 },
    .{ .lo = 0x0AFA, .hi = 0x0AFF },
    .{ .lo = 0x0B01, .hi = 0x0B03 }, // oriya
    .{ .lo = 0x0B3C, .hi = 0x0B3C },
    .{ .lo = 0x0B3E, .hi = 0x0B4D },
    .{ .lo = 0x0B55, .hi = 0x0B57 },
    .{ .lo = 0x0B62, .hi = 0x0B63 },
    .{ .lo = 0x0B82, .hi = 0x0B82 }, // tamil
    .{ .lo = 0x0BBE, .hi = 0x0BCD },
    .{ .lo = 0x0BD7, .hi = 0x0BD7 },
    .{ .lo = 0x0C00, .hi = 0x0C04 }, // telugu
    .{ .lo = 0x0C3E, .hi = 0x0C56 },
    .{ .lo = 0x0C62, .hi = 0x0C63 },
    .{ .lo = 0x0C81, .hi = 0x0C83 }, // kannada
    .{ .lo = 0x0CBC, .hi = 0x0CBC },
    .{ .lo = 0x0CBE, .hi = 0x0CCD },
    .{ .lo = 0x0CD5, .hi = 0x0CD6 },
    .{ .lo = 0x0CE2, .hi = 0x0CE3 },
    .{ .lo = 0x0D00, .hi = 0x0D03 }, // malayalam
    .{ .lo = 0x0D3B, .hi = 0x0D3C },
    .{ .lo = 0x0D3E, .hi = 0x0D4D },
    .{ .lo = 0x0D57, .hi = 0x0D57 },
    .{ .lo = 0x0D62, .hi = 0x0D63 },
    .{ .lo = 0x0D81, .hi = 0x0D83 }, // sinhala
    .{ .lo = 0x0DCA, .hi = 0x0DCA },
    .{ .lo = 0x0DCF, .hi = 0x0DDF },
    .{ .lo = 0x0DF2, .hi = 0x0DF3 },
    .{ .lo = 0x0E31, .hi = 0x0E31 }, // thai
    .{ .lo = 0x0E34, .hi = 0x0E3A },
    .{ .lo = 0x0E47, .hi = 0x0E4E },
    .{ .lo = 0x0EB1, .hi = 0x0EB1 }, // lao
    .{ .lo = 0x0EB4, .hi = 0x0EBC },
    .{ .lo = 0x0EC8, .hi = 0x0ECD },
    .{ .lo = 0x0F18, .hi = 0x0F19 }, // tibetan
    .{ .lo = 0x0F35, .hi = 0x0F35 },
    .{ .lo = 0x0F37, .hi = 0x0F37 },
    .{ .lo = 0x0F39, .hi = 0x0F39 },
    .{ .lo = 0x0F3E, .hi = 0x0F3F },
    .{ .lo = 0x0F71, .hi = 0x0F84 },
    .{ .lo = 0x0F86, .hi = 0x0F87 },
    .{ .lo = 0x0F8D, .hi = 0x0FBC },
    .{ .lo = 0x0FC6, .hi = 0x0FC6 },
    .{ .lo = 0x102B, .hi = 0x103E }, // myanmar
    .{ .lo = 0x1056, .hi = 0x1059 },
    .{ .lo = 0x105E, .hi = 0x1060 },
    .{ .lo = 0x1062, .hi = 0x1064 },
    .{ .lo = 0x1067, .hi = 0x106D },
    .{ .lo = 0x1071, .hi = 0x1074 },
    .{ .lo = 0x1082, .hi = 0x108D },
    .{ .lo = 0x108F, .hi = 0x108F },
    .{ .lo = 0x109A, .hi = 0x109D },
    .{ .lo = 0x1160, .hi = 0x11FF }, // hangul jamo medial/final
    .{ .lo = 0x135D, .hi = 0x135F }, // ethiopic combining
    .{ .lo = 0x1712, .hi = 0x1714 }, // tagalog
    .{ .lo = 0x1732, .hi = 0x1734 },
    .{ .lo = 0x1752, .hi = 0x1753 },
    .{ .lo = 0x1772, .hi = 0x1773 },
    .{ .lo = 0x17B4, .hi = 0x17D3 }, // khmer
    .{ .lo = 0x17DD, .hi = 0x17DD },
    .{ .lo = 0x180B, .hi = 0x180E }, // mongolian
    .{ .lo = 0x1885, .hi = 0x1886 },
    .{ .lo = 0x18A9, .hi = 0x18A9 },
    .{ .lo = 0x1920, .hi = 0x193B }, // limbu/tai le
    .{ .lo = 0x19B0, .hi = 0x19C0 },
    .{ .lo = 0x19C8, .hi = 0x19C9 },
    .{ .lo = 0x1A17, .hi = 0x1A1B },
    .{ .lo = 0x1A55, .hi = 0x1A7F },
    .{ .lo = 0x1AB0, .hi = 0x1ACE }, // combining diacritical marks extended
    .{ .lo = 0x1B00, .hi = 0x1B04 }, // balinese
    .{ .lo = 0x1B34, .hi = 0x1B44 },
    .{ .lo = 0x1B6B, .hi = 0x1B73 },
    .{ .lo = 0x1B80, .hi = 0x1B82 },
    .{ .lo = 0x1BA1, .hi = 0x1BAD },
    .{ .lo = 0x1BE6, .hi = 0x1BF3 },
    .{ .lo = 0x1C24, .hi = 0x1C37 },
    .{ .lo = 0x1CD0, .hi = 0x1CD2 }, // vedic extensions
    .{ .lo = 0x1CD4, .hi = 0x1CE8 },
    .{ .lo = 0x1CED, .hi = 0x1CED },
    .{ .lo = 0x1CF4, .hi = 0x1CF4 },
    .{ .lo = 0x1CF7, .hi = 0x1CF9 },
    .{ .lo = 0x1DC0, .hi = 0x1DFF }, // combining diacritical marks supplement
    .{ .lo = 0x200B, .hi = 0x200F }, // zwsp, zwnj, zwj, lrm, rlm
    .{ .lo = 0x2028, .hi = 0x202E }, // line/para separators, bidi
    .{ .lo = 0x2060, .hi = 0x2064 }, // word joiner, invisible operators
    .{ .lo = 0x2066, .hi = 0x206F }, // bidi isolates
    .{ .lo = 0x20D0, .hi = 0x20F0 }, // combining marks for symbols
    .{ .lo = 0x2CEF, .hi = 0x2CF1 },
    .{ .lo = 0x2D7F, .hi = 0x2D7F },
    .{ .lo = 0x2DE0, .hi = 0x2DFF },
    .{ .lo = 0x302A, .hi = 0x302F }, // cjk combining
    .{ .lo = 0x3099, .hi = 0x309A }, // japanese combining
    .{ .lo = 0xA66F, .hi = 0xA672 },
    .{ .lo = 0xA674, .hi = 0xA67D },
    .{ .lo = 0xA69E, .hi = 0xA69F },
    .{ .lo = 0xA6F0, .hi = 0xA6F1 },
    .{ .lo = 0xA802, .hi = 0xA802 },
    .{ .lo = 0xA806, .hi = 0xA806 },
    .{ .lo = 0xA80B, .hi = 0xA80B },
    .{ .lo = 0xA823, .hi = 0xA827 },
    .{ .lo = 0xA82C, .hi = 0xA82C },
    .{ .lo = 0xA880, .hi = 0xA881 },
    .{ .lo = 0xA8B4, .hi = 0xA8C5 },
    .{ .lo = 0xA8E0, .hi = 0xA8F1 },
    .{ .lo = 0xA8FF, .hi = 0xA8FF },
    .{ .lo = 0xA926, .hi = 0xA92D },
    .{ .lo = 0xA947, .hi = 0xA953 },
    .{ .lo = 0xA980, .hi = 0xA983 },
    .{ .lo = 0xA9B3, .hi = 0xA9C0 },
    .{ .lo = 0xA9E5, .hi = 0xA9E5 },
    .{ .lo = 0xAA29, .hi = 0xAA36 },
    .{ .lo = 0xAA43, .hi = 0xAA43 },
    .{ .lo = 0xAA4C, .hi = 0xAA4D },
    .{ .lo = 0xAA7B, .hi = 0xAA7D },
    .{ .lo = 0xAAB0, .hi = 0xAAB0 },
    .{ .lo = 0xAAB2, .hi = 0xAAB4 },
    .{ .lo = 0xAAB7, .hi = 0xAAB8 },
    .{ .lo = 0xAABE, .hi = 0xAABF },
    .{ .lo = 0xAAC1, .hi = 0xAAC1 },
    .{ .lo = 0xAAEB, .hi = 0xAAEF },
    .{ .lo = 0xAAF5, .hi = 0xAAF6 },
    .{ .lo = 0xABE3, .hi = 0xABEA },
    .{ .lo = 0xABEC, .hi = 0xABED },
    .{ .lo = 0xFB1E, .hi = 0xFB1E },
    .{ .lo = 0xFE00, .hi = 0xFE0F }, // variation selectors
    .{ .lo = 0xFE20, .hi = 0xFE2F }, // combining half marks
    .{ .lo = 0xFEFF, .hi = 0xFEFF }, // bom / zwnbsp
    .{ .lo = 0xFFF9, .hi = 0xFFFB },
    .{ .lo = 0x101FD, .hi = 0x101FD },
    .{ .lo = 0x102E0, .hi = 0x102E0 },
    .{ .lo = 0x10376, .hi = 0x1037A },
    .{ .lo = 0x10A01, .hi = 0x10A0F },
    .{ .lo = 0x10A38, .hi = 0x10A3F },
    .{ .lo = 0x10AE5, .hi = 0x10AE6 },
    .{ .lo = 0x10D24, .hi = 0x10D27 },
    .{ .lo = 0x10EAB, .hi = 0x10EAC },
    .{ .lo = 0x10F46, .hi = 0x10F50 },
    .{ .lo = 0x11000, .hi = 0x11002 },
    .{ .lo = 0x11038, .hi = 0x11046 },
    .{ .lo = 0x1107F, .hi = 0x11082 },
    .{ .lo = 0x110B0, .hi = 0x110BA },
    .{ .lo = 0x11100, .hi = 0x11102 },
    .{ .lo = 0x11127, .hi = 0x11134 },
    .{ .lo = 0x11145, .hi = 0x11146 },
    .{ .lo = 0x11173, .hi = 0x11173 },
    .{ .lo = 0x11180, .hi = 0x11182 },
    .{ .lo = 0x111B3, .hi = 0x111C0 },
    .{ .lo = 0x111C9, .hi = 0x111CC },
    .{ .lo = 0x111CE, .hi = 0x111CF },
    .{ .lo = 0x1122C, .hi = 0x11237 },
    .{ .lo = 0x1123E, .hi = 0x1123E },
    .{ .lo = 0x112DF, .hi = 0x112EA },
    .{ .lo = 0x11300, .hi = 0x11303 },
    .{ .lo = 0x1133B, .hi = 0x1133C },
    .{ .lo = 0x1133E, .hi = 0x11344 },
    .{ .lo = 0x11347, .hi = 0x11348 },
    .{ .lo = 0x1134B, .hi = 0x1134D },
    .{ .lo = 0x11357, .hi = 0x11357 },
    .{ .lo = 0x11362, .hi = 0x11363 },
    .{ .lo = 0x11366, .hi = 0x1136C },
    .{ .lo = 0x11370, .hi = 0x11374 },
    .{ .lo = 0x11435, .hi = 0x11446 },
    .{ .lo = 0x1145E, .hi = 0x1145E },
    .{ .lo = 0x114B0, .hi = 0x114C3 },
    .{ .lo = 0x115AF, .hi = 0x115B5 },
    .{ .lo = 0x115B8, .hi = 0x115C0 },
    .{ .lo = 0x115DC, .hi = 0x115DD },
    .{ .lo = 0x11630, .hi = 0x11640 },
    .{ .lo = 0x116AB, .hi = 0x116B7 },
    .{ .lo = 0x1171D, .hi = 0x1172B },
    .{ .lo = 0x1182C, .hi = 0x1183A },
    .{ .lo = 0x11930, .hi = 0x11935 },
    .{ .lo = 0x11937, .hi = 0x11938 },
    .{ .lo = 0x1193B, .hi = 0x1193E },
    .{ .lo = 0x11940, .hi = 0x11940 },
    .{ .lo = 0x11942, .hi = 0x11943 },
    .{ .lo = 0x119D1, .hi = 0x119D7 },
    .{ .lo = 0x119DA, .hi = 0x119E0 },
    .{ .lo = 0x119E4, .hi = 0x119E4 },
    .{ .lo = 0x11A01, .hi = 0x11A0A },
    .{ .lo = 0x11A33, .hi = 0x11A39 },
    .{ .lo = 0x11A3B, .hi = 0x11A3E },
    .{ .lo = 0x11A47, .hi = 0x11A47 },
    .{ .lo = 0x11A51, .hi = 0x11A5B },
    .{ .lo = 0x11A8A, .hi = 0x11A99 },
    .{ .lo = 0x11C2F, .hi = 0x11C36 },
    .{ .lo = 0x11C38, .hi = 0x11C3F },
    .{ .lo = 0x11C92, .hi = 0x11CA7 },
    .{ .lo = 0x11CA9, .hi = 0x11CB6 },
    .{ .lo = 0x11D31, .hi = 0x11D36 },
    .{ .lo = 0x11D3A, .hi = 0x11D3A },
    .{ .lo = 0x11D3C, .hi = 0x11D3D },
    .{ .lo = 0x11D3F, .hi = 0x11D45 },
    .{ .lo = 0x11D47, .hi = 0x11D47 },
    .{ .lo = 0x11D8A, .hi = 0x11D8E },
    .{ .lo = 0x11D90, .hi = 0x11D91 },
    .{ .lo = 0x11D93, .hi = 0x11D97 },
    .{ .lo = 0x11EF3, .hi = 0x11EF6 },
    .{ .lo = 0x16AF0, .hi = 0x16AF4 },
    .{ .lo = 0x16B30, .hi = 0x16B36 },
    .{ .lo = 0x16F4F, .hi = 0x16F4F },
    .{ .lo = 0x16F51, .hi = 0x16F87 },
    .{ .lo = 0x16F8F, .hi = 0x16F92 },
    .{ .lo = 0x16FE4, .hi = 0x16FE4 },
    .{ .lo = 0x1BC9D, .hi = 0x1BC9E },
    .{ .lo = 0x1D165, .hi = 0x1D169 }, // musical symbols combining
    .{ .lo = 0x1D16D, .hi = 0x1D182 },
    .{ .lo = 0x1D185, .hi = 0x1D18B },
    .{ .lo = 0x1D1AA, .hi = 0x1D1AD },
    .{ .lo = 0x1D242, .hi = 0x1D244 },
    .{ .lo = 0x1DA00, .hi = 0x1DA36 },
    .{ .lo = 0x1DA3B, .hi = 0x1DA6C },
    .{ .lo = 0x1DA75, .hi = 0x1DA75 },
    .{ .lo = 0x1DA84, .hi = 0x1DA84 },
    .{ .lo = 0x1DA9B, .hi = 0x1DA9F },
    .{ .lo = 0x1DAA1, .hi = 0x1DAAF },
    .{ .lo = 0x1E000, .hi = 0x1E006 },
    .{ .lo = 0x1E008, .hi = 0x1E018 },
    .{ .lo = 0x1E01B, .hi = 0x1E021 },
    .{ .lo = 0x1E023, .hi = 0x1E024 },
    .{ .lo = 0x1E026, .hi = 0x1E02A },
    .{ .lo = 0x1E130, .hi = 0x1E136 },
    .{ .lo = 0x1E2EC, .hi = 0x1E2EF },
    .{ .lo = 0x1E8D0, .hi = 0x1E8D6 },
    .{ .lo = 0x1E944, .hi = 0x1E94A },
    .{ .lo = 0xE0001, .hi = 0xE0001 }, // language tag
    .{ .lo = 0xE0020, .hi = 0xE007F }, // tag characters
    .{ .lo = 0xE0100, .hi = 0xE01EF }, // variation selectors supplement
};

// Sorted ranges of wide (2-column) codepoints
const wide_ranges = [_]Range{
    .{ .lo = 0x1100, .hi = 0x115F }, // hangul jamo initial
    .{ .lo = 0x231A, .hi = 0x231B }, // watch, hourglass
    .{ .lo = 0x2329, .hi = 0x232A }, // angle brackets
    .{ .lo = 0x23E9, .hi = 0x23F3 }, // various symbols
    .{ .lo = 0x23F8, .hi = 0x23FA },
    .{ .lo = 0x25FD, .hi = 0x25FE },
    .{ .lo = 0x2614, .hi = 0x2615 },
    .{ .lo = 0x2648, .hi = 0x2653 },
    .{ .lo = 0x267F, .hi = 0x267F },
    .{ .lo = 0x2693, .hi = 0x2693 },
    .{ .lo = 0x26A1, .hi = 0x26A1 },
    .{ .lo = 0x26AA, .hi = 0x26AB },
    .{ .lo = 0x26BD, .hi = 0x26BE },
    .{ .lo = 0x26C4, .hi = 0x26C5 },
    .{ .lo = 0x26CE, .hi = 0x26CE },
    .{ .lo = 0x26D4, .hi = 0x26D4 },
    .{ .lo = 0x26EA, .hi = 0x26EA },
    .{ .lo = 0x26F2, .hi = 0x26F3 },
    .{ .lo = 0x26F5, .hi = 0x26F5 },
    .{ .lo = 0x26FA, .hi = 0x26FA },
    .{ .lo = 0x26FD, .hi = 0x26FD },
    .{ .lo = 0x2702, .hi = 0x2702 },
    .{ .lo = 0x2705, .hi = 0x2705 },
    .{ .lo = 0x2708, .hi = 0x270D },
    .{ .lo = 0x270F, .hi = 0x270F },
    .{ .lo = 0x2728, .hi = 0x2728 },
    .{ .lo = 0x274C, .hi = 0x274C },
    .{ .lo = 0x274E, .hi = 0x274E },
    .{ .lo = 0x2753, .hi = 0x2755 },
    .{ .lo = 0x2757, .hi = 0x2757 },
    .{ .lo = 0x2795, .hi = 0x2797 },
    .{ .lo = 0x27B0, .hi = 0x27B0 },
    .{ .lo = 0x27BF, .hi = 0x27BF },
    .{ .lo = 0x2B1B, .hi = 0x2B1C },
    .{ .lo = 0x2B50, .hi = 0x2B50 },
    .{ .lo = 0x2B55, .hi = 0x2B55 },
    .{ .lo = 0x2E80, .hi = 0x2E99 }, // cjk radicals supplement
    .{ .lo = 0x2E9B, .hi = 0x2EF3 },
    .{ .lo = 0x2F00, .hi = 0x2FD5 }, // kangxi radicals
    .{ .lo = 0x2FF0, .hi = 0x2FFB }, // ideographic description
    .{ .lo = 0x3000, .hi = 0x303E }, // cjk symbols and punctuation
    .{ .lo = 0x3041, .hi = 0x3096 }, // hiragana
    .{ .lo = 0x3099, .hi = 0x30FF }, // katakana
    .{ .lo = 0x3105, .hi = 0x312F }, // bopomofo
    .{ .lo = 0x3131, .hi = 0x318E }, // hangul compatibility jamo
    .{ .lo = 0x3190, .hi = 0x31E3 }, // kanbun, cjk strokes
    .{ .lo = 0x31F0, .hi = 0x321E }, // katakana phonetic ext
    .{ .lo = 0x3220, .hi = 0x3247 }, // enclosed cjk
    .{ .lo = 0x3250, .hi = 0x4DBF }, // cjk extensions
    .{ .lo = 0x4E00, .hi = 0xA48C }, // cjk unified ideographs
    .{ .lo = 0xA490, .hi = 0xA4C6 }, // yi radicals
    .{ .lo = 0xA960, .hi = 0xA97C }, // hangul jamo extended-a
    .{ .lo = 0xAC00, .hi = 0xD7A3 }, // hangul syllables
    .{ .lo = 0xF900, .hi = 0xFAFF }, // cjk compatibility ideographs
    .{ .lo = 0xFE10, .hi = 0xFE19 }, // vertical forms
    .{ .lo = 0xFE30, .hi = 0xFE6F }, // cjk compatibility forms
    .{ .lo = 0xFF01, .hi = 0xFF60 }, // fullwidth forms
    .{ .lo = 0xFFE0, .hi = 0xFFE6 }, // fullwidth signs
    .{ .lo = 0x16FE0, .hi = 0x16FE3 }, // ideographic symbols
    .{ .lo = 0x17000, .hi = 0x187F7 }, // tangut
    .{ .lo = 0x18800, .hi = 0x18CD5 },
    .{ .lo = 0x18D00, .hi = 0x18D08 },
    .{ .lo = 0x1AFF0, .hi = 0x1AFF3 },
    .{ .lo = 0x1AFF5, .hi = 0x1AFFB },
    .{ .lo = 0x1AFFD, .hi = 0x1AFFE },
    .{ .lo = 0x1B000, .hi = 0x1B122 }, // kana supplement
    .{ .lo = 0x1B150, .hi = 0x1B152 },
    .{ .lo = 0x1B164, .hi = 0x1B167 },
    .{ .lo = 0x1B170, .hi = 0x1B2FB }, // nushu
    .{ .lo = 0x1F004, .hi = 0x1F004 }, // mahjong tile
    .{ .lo = 0x1F0CF, .hi = 0x1F0CF }, // playing card
    .{ .lo = 0x1F18E, .hi = 0x1F18E },
    .{ .lo = 0x1F191, .hi = 0x1F19A },
    .{ .lo = 0x1F200, .hi = 0x1F202 }, // enclosed ideographic supplement
    .{ .lo = 0x1F210, .hi = 0x1F23B },
    .{ .lo = 0x1F240, .hi = 0x1F248 },
    .{ .lo = 0x1F250, .hi = 0x1F251 },
    .{ .lo = 0x1F260, .hi = 0x1F265 },
    .{ .lo = 0x1F300, .hi = 0x1F64F }, // misc symbols, emoticons
    .{ .lo = 0x1F680, .hi = 0x1F6FF }, // transport/map symbols
    .{ .lo = 0x1F774, .hi = 0x1F77F },
    .{ .lo = 0x1F7D5, .hi = 0x1F7FF },
    .{ .lo = 0x1F80C, .hi = 0x1F80F },
    .{ .lo = 0x1F848, .hi = 0x1F84F },
    .{ .lo = 0x1F85A, .hi = 0x1F85F },
    .{ .lo = 0x1F888, .hi = 0x1F88F },
    .{ .lo = 0x1F8AE, .hi = 0x1F8FF },
    .{ .lo = 0x1F900, .hi = 0x1F9FF }, // supplemental symbols
    .{ .lo = 0x1FA00, .hi = 0x1FA6F },
    .{ .lo = 0x1FA70, .hi = 0x1FAFF },
    .{ .lo = 0x1FB00, .hi = 0x1FBFF },
    .{ .lo = 0x20000, .hi = 0x2FFFD }, // cjk unified ideographs ext B+
    .{ .lo = 0x30000, .hi = 0x3FFFD }, // cjk unified ideographs ext G+
};

fn inRanges(cp: u21, ranges: []const Range) bool {
    var lo: usize = 0;
    var hi: usize = ranges.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        if (cp > ranges[mid].hi) {
            lo = mid + 1;
        } else if (cp < ranges[mid].lo) {
            hi = mid;
        } else {
            return true;
        }
    }
    return false;
}

fn charWidth(cp: u21) u2 {
    if (cp < 0x20 or (cp >= 0x7F and cp < 0xA0)) return 0;
    if (inRanges(cp, &zero_width_ranges)) return 0;
    if (inRanges(cp, &wide_ranges)) return 2;
    return 1;
}

fn displayWidth(str: []const u8) usize {
    var width: usize = 0;
    var i: usize = 0;
    while (i < str.len) {
        const cp_len = std.unicode.utf8ByteSequenceLength(str[i]) catch {
            i += 1;
            continue;
        };
        if (i + cp_len > str.len) break;
        const codepoint = std.unicode.utf8Decode(str[i..][0..cp_len]) catch {
            i += cp_len;
            continue;
        };
        width += charWidth(codepoint);
        i += cp_len;
    }
    return width;
}

test "displayWidth: ASCII" {
    try std.testing.expectEqual(@as(usize, 5), displayWidth("hello"));
    try std.testing.expectEqual(@as(usize, 0), displayWidth(""));
    try std.testing.expectEqual(@as(usize, 1), displayWidth(" "));
}

test "displayWidth: Vietnamese combining marks" {
    // NFC (precomposed) - no separate combining marks
    try std.testing.expectEqual(@as(usize, 33), displayWidth("Với con thế thôi, còn gì đẹp hơn?"));

    // NFD (decomposed) - combining marks should be zero-width
    // "é" as e + combining acute (U+0301)
    try std.testing.expectEqual(@as(usize, 1), displayWidth("e\u{0301}"));
    // "ờ" as o + combining horn (U+031B) + combining grave (U+0300)
    try std.testing.expectEqual(@as(usize, 1), displayWidth("o\u{031B}\u{0300}"));
    // NFD "Với" = V + o + horn + grave + i = 3 visible columns
    try std.testing.expectEqual(@as(usize, 3), displayWidth("Vo\u{031B}\u{0300}i"));
}

test "displayWidth: CJK wide characters" {
    // Each CJK character = 2 columns
    try std.testing.expectEqual(@as(usize, 6), displayWidth("中文字"));
    try std.testing.expectEqual(@as(usize, 7), displayWidth("A中文字"));
}

test "displayWidth: zero-width characters" {
    // ZWJ (U+200D) and ZWNJ (U+200C) are zero width
    try std.testing.expectEqual(@as(usize, 2), displayWidth("a\u{200D}b"));
    try std.testing.expectEqual(@as(usize, 2), displayWidth("a\u{200C}b"));
}

test "displayWidth: fullwidth forms" {
    // Fullwidth latin (U+FF21 = fullwidth A)
    try std.testing.expectEqual(@as(usize, 2), displayWidth("\u{FF21}"));
}

test "displayWidth: mixed content" {
    // "Hello中文" = 5 ASCII + 2*2 CJK = 9
    try std.testing.expectEqual(@as(usize, 9), displayWidth("Hello中文"));
}

const TerminalSize = struct {
    rows: u16,
    cols: u16,
};

const RenderSlot = struct {
    present: bool,
    text_ptr: usize,
    t: f64,
    highlight: bool,
};

pub const RenderState = struct {
    allocator: std.mem.Allocator,
    show_timestamp: bool,
    dim_inactive: bool,
    visible_lines: usize,
    initialized: bool,
    last_rows: u16,
    last_cols: u16,
    last_start_row: usize,
    slots: []RenderSlot,

    pub fn init(allocator: std.mem.Allocator, show_timestamp: bool, dim_inactive: bool, visible_lines: usize) !RenderState {
        const slots = try allocator.alloc(RenderSlot, visible_lines);
        for (slots) |*slot| slot.* = RenderSlot{ .present = false, .text_ptr = 0, .t = 0, .highlight = false };
        return RenderState{
            .allocator = allocator,
            .show_timestamp = show_timestamp,
            .dim_inactive = dim_inactive,
            .visible_lines = visible_lines,
            .initialized = false,
            .last_rows = 0,
            .last_cols = 0,
            .last_start_row = 0,
            .slots = slots,
        };
    }

    pub fn deinit(self: *RenderState) void {
        self.allocator.free(self.slots);
        self.slots = &[_]RenderSlot{};
    }

    pub fn reset(self: *RenderState) void {
        self.initialized = false;
        self.last_rows = 0;
        self.last_cols = 0;
        self.last_start_row = 0;
        for (self.slots) |*slot| slot.* = RenderSlot{ .present = false, .text_ptr = 0, .t = 0, .highlight = false };
    }

    pub fn draw(
        self: *RenderState,
        title: []const u8,
        artist: []const u8,
        album: []const u8,
        status: []const u8,
        cur_t: f64,
        lines: []const lyrics.Line,
        src: []const u8,
    ) void {
        _ = title;
        _ = artist;
        _ = album;
        _ = status;
        _ = src;

        const term = getTerminalSize();
        const row_count: usize = @as(usize, if (term.rows == 0) 24 else term.rows);
        const col_count: usize = @as(usize, if (term.cols == 0) 80 else term.cols);
        const line_count: usize = self.visible_lines;
        const top_pad: usize = if (row_count > line_count) (row_count - line_count) / 2 else 0;
        const start_row: usize = top_pad + 1;

        const need_full_clear = !self.initialized or term.rows != self.last_rows or term.cols != self.last_cols or start_row != self.last_start_row;
        if (need_full_clear) {
            clearScreen();
            self.initialized = true;
            self.last_rows = term.rows;
            self.last_cols = term.cols;
            self.last_start_row = start_row;
            for (self.slots) |*slot| slot.* = RenderSlot{ .present = false, .text_ptr = 0, .t = 0, .highlight = false };
        }

        const idx = nearestIndex(lines, cur_t);
        const half = self.visible_lines / 2;
        var base_index: usize = 0;
        if (lines.len != 0) {
            base_index = if (idx > half) idx - half else 0;
            const max_start = if (lines.len > self.visible_lines) lines.len - self.visible_lines else 0;
            if (base_index > max_start) base_index = max_start;
        }

        for (self.slots, 0..) |*slot, i| {
            const line_index = if (lines.len == 0) @as(usize, 0) else base_index + i;
            var line_opt: ?lyrics.Line = null;
            var highlight = false;
            if (lines.len != 0 and line_index < lines.len) {
                line_opt = lines[line_index];
                highlight = line_index == idx;
            }
            if (slotNeedsUpdate(slot.*, line_opt, highlight)) {
                printCenteredLine(start_row + i, line_opt, highlight, col_count, self.show_timestamp, self.dim_inactive);
                rememberSlot(slot, line_opt, highlight);
            }
        }
    }
};

fn getTerminalSize() TerminalSize {
    var size = TerminalSize{ .rows = 24, .cols = 80 };
    const stdout_file = std.fs.File.stdout();
    const fd = stdout_file.handle;

    var ws: std.posix.winsize = .{
        .row = 0,
        .col = 0,
        .xpixel = 0,
        .ypixel = 0,
    };

    const err = std.posix.system.ioctl(fd, std.posix.T.IOCGWINSZ, @intFromPtr(&ws));
    if (std.posix.errno(err) == .SUCCESS and ws.row != 0 and ws.col != 0) {
        size.rows = ws.row;
        size.cols = ws.col;
    }

    return size;
}

fn clearScreen() void {
    std.debug.print("\x1b[2J\x1b[H", .{});
}

fn slotNeedsUpdate(slot: RenderSlot, line_opt: ?lyrics.Line, highlight: bool) bool {
    if (line_opt) |ln| {
        const text_ptr = @intFromPtr(ln.text.ptr);
        return !slot.present or slot.text_ptr != text_ptr or slot.t != ln.t or slot.highlight != highlight;
    } else {
        return slot.present;
    }
}

fn rememberSlot(slot: *RenderSlot, line_opt: ?lyrics.Line, highlight: bool) void {
    if (line_opt) |ln| {
        slot.* = RenderSlot{
            .present = true,
            .text_ptr = @intFromPtr(ln.text.ptr),
            .t = ln.t,
            .highlight = highlight,
        };
    } else {
        slot.* = RenderSlot{ .present = false, .text_ptr = 0, .t = 0, .highlight = false };
    }
}

fn nearestIndex(lines: []const lyrics.Line, t: f64) usize {
    if (lines.len == 0) return 0;
    var lo: usize = 0;
    var hi: usize = lines.len - 1;
    while (lo < hi) {
        const mid = (lo + hi + 1) / 2;
        if (lines[mid].t <= t) lo = mid else hi = mid - 1;
    }
    return lo;
}

fn printCenteredLine(row: usize, line_opt: ?lyrics.Line, highlight: bool, cols: usize, show_timestamp: bool, dim_inactive: bool) void {
    std.debug.print("\x1b[{d};1H", .{row});

    if (line_opt) |ln| {
        var buf: [1024]u8 = undefined;
        const segment = blk: {
            if (show_timestamp) {
                const mm: u64 = @intFromFloat(@floor(ln.t / 60.0));
                const ss: u64 = @intFromFloat(@floor(ln.t - @as(f64, @floatFromInt(mm)) * 60.0));
                const formatted = std.fmt.bufPrint(&buf, "[{d:0>2}:{d:0>2}] {s}", .{ mm, ss, ln.text }) catch null;
                if (formatted) |seg| break :blk seg;
            }
            break :blk ln.text;
        };

        const seg_width = displayWidth(segment);
        const visual_width = if (cols == 0) seg_width else cols;
        const pad = if (visual_width > seg_width) (visual_width - seg_width) / 2 else 0;

        var i: usize = 0;
        while (i < pad) : (i += 1) {
            std.debug.print(" ", .{});
        }

        if (highlight) {
            std.debug.print("\x1b[7m{s}\x1b[0m", .{segment});
        } else if (dim_inactive) {
            std.debug.print("\x1b[2m{s}\x1b[0m", .{segment});
        } else {
            std.debug.print("{s}", .{segment});
        }
    }

    std.debug.print("\x1b[0m\x1b[K", .{});
}
