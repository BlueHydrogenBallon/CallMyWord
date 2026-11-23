/// Build-time app configuration
///
/// Build the Greek app variant with:
///   flutter build apk --dart-define=DICTIONARY=greek
///   flutter build ipa --dart-define=DICTIONARY=greek
const kDictionary =
    String.fromEnvironment('DICTIONARY', defaultValue: 'english');

bool get kIsGreek => kDictionary == 'greek';
