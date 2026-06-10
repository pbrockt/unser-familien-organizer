/// Parst/serialisiert iCalendar-Objekte (RFC 5545) mit `enough_icalendar`.
///
/// Phase 2: Umwandlung zwischen rohem iCal-Body und den App-Modellen.
///
/// Relevante iCal-Bausteine:
///  - VEVENT          → Kalendertermin
///  - VTODO           → Aufgabe UND Einkaufsartikel
///  - VALARM          → Erinnerung (wird zu lokaler Notification)
///  - RRULE           → Wiederholung (Serientermine)
///  - RELATED-TO      → Unteraufgabe
///  - STATUS:COMPLETED→ abgehakt (Aufgabe/Einkauf)
///  - CATEGORIES      → Kategorie (Einkaufsliste: Obst, Getränke, …)
class IcalParser {
  const IcalParser();

  // TODO(phase2): parseEvents / parseTodos / buildEvent / buildTodo
}
