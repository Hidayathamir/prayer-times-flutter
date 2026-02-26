import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart';

/// Holds a single notification message (title + body) from CSV.
class PrayerMessage {
  final String title;
  final String body;
  PrayerMessage({required this.title, required this.body});
}

/// Loads and provides prayer notification messages from CSV assets.
/// Each prayer has 365 messages, one for each day of the year.
class PrayerDataService {
  // Map: prayer key → list of 365 PrayerMessages
  static final Map<String, List<PrayerMessage>> _cache = {};

  /// CSV asset path for each prayer key
  static const Map<String, String> _assetPaths = {
    'Fajr': 'data/notification-for-pray-subuh-merged.csv',
    'Dhuhr': 'data/notification-for-pray-dzuhur-merged.csv',
    'Asr': 'data/notification-for-pray-ashar-merged.csv',
    'Maghrib': 'data/notification-for-pray-maghrib-merged.csv',
    'Isha': 'data/notification-for-pray-isya-merged.csv',
  };

  /// Load all prayer CSVs into memory. Call once at startup.
  static Future<void> loadAll() async {
    for (final entry in _assetPaths.entries) {
      await _loadCsv(entry.key, entry.value);
    }
    debugPrint('[PrayerData] Loaded ${_cache.length} prayer CSV files');
  }

  static Future<void> _loadCsv(String key, String assetPath) async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      final lines = raw
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();

      // Skip header line ("title, body")
      final messages = <PrayerMessage>[];
      for (int i = 1; i < lines.length; i++) {
        final line = lines[i];
        // Split on first comma only — body may contain commas
        final commaIndex = line.indexOf(',');
        if (commaIndex == -1) continue;

        final title = line.substring(0, commaIndex).trim();
        final body = line.substring(commaIndex + 1).trim();
        messages.add(PrayerMessage(title: title, body: body));
      }

      _cache[key] = messages;
      debugPrint('[PrayerData] $key: ${messages.length} messages loaded');
    } catch (e) {
      debugPrint('[PrayerData] Error loading $assetPath: $e');
    }
  }

  /// Get today's message for a given prayer.
  /// Uses day-of-year (0-based) as index, wrapping around.
  static PrayerMessage? getMessageForToday(String prayerKey) =>
      getMessageForDate(prayerKey, DateTime.now());

  /// Get message for a given prayer on [date].
  /// Uses day-of-year (0-based) as index, wrapping around.
  static PrayerMessage? getMessageForDate(String prayerKey, DateTime date) {
    final messages = _cache[prayerKey];
    if (messages == null || messages.isEmpty) return null;

    final dayOfYear = date.difference(DateTime(date.year, 1, 1)).inDays; // 0-based
    final index = dayOfYear % messages.length;

    return messages[index];
  }
}
