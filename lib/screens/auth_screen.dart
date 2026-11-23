import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_strings.dart';
import '../providers/auth_provider.dart';
import '../services/user_service.dart';

/// Authentication screen for login/register
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();

  bool _isLogin = true;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _signInAnonymously() async {
    final nickname = await _showNicknameDialog();
    if (nickname == null) return; // user dismissed

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final authService = ref.read(authServiceProvider);
      final credential = await authService.signInAnonymously();
      final user = credential.user;
      if (user != null) {
        await ref.read(userServiceProvider).ensureUserProfile(
          userId: user.uid,
          defaultDisplayName: nickname,
          isAnonymous: true,
        );
      }
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<String?> _showNicknameDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(S.chooseNickname),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: S.nicknameHint,
            prefixIcon: const Icon(Icons.person_outline),
          ),
          textCapitalization: TextCapitalization.words,
          maxLength: 20,
          autofocus: true,
          onSubmitted: (value) {
            final trimmed = value.trim();
            if (trimmed.isNotEmpty) Navigator.of(ctx).pop(trimmed);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: Text(S.cancel),
          ),
          TextButton(
            onPressed: () {
              final trimmed = controller.text.trim();
              if (trimmed.isNotEmpty) Navigator.of(ctx).pop(trimmed);
            },
            child: Text(S.confirm),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final authService = ref.read(authServiceProvider);

      if (_isLogin) {
        await authService.signInWithEmail(
          _emailController.text.trim(),
          _passwordController.text,
        );
      } else {
        final credential = await authService.createAccount(
          _emailController.text.trim(),
          _passwordController.text,
        );
        final user = credential.user;
        if (user != null) {
          final displayName = _displayNameController.text.trim();
          if (displayName.isNotEmpty) {
            await user.updateDisplayName(displayName);
          }
          await ref.read(userServiceProvider).createUserProfile(
            userId: user.uid,
            displayName: displayName.isNotEmpty ? displayName : 'User',
            isAnonymous: false,
          );
        }
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() {
        _error = _parseError(e.toString());
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _parseError(String error) {
    if (error.contains('user-not-found')) {
      return S.noAccountFound;
    } else if (error.contains('wrong-password')) {
      return S.incorrectPassword;
    } else if (error.contains('email-already-in-use')) {
      return S.accountAlreadyExists;
    } else if (error.contains('weak-password')) {
      return S.weakPassword;
    } else if (error.contains('invalid-email')) {
      return S.invalidEmail;
    }
    return S.authFailed;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isLogin ? S.signIn : S.createAccount),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Guest play option
              OutlinedButton.icon(
                onPressed: _isLoading ? null : _signInAnonymously,
                icon: const Icon(Icons.person_outline),
                label: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(S.playAsGuest),
                ),
              ),

              const SizedBox(height: 24),

              // Divider
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      S.orSeparator,
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),

              const SizedBox(height: 24),

              // Email form
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Username (only for registration)
                    if (!_isLogin) ...[
                      TextFormField(
                        controller: _displayNameController,
                        decoration: InputDecoration(
                          labelText: S.username,
                          hintText: S.nicknameHint,
                          prefixIcon: const Icon(Icons.person_outline),
                        ),
                        textCapitalization: TextCapitalization.words,
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Email
                    TextFormField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        labelText: S.email,
                        hintText: S.emailHint,
                        prefixIcon: const Icon(Icons.email_outlined),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return S.enterEmail;
                        }
                        if (!value.contains('@')) {
                          return S.enterValidEmail;
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    // Password
                    TextFormField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: S.password,
                        hintText: '••••••••',
                        prefixIcon: const Icon(Icons.lock_outlined),
                      ),
                      obscureText: true,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return S.enterPassword;
                        }
                        if (!_isLogin && value.length < 6) {
                          return S.passwordMinLength;
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 24),

                    // Error message
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _error!,
                          style: TextStyle(color: Colors.red.shade700),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Submit button
                    ElevatedButton(
                      onPressed: _isLoading ? null : _submitForm,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(_isLogin ? S.signIn : S.createAccount),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Toggle login/register
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () {
                              setState(() {
                                _isLogin = !_isLogin;
                                _error = null;
                              });
                            },
                      child: Text(
                        _isLogin
                            ? S.noAccountSignUp
                            : S.haveAccountSignIn,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
