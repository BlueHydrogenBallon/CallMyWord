import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Firebase Auth instance provider
final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

/// Auth state stream provider - emits current user or null
final authStateProvider = StreamProvider<User?>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  return auth.authStateChanges();
});

/// Current user provider (synchronous access to current user)
final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(authStateProvider).value;
});

/// Current user ID provider
final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(currentUserProvider)?.uid;
});

/// Auth service provider for actions
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(firebaseAuthProvider));
});

/// Auth service for authentication operations
class AuthService {
  final FirebaseAuth _auth;

  AuthService(this._auth);

  /// Get current user
  User? get currentUser => _auth.currentUser;

  /// Get current user ID
  String? get userId => _auth.currentUser?.uid;

  /// Check if user is signed in
  bool get isSignedIn => _auth.currentUser != null;

  /// Check if user is anonymous
  bool get isAnonymous => _auth.currentUser?.isAnonymous ?? false;

  /// Sign in anonymously
  Future<UserCredential> signInAnonymously() async {
    return await _auth.signInAnonymously();
  }

  /// Sign in with email and password
  Future<UserCredential> signInWithEmail(String email, String password) async {
    return await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  /// Create account with email and password
  Future<UserCredential> createAccount(String email, String password) async {
    return await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  /// Upgrade anonymous account to email/password
  Future<UserCredential> upgradeAnonymousAccount(
    String email,
    String password,
  ) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('No user signed in');
    }
    if (!user.isAnonymous) {
      throw Exception('User is not anonymous');
    }

    final credential = EmailAuthProvider.credential(
      email: email,
      password: password,
    );

    return await user.linkWithCredential(credential);
  }

  /// Sign out
  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Ensure user is signed in (sign in anonymously if not)
  Future<User> ensureSignedIn() async {
    if (_auth.currentUser != null) {
      return _auth.currentUser!;
    }

    final credential = await signInAnonymously();
    return credential.user!;
  }
}
