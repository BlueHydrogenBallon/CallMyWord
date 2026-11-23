import 'package:flutter/services.dart';

/// Looks up word definitions from the bundled word list files.
/// Each file has lines in the format: WORD - definition text
/// Results are cached after first load.
class DictionaryService {
  static Map<String, String>? _english;
  static Map<String, String>? _greek;

  static Future<String?> lookup(String word, {required bool isGreek}) async {
    final dict = isGreek
        ? (_greek ??= await _load('functions/src/utils/words_greek.txt'))
        : (_english ??= await _load('functions/src/utils/words_english.txt'));
    return dict[word.toUpperCase()];
  }

  static Future<Map<String, String>> _load(String assetPath) async {
    final contents = await rootBundle.loadString(assetPath);
    final map = <String, String>{};
    for (final line in contents.split('\n')) {
      final idx = line.indexOf(' - ');
      if (idx > 0) {
        final word = line.substring(0, idx).trim().toUpperCase();
        final definition = line.substring(idx + 3).trim();
        if (word.isNotEmpty && definition.isNotEmpty) {
          map[word] = definition;
        }
      }
    }
    return map;
  }
}
