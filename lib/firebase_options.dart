import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default Firebase configuration options for the current platform.
///
/// IMPORTANT: This is a placeholder file. You need to configure Firebase:
///
/// 1. Create a Firebase project at https://console.firebase.google.com/
/// 2. Install FlutterFire CLI: dart pub global activate flutterfire_cli
/// 3. Run: flutterfire configure
/// 4. This will replace this file with your actual Firebase credentials
///
/// For more information, see: https://firebase.google.com/docs/flutter/setup
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  // TODO: Replace these placeholder values with your actual Firebase config
  // Run `flutterfire configure` to generate the real values

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDZkX_iM3Lt8sNAss5-pkDjUbRcCHYgacU',
    appId: '1:337700608453:web:dea63cea6d31ff7aaa53ac',
    messagingSenderId: '337700608453',
    projectId: 'call-my-word-1634f',
    authDomain: 'call-my-word-1634f.firebaseapp.com',
    storageBucket: 'call-my-word-1634f.firebasestorage.app',
    measurementId: 'G-NM9LGWP89H',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAHM-IinslUd_cl9jyB59ldQsVVH1HTSxY',
    appId: '1:337700608453:android:42d9b221b884190aaa53ac',
    messagingSenderId: '337700608453',
    projectId: 'call-my-word-1634f',
    storageBucket: 'call-my-word-1634f.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyD1WV6aOHIUjQdJU0IOqP7iSm1-KSsT3lo',
    appId: '1:337700608453:ios:2a1faf57d325697baa53ac',
    messagingSenderId: '337700608453',
    projectId: 'call-my-word-1634f',
    storageBucket: 'call-my-word-1634f.firebasestorage.app',
    iosClientId: '337700608453-rf6sv4mtgbl2l5gf9gjmrk2p1dd0utcc.apps.googleusercontent.com',
    iosBundleId: 'com.callmyword.callMyWord',
  );

}