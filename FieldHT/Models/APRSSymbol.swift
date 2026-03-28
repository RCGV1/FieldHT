//
//  APRSSymbol.swift
//  FieldHT
//

import Foundation

struct APRSSymbol: Identifiable, Equatable {
    /// The 2-character APRS symbol code stored on the radio (e.g. "/>")
    let code: String
    /// Image filename base (without .png) inside APRSSymbols bundle folder (e.g. "MV")
    let tocall: String
    /// Human-readable description
    let description: String

    var id: String { code }
}

// MARK: - Bundle image loading
extension APRSSymbol {
    /// Returns the path to the PNG inside the app bundle, or nil if not found.
    var imagePath: String? {
        Bundle.main.path(forResource: tocall, ofType: "png")
    }
}

// MARK: - Full symbol table
extension APRSSymbol {
    /// Parse a 2-char APRS symbol string to its APRSSymbol, or nil if unknown.
    static func symbol(for code: String) -> APRSSymbol? {
        all.first { $0.code == code }
    }

    static let all: [APRSSymbol] = [
        // ── Primary table (/) ─────────────────────────────────────────────
        APRSSymbol(code: "/!", tocall: "BB", description: "Police station"),
        APRSSymbol(code: "/#", tocall: "BD", description: "Digipeater"),
        APRSSymbol(code: "/$", tocall: "BE", description: "Telephone"),
        APRSSymbol(code: "/%", tocall: "BF", description: "DX cluster"),
        APRSSymbol(code: "/&", tocall: "BG", description: "HF gateway"),
        APRSSymbol(code: "/'", tocall: "BH", description: "Small aircraft"),
        APRSSymbol(code: "/(", tocall: "BI", description: "Mobile satellite station"),
        APRSSymbol(code: "/)", tocall: "BJ", description: "Wheelchair"),
        APRSSymbol(code: "/*", tocall: "BK", description: "Snowmobile"),
        APRSSymbol(code: "/+", tocall: "BL", description: "Red Cross"),
        APRSSymbol(code: "/,", tocall: "BM", description: "Boy Scouts"),
        APRSSymbol(code: "/-", tocall: "BN", description: "House"),
        APRSSymbol(code: "/.", tocall: "BO", description: "Red X"),
        APRSSymbol(code: "//", tocall: "BP", description: "Red dot"),
        APRSSymbol(code: "/0", tocall: "P0", description: "Circle: 0"),
        APRSSymbol(code: "/1", tocall: "P1", description: "Circle: 1"),
        APRSSymbol(code: "/2", tocall: "P2", description: "Circle: 2"),
        APRSSymbol(code: "/3", tocall: "P3", description: "Circle: 3"),
        APRSSymbol(code: "/4", tocall: "P4", description: "Circle: 4"),
        APRSSymbol(code: "/5", tocall: "P5", description: "Circle: 5"),
        APRSSymbol(code: "/6", tocall: "P6", description: "Circle: 6"),
        APRSSymbol(code: "/7", tocall: "P7", description: "Circle: 7"),
        APRSSymbol(code: "/8", tocall: "P8", description: "Circle: 8"),
        APRSSymbol(code: "/9", tocall: "P9", description: "Circle: 9"),
        APRSSymbol(code: "/:", tocall: "MR", description: "Fire"),
        APRSSymbol(code: "/;", tocall: "MS", description: "Campground"),
        APRSSymbol(code: "/<", tocall: "MT", description: "Motorcycle"),
        APRSSymbol(code: "/=", tocall: "MU", description: "Railroad engine"),
        APRSSymbol(code: "/>", tocall: "MV", description: "Car"),
        APRSSymbol(code: "/?", tocall: "MW", description: "File server"),
        APRSSymbol(code: "/@", tocall: "MX", description: "Hurricane path"),
        APRSSymbol(code: "/A", tocall: "PA", description: "Aid station"),
        APRSSymbol(code: "/B", tocall: "PB", description: "BBS"),
        APRSSymbol(code: "/C", tocall: "PC", description: "Canoe"),
        APRSSymbol(code: "/E", tocall: "PE", description: "Eyeball"),
        APRSSymbol(code: "/F", tocall: "PF", description: "Farm vehicle"),
        APRSSymbol(code: "/G", tocall: "PG", description: "Grid square 3x3"),
        APRSSymbol(code: "/H", tocall: "PH", description: "Hotel"),
        APRSSymbol(code: "/I", tocall: "PI", description: "TCP/IP network"),
        APRSSymbol(code: "/K", tocall: "PK", description: "School"),
        APRSSymbol(code: "/L", tocall: "PL", description: "PC user"),
        APRSSymbol(code: "/M", tocall: "PM", description: "Apple"),
        APRSSymbol(code: "/N", tocall: "PN", description: "NTS station"),
        APRSSymbol(code: "/O", tocall: "PO", description: "Balloon"),
        APRSSymbol(code: "/P", tocall: "PP", description: "Police car"),
        APRSSymbol(code: "/R", tocall: "PR", description: "Recreational vehicle"),
        APRSSymbol(code: "/S", tocall: "PS", description: "Space Shuttle"),
        APRSSymbol(code: "/T", tocall: "PT", description: "SSTV"),
        APRSSymbol(code: "/U", tocall: "PU", description: "Bus"),
        APRSSymbol(code: "/V", tocall: "PV", description: "ATV"),
        APRSSymbol(code: "/W", tocall: "PW", description: "Weather service"),
        APRSSymbol(code: "/X", tocall: "PX", description: "Helicopter"),
        APRSSymbol(code: "/Y", tocall: "PY", description: "Sailboat"),
        APRSSymbol(code: "/Z", tocall: "PZ", description: "Windows flag"),
        APRSSymbol(code: "/[", tocall: "HS", description: "Human"),
        APRSSymbol(code: "/\\", tocall: "HT", description: "DF triangle"),
        APRSSymbol(code: "/]", tocall: "HU", description: "Mailbox"),
        APRSSymbol(code: "/^", tocall: "HV", description: "Large aircraft"),
        APRSSymbol(code: "/_", tocall: "HW", description: "Weather station"),
        APRSSymbol(code: "/`", tocall: "HX", description: "Satellite dish"),
        APRSSymbol(code: "/a", tocall: "LA", description: "Ambulance"),
        APRSSymbol(code: "/b", tocall: "LB", description: "Bicycle"),
        APRSSymbol(code: "/c", tocall: "LC", description: "Incident command"),
        APRSSymbol(code: "/d", tocall: "LD", description: "Fire station"),
        APRSSymbol(code: "/e", tocall: "LE", description: "Horse"),
        APRSSymbol(code: "/f", tocall: "LF", description: "Fire truck"),
        APRSSymbol(code: "/g", tocall: "LG", description: "Glider"),
        APRSSymbol(code: "/h", tocall: "LH", description: "Hospital"),
        APRSSymbol(code: "/i", tocall: "LI", description: "IOTA island"),
        APRSSymbol(code: "/j", tocall: "LJ", description: "Jeep"),
        APRSSymbol(code: "/k", tocall: "LK", description: "Truck"),
        APRSSymbol(code: "/l", tocall: "LL", description: "Laptop"),
        APRSSymbol(code: "/m", tocall: "LM", description: "Mic-E repeater"),
        APRSSymbol(code: "/n", tocall: "LN", description: "Node"),
        APRSSymbol(code: "/o", tocall: "LO", description: "EOC"),
        APRSSymbol(code: "/p", tocall: "LP", description: "Dog"),
        APRSSymbol(code: "/q", tocall: "LQ", description: "Grid square 2x2"),
        APRSSymbol(code: "/r", tocall: "LR", description: "Repeater tower"),
        APRSSymbol(code: "/s", tocall: "LS", description: "Boat"),
        APRSSymbol(code: "/t", tocall: "LT", description: "Truck stop"),
        APRSSymbol(code: "/u", tocall: "LU", description: "Semi truck"),
        APRSSymbol(code: "/v", tocall: "LV", description: "Van"),
        APRSSymbol(code: "/w", tocall: "LW", description: "Water station"),
        APRSSymbol(code: "/x", tocall: "LX", description: "X / Unix"),
        APRSSymbol(code: "/y", tocall: "LY", description: "House + yagi"),
        APRSSymbol(code: "/z", tocall: "LZ", description: "Shelter"),
        // ── Alternate table (\) ───────────────────────────────────────────
        APRSSymbol(code: "\\!", tocall: "OB", description: "Emergency"),
        APRSSymbol(code: "\\#", tocall: "OD", description: "Digipeater (green)"),
        APRSSymbol(code: "\\$", tocall: "OE", description: "Bank / ATM"),
        APRSSymbol(code: "\\&", tocall: "OG", description: "Gateway station"),
        APRSSymbol(code: "\\'", tocall: "OH", description: "Crash / incident"),
        APRSSymbol(code: "\\(", tocall: "OI", description: "Cloudy"),
        APRSSymbol(code: "\\)", tocall: "OJ", description: "Firenet MEO"),
        APRSSymbol(code: "\\*", tocall: "OK", description: "Snow"),
        APRSSymbol(code: "\\+", tocall: "OL", description: "Church"),
        APRSSymbol(code: "\\,", tocall: "OM", description: "Girl Scouts"),
        APRSSymbol(code: "\\-", tocall: "ON", description: "House HF antenna"),
        APRSSymbol(code: "\\.", tocall: "OO", description: "Ambiguous"),
        APRSSymbol(code: "\\/", tocall: "OP", description: "Waypoint"),
        APRSSymbol(code: "\\0", tocall: "A0", description: "IRLP / Echolink"),
        // A8.png not available in symbol set — omitted
        // APRSSymbol(code: "\\8", tocall: "A8", description: "WiFi node"),
        APRSSymbol(code: "\\9", tocall: "A9", description: "Gas station"),
        APRSSymbol(code: "\\:", tocall: "NR", description: "Hail"),
        APRSSymbol(code: "\\;", tocall: "NS", description: "Park / picnic"),
        APRSSymbol(code: "\\<", tocall: "NT", description: "Advisory flag"),
        APRSSymbol(code: "\\>", tocall: "NV", description: "Red car"),
        APRSSymbol(code: "\\?", tocall: "NW", description: "Info kiosk"),
        APRSSymbol(code: "\\@", tocall: "NX", description: "Hurricane"),
        APRSSymbol(code: "\\A", tocall: "AA", description: "White box"),
        APRSSymbol(code: "\\B", tocall: "AB", description: "Blowing snow"),
        APRSSymbol(code: "\\C", tocall: "AC", description: "Coast Guard"),
        APRSSymbol(code: "\\D", tocall: "AD", description: "Drizzling rain"),
        APRSSymbol(code: "\\E", tocall: "AE", description: "Smoke"),
        APRSSymbol(code: "\\F", tocall: "AF", description: "Freezing rain"),
        APRSSymbol(code: "\\G", tocall: "AG", description: "Snow shower"),
        APRSSymbol(code: "\\H", tocall: "AH", description: "Haze"),
        APRSSymbol(code: "\\I", tocall: "AI", description: "Rain shower"),
        APRSSymbol(code: "\\J", tocall: "AJ", description: "Lightning"),
        APRSSymbol(code: "\\K", tocall: "AK", description: "Kenwood HT"),
        APRSSymbol(code: "\\L", tocall: "AL", description: "Lighthouse"),
        APRSSymbol(code: "\\N", tocall: "AN", description: "Navigation buoy"),
        APRSSymbol(code: "\\O", tocall: "AO", description: "Rocket"),
        APRSSymbol(code: "\\P", tocall: "AP", description: "Parking"),
        APRSSymbol(code: "\\Q", tocall: "AQ", description: "Earthquake"),
        APRSSymbol(code: "\\R", tocall: "AR", description: "Restaurant"),
        APRSSymbol(code: "\\S", tocall: "AS", description: "Satellite"),
        APRSSymbol(code: "\\T", tocall: "AT", description: "Thunderstorm"),
        APRSSymbol(code: "\\U", tocall: "AU", description: "Sunny"),
        APRSSymbol(code: "\\V", tocall: "AV", description: "VORTAC"),
        APRSSymbol(code: "\\W", tocall: "AW", description: "NWS site"),
        APRSSymbol(code: "\\X", tocall: "AX", description: "Pharmacy"),
        APRSSymbol(code: "\\[", tocall: "DS", description: "Wall cloud"),
        APRSSymbol(code: "\\^", tocall: "DV", description: "Aircraft"),
        APRSSymbol(code: "\\_", tocall: "DW", description: "Weather site"),
        APRSSymbol(code: "\\`", tocall: "DX", description: "Rain"),
        APRSSymbol(code: "\\a", tocall: "SA", description: "Red diamond"),
        APRSSymbol(code: "\\b", tocall: "SB", description: "Blowing dust"),
        APRSSymbol(code: "\\c", tocall: "SC", description: "CD triangle RACES"),
        APRSSymbol(code: "\\d", tocall: "SD", description: "DX spot"),
        APRSSymbol(code: "\\e", tocall: "SE", description: "Sleet"),
        APRSSymbol(code: "\\f", tocall: "SF", description: "Funnel cloud"),
        APRSSymbol(code: "\\g", tocall: "SG", description: "Gale flags"),
        APRSSymbol(code: "\\h", tocall: "SH", description: "Store"),
        APRSSymbol(code: "\\i", tocall: "SI", description: "Point of interest"),
        APRSSymbol(code: "\\j", tocall: "SJ", description: "Work zone"),
        APRSSymbol(code: "\\k", tocall: "SK", description: "SUV / ATV"),
        APRSSymbol(code: "\\m", tocall: "SM", description: "Value sign"),
        APRSSymbol(code: "\\n", tocall: "SN", description: "Red triangle"),
        APRSSymbol(code: "\\o", tocall: "SO", description: "Small circle"),
        APRSSymbol(code: "\\p", tocall: "SP", description: "Partly cloudy"),
        APRSSymbol(code: "\\r", tocall: "SR", description: "Restrooms"),
        APRSSymbol(code: "\\s", tocall: "SS", description: "Ship"),
        APRSSymbol(code: "\\t", tocall: "ST", description: "Tornado"),
        APRSSymbol(code: "\\u", tocall: "SU", description: "Truck"),
        APRSSymbol(code: "\\v", tocall: "SV", description: "Van"),
        APRSSymbol(code: "\\w", tocall: "SW", description: "Flooding"),
        APRSSymbol(code: "\\y", tocall: "SY", description: "Skywarn"),
        APRSSymbol(code: "\\z", tocall: "SZ", description: "Shelter"),
        APRSSymbol(code: "\\{", tocall: "Q1", description: "Fog"),
    ]
}
