import Foundation

/// Nombre décimal à la française : virgule décimale (« 12,3 »).
func frDecimal(_ v: Double, digits: Int = 1) -> String {
    String(format: "%.\(digits)f", v).replacingOccurrences(of: ".", with: ",")
}

/// Entier avec espace fine insécable entre les milliers dès 4 chiffres
/// (« 1 054 »).
func frThousands(_ n: Int) -> String {
    let digits = String(abs(n))
    guard digits.count >= 4 else { return String(n) }
    var out = ""
    for (i, ch) in digits.reversed().enumerated() {
        if i > 0, i % 3 == 0 { out.append("\u{202F}") }
        out.append(ch)
    }
    return (n < 0 ? "-" : "") + String(out.reversed())
}
