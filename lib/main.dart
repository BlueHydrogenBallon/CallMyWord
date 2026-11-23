import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'services/ad_service.dart';

/// Set to true to use Firebase Emulators for local development
const bool useEmulators = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Connect to emulators in debug mode
  if (kDebugMode && useEmulators) {
    await _connectToEmulators();
  }

  // Initialize Mobile Ads SDK (not supported on web)
  if (!kIsWeb) {
    await MobileAds.instance.initialize();
  }

  // Create the provider container
  final container = ProviderContainer();

  // Pre-load the first interstitial ad so it's ready after the first game
  if (!kIsWeb) {
    container.read(adServiceProvider).preloadInterstitial();
  }

  // Note: Music cannot autoplay on web browsers due to browser policy.
  // Music will start on first user interaction (e.g., clicking PLAY button)

  runApp(
    // Wrap with ProviderScope for Riverpod
    UncontrolledProviderScope(
      container: container,
      child: const CallMyWordApp(),
    ),
  );
}

/// Connect to Firebase Emulators for local development
Future<void> _connectToEmulators() async {
  // Use localhost for most platforms, 10.0.2.2 for Android emulator
  final host = defaultTargetPlatform == TargetPlatform.android
      ? '10.0.2.2'
      : 'localhost';

  // Connect to Auth Emulator
  await FirebaseAuth.instance.useAuthEmulator(host, 9099);

  // Connect to Firestore Emulator
  FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);

  // Connect to Functions Emulator
  FirebaseFunctions.instance.useFunctionsEmulator(host, 5001);

  // Connect to Realtime Database Emulator
  FirebaseDatabase.instance.useDatabaseEmulator(host, 9000);

  debugPrint('Connected to Firebase Emulators');
}
