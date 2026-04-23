import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/auth_models.dart';
import '../services/auth_session_manager.dart';
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
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;

  bool _isSubmitting = false;
  bool _obscurePassword = true;
  bool _didEditUsername = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String _usernameFromEmail(String email) {
    final normalized = email.trim();
    if (normalized.isEmpty) {
      return '';
    }
    final atIndex = normalized.indexOf('@');
    if (atIndex <= 0) {
      return normalized;
    }
    return normalized.substring(0, atIndex);
  }

  Future<void> _submit() async {
    if (_isSubmitting) {
      return;
    }

    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
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

    final email = _emailController.text.trim();
    final enteredUsername = _usernameController.text.trim();
    final resolvedUsername = enteredUsername.isNotEmpty
        ? enteredUsername
        : _usernameFromEmail(email);

    if (resolvedUsername.isEmpty) {
      setState(() {
        _isSubmitting = false;
        _errorText = 'Vui lòng nhập tên đăng nhập.';
      });
      return;
    }

    try {
      final session = await widget.sessionManager.signIn(
        apiKey: AppConfig.firebaseApiKey.trim(),
        email: email,
        username: resolvedUsername,
        password: _passwordController.text,
        backendBaseUrl: AppConfig.apiBaseUrl.trim(),
      );

      if (!mounted) {
        return;
      }
      widget.onLoginSuccess(session);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = 'Đăng nhập thất bại. Kiểm tra thông tin và thử lại.';
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
                    Colors.blue.shade900,
                    Colors.blue.shade600,
                    const Color(0xFF1BA5A5),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: -100,
            top: 70,
            child: _SoftOrb(
              size: 230,
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
          Positioned(
            right: -80,
            bottom: 60,
            child: _SoftOrb(
              size: 260,
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                    18, topPadding + 6, 18, bottomPadding + 10),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'LMS Smooth Bridge',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    color: accents.ink,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Đăng nhập để quản lý lớp học và theo dõi thu nhập nhanh gọn.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: accents.mutedInk,
                                  ),
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                hintText: 'name@example.com',
                              ),
                              validator: (value) {
                                final email = (value ?? '').trim();
                                if (email.isEmpty) {
                                  return 'Vui lòng nhập email.';
                                }
                                if (!email.contains('@')) {
                                  return 'Email chưa đúng định dạng.';
                                }
                                return null;
                              },
                              onChanged: (value) {
                                if (_didEditUsername) {
                                  return;
                                }
                                final derived = _usernameFromEmail(value);
                                if (_usernameController.text != derived) {
                                  _usernameController.text = derived;
                                }
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _usernameController,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Tên đăng nhập',
                                hintText: 'Nhập tên đăng nhập LMS',
                                helperText: 'Tự động lấy từ email, có thể sửa.',
                              ),
                              validator: (value) {
                                if ((value ?? '').trim().isEmpty) {
                                  return 'Vui lòng nhập tên đăng nhập.';
                                }
                                return null;
                              },
                              onChanged: (_) {
                                _didEditUsername = true;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.done,
                              decoration: InputDecoration(
                                labelText: 'Mật khẩu',
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
                              onFieldSubmitted: (_) => _submit(),
                            ),
                            if (_errorText != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border:
                                      Border.all(color: Colors.red.shade100),
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
