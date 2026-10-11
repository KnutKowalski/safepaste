import Foundation

/// Suchmodi: Exakt (Standard), validierter Regex, Fuzzy ( eigene, winzige
/// Subsequenz-Implementierung statt Fuse-Abhängigkeit).
final class SearchEngine {
  func matches(query: String, item: DisplayItem) -> Bool {
    let subject = item.fullText.isEmpty ? item.preview : item.fullText
    switch AppSettings.searchMode {
    case .exact:
      return subject.localizedCaseInsensitiveContains(query)
    case .regex:
      return regexMatches(query, subject: subject)
    case .fuzzy:
      return fuzzyMatches(query, subject: subject)
    }
  }

  private func regexMatches(_ query: String, subject: String) -> Bool {
    // Ungültiges Muster → sicherer Fallback (Exakt), niemals Abbruch/Stillstand.
    guard let regex = try? NSRegularExpression(pattern: query) else {
      return subject.localizedCaseInsensitiveContains(query)
    }
    let range = NSRange(subject.startIndex..., in: subject)
    return regex.firstMatch(in: subject, range: range) != nil
  }

  private func fuzzyMatches(_ query: String, subject: String) -> Bool {
    let haystack = Array(subject.lowercased().unicodeScalars)
    var needle = query.lowercased().unicodeScalars.makeIterator()
    guard let first = needle.next() else { return true }
    var current = first
    for scalar in haystack {
      if scalar == current {
        if let next = needle.next() {
          current = next
        } else {
          return true
        }
      }
    }
    return false
  }
}
