import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/auth_models.dart';
import '../services/auth_session_manager.dart';
import '../services/secure_store_service.dart';
import '../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  final AuthSessionManager sessionManager;
  final ValueChanged<AuthSession> onLoginSuccess;

  const LoginScreen({
    super.key,
    required this.sessionManager,
    required this.onLoginSuccess,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const String _requiredDomain = 'mindx.net.vn';
  static const String _rememberPasswordKey = 'auth.remember_password_v1';
  static const String _legacyRememberedEmailKey = 'auth.remembered_email_v1';
  static const String _legacyRememberedPasswordKey =
      'auth.remembered_password_v1';
  static const String _rememberedEmailSecureKey = 'secure.remembered_email_v1';
  static const String _rememberedPasswordSecureKey =
      'secure.remembered_password_v1';

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final SecureStoreService _secureStore = const SecureStoreService();
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;
  late final FocusNode _emailFocusNode;

  bool _isSubmitting = false;
  bool _obscurePassword = true;
  bool _rememberPassword = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController();
    _passwordController = TextEditingController();
    _emailFocusNode = FocusNode();
    _emailFocusNode.addListener(_onEmailFocusChanged);
    unawaited(_loadRememberedCredentials());
  }

  @override
  void dispose() {
    _emailFocusNode.removeListener(_onEmailFocusChanged);
    _emailFocusNode.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onEmailFocusChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  bool get _showMindxSuggestion {
    final raw = _emailController.text.trim();
    return _emailFocusNode.hasFocus && raw.isNotEmpty && !raw.contains('@');
  }

  String _normalizeEmailInput(
    String raw, {
    bool appendDefaultDomain = true,
  }) {
    final normalized = raw.trim().toLowerCase();
    if (normalized.isEmpty) {
      return '';
    }

    final atIndex = normalized.indexOf('@');
    if (atIndex < 0) {
      return appendDefaultDomain ? '$normalized@$_requiredDomain' : normalized;
    }

    final localPart = normalized.substring(0, atIndex).trim();
    final domain = normalized.substring(atIndex + 1).trim();
    if (localPart.isEmpty || domain.isEmpty) {
      return '';
    }
    return '$localPart@$domain';
  }

  String _usernameFromEmail(String email) {
    final atIndex = email.indexOf('@');
    if (atIndex <= 0) {
      return '';
    }
    return email.substring(0, atIndex);
  }

  Future<void> _loadRememberedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool(_rememberPasswordKey) ?? false;
    var savedEmail = '';
    var savedPassword = '';
    if (remember) {
      savedEmail = (await _secureStore.read(key: _rememberedEmailSecureKey)) ?? '';
      savedPassword =
          (await _secureStore.read(key: _rememberedPasswordSecureKey)) ?? '';

      // Legacy migration from plain SharedPreferences to secure storage.
      if (savedEmail.isEmpty && savedPassword.isEmpty) {
        final legacyEmail = prefs.getString(_legacyRememberedEmailKey) ?? '';
        final legacyPassword =
            prefs.getString(_legacyRememberedPasswordKey) ?? '';
        if (legacyEmail.isNotEmpty || legacyPassword.isNotEmpty) {
          savedEmail = legacyEmail;
          savedPassword = legacyPassword;
          await _secureStore.write(
            key: _rememberedEmailSecureKey,
            value: savedEmail,
          );
          await _secureStore.write(
            key: _rememberedPasswordSecureKey,
            value: savedPassword,
          );
          await prefs.remove(_legacyRememberedEmailKey);
          await prefs.remove(_legacyRememberedPasswordKey);
        }
      }
    }

    if (!mounted) {
      return;
    }

    final normalizedEmail = _normalizeEmailInput(
      savedEmail,
      appendDefaultDomain: true,
    );
    setState(() {
      _rememberPassword = remember;
      if (remember) {
        _emailController.text = normalizedEmail;
        _passwordController.text = savedPassword;
      }
    });
  }

  Future<void> _saveRememberedCredentials({
    required String email,
    required String password,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (!_rememberPassword) {
      await prefs.setBool(_rememberPasswordKey, false);
      await _secureStore.delete(key: _rememberedEmailSecureKey);
      await _secureStore.delete(key: _rememberedPasswordSecureKey);
      await prefs.remove(_legacyRememberedEmailKey);
      await prefs.remove(_legacyRememberedPasswordKey);
      return;
    }

    await prefs.setBool(_rememberPasswordKey, true);
    await _secureStore.write(key: _rememberedEmailSecureKey, value: email);
    await _secureStore.write(
      key: _rememberedPasswordSecureKey,
      value: password,
    );
    await prefs.remove(_legacyRememberedEmailKey);
    await prefs.remove(_legacyRememberedPasswordKey);
  }

  Future<void> _onRememberPasswordChanged(bool? value) async {
    final next = value ?? false;
    if (next == _rememberPassword) {
      return;
    }

    setState(() {
      _rememberPassword = next;
    });

    final normalizedEmail = _normalizeEmailInput(
      _emailController.text,
      appendDefaultDomain: true,
    );
    await _saveRememberedCredentials(
      email: normalizedEmail,
      password: _passwordController.text,
    );
  }

  void _applyDefaultDomainToEmailField() {
    final current = _emailController.text;
    final normalized = _normalizeEmailInput(
      current,
      appendDefaultDomain: true,
    );
    if (normalized.isEmpty) {
      return;
    }
    if (current.trim().toLowerCase() == normalized) {
      return;
    }
    _emailController.value = TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
    );
  }

  String? _validateEmail(String? value) {
    final normalized = _normalizeEmailInput(
      value ?? '',
      appendDefaultDomain: true,
    );
    if (normalized.isEmpty) {
      return 'Vui lòng nhập email.';
    }

    final atIndex = normalized.indexOf('@');
    if (atIndex <= 0 || atIndex == normalized.length - 1) {
      return 'Email chưa đúng định dạng.';
    }

    final domain = normalized.substring(atIndex + 1);
    if (domain != _requiredDomain) {
      return 'Chỉ hỗ trợ email @$_requiredDomain.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_isSubmitting) {
      return;
    }

    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    _applyDefaultDomainToEmailField();
    final email = _normalizeEmailInput(
      _emailController.text,
      appendDefaultDomain: true,
    );
    final username = _usernameFromEmail(email);
    if (username.isEmpty) {
      setState(() {
        _errorText = 'Email chưa đúng định dạng.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    if (!AppConfig.hasFirebaseApiKey) {
      setState(() {
        _isSubmitting = false;
        _errorText = 'Thiếu Firebase API key trong cấu hình app.';
      });
      return;
    }

    try {
      final session = await widget.sessionManager.signIn(
        apiKey: AppConfig.firebaseApiKey.trim(),
        email: email,
        username: username,
        password: _passwordController.text,
        backendBaseUrl: AppConfig.apiBaseUrl.trim(),
      );

      await _saveRememberedCredentials(
        email: email,
        password: _passwordController.text,
      );

      if (!mounted) {
        return;
      }
      widget.onLoginSuccess(session);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText =
            'Đăng nhập thất bại. Kiểm tra email @$_requiredDomain và mật khẩu.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accents = Theme.of(context).extension<AppAccentColors>()!;
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF06224A),
                    const Color(0xFF114FA3),
                    const Color(0xFF0E8B93),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: -120,
            top: 50,
            child: _SoftOrb(
              size: 240,
              color: Colors.white.withValues(alpha: 0.1),
            ),
          ),
          Positioned(
            right: -100,
            bottom: 40,
            child: _SoftOrb(
              size: 280,
              color: Colors.white.withValues(alpha: 0.11),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  18,
                  topPadding + 6,
                  18,
                  bottomPadding + 12,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.45),
                        width: 1.2,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x40081C3B),
                          blurRadius: 28,
                          offset: Offset(0, 14),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        MediaQuery.sizeOf(context).width < 380 ? 16 : 22,
                        MediaQuery.sizeOf(context).width < 380 ? 18 : 22,
                        MediaQuery.sizeOf(context).width < 380 ? 16 : 22,
                        MediaQuery.sizeOf(context).width < 380 ? 20 : 24,
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            LayoutBuilder(
                              builder: (context, headerConstraints) {
                                final logo = Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color(0xFF175EC3),
                                        Color(0xFF0E8B93),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.school_rounded,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                );
                                final title = Text(
                                  'LMS Smooth Bridge',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        color: accents.ink,
                                        fontWeight: FontWeight.w800,
                                      ),
                                );

                                if (headerConstraints.maxWidth < 340) {
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      logo,
                                      const SizedBox(height: 10),
                                      title,
                                    ],
                                  );
                                }

                                return Row(
                                  children: [
                                    logo,
                                    const SizedBox(width: 12),
                                    Expanded(child: title),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Đăng nhập để quản lý lớp học và theo dõi thu nhập nhanh gọn.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: accents.mutedInk,
                                  ),
                            ),
                            const SizedBox(height: 18),
                            TextFormField(
                              focusNode: _emailFocusNode,
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.email],
                              decoration: InputDecoration(
                                labelText: 'Email',
                                hintText: 'Nhập mã giáo viên của bạn',
                                prefixIcon:
                                    const Icon(Icons.alternate_email_rounded),
                                suffixText: _showMindxSuggestion
                                    ? '@$_requiredDomain'
                                    : null,
                                helperText: _showMindxSuggestion
                                    ? 'Sẽ tự thêm @$_requiredDomain khi đăng nhập.'
                                    : 'Chỉ hỗ trợ email @$_requiredDomain',
                                helperMaxLines: 2,
                              ),
                              validator: _validateEmail,
                              onChanged: (_) {
                                if (_errorText != null) {
                                  setState(() {
                                    _errorText = null;
                                  });
                                  return;
                                }
                                if (_emailFocusNode.hasFocus &&
                                    _rememberPassword &&
                                    _passwordController.text.isNotEmpty) {
                                  setState(() {});
                                  return;
                                }
                                if (_emailFocusNode.hasFocus) {
                                  setState(() {});
                                }
                              },
                              onFieldSubmitted: (_) {
                                _applyDefaultDomainToEmailField();
                                FocusScope.of(context).nextFocus();
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.password],
                              decoration: InputDecoration(
                                labelText: 'Mật khẩu',
                                prefixIcon:
                                    const Icon(Icons.lock_outline_rounded),
                                suffixIcon: IconButton(
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                              validator: (value) {
                                if ((value ?? '').isEmpty) {
                                  return 'Vui lòng nhập mật khẩu.';
                                }
                                return null;
                              },
                              onChanged: (_) {
                                if (_errorText == null) {
                                  return;
                                }
                                setState(() {
                                  _errorText = null;
                                });
                              },
                              onFieldSubmitted: (_) => _submit(),
                            ),
                            const SizedBox(height: 8),
                            CheckboxListTile(
                              value: _rememberPassword,
                              onChanged: _isSubmitting
                                  ? null
                                  : (value) {
                                      unawaited(
                                        _onRememberPasswordChanged(value),
                                      );
                                    },
                              contentPadding: EdgeInsets.zero,
                              dense: false,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: Text(
                                'Nhớ mật khẩu',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (_errorText != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.red.shade100,
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                child: Text(
                                  _errorText!,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Colors.red.shade700,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 18),
                            FilledButton.icon(
                              onPressed: _isSubmitting ? null : _submit,
                              style: FilledButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              icon: _isSubmitting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.login_rounded),
                              label: Text(
                                _isSubmitting
                                    ? 'Đang đăng nhập...'
                                    : 'Đăng nhập',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SoftOrb extends StatelessWidget {
  final double size;
  final Color color;

  const _SoftOrb({
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
      ),
    );
  }
}
