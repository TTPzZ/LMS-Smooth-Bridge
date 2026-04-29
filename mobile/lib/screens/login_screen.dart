import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/auth_models.dart';
import '../services/auth_session_manager.dart';
import '../services/public_app_config_service.dart';
import '../services/secure_store_service.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';

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

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  static const String _requiredDomain = 'mindx.net.vn';
  static const Duration _shimmerDuration = Duration(milliseconds: 6500);
  static const Duration _shimmerPauseDuration = Duration(seconds: 2);
  static const String _rememberPasswordKey = 'auth.remember_password_v1';
  static const String _legacyRememberedEmailKey = 'auth.remembered_email_v1';
  static const String _legacyRememberedPasswordKey =
      'auth.remembered_password_v1';
  static const String _rememberedEmailSecureKey = 'secure.remembered_email_v1';
  static const String _rememberedPasswordSecureKey =
      'secure.remembered_password_v1';

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final SecureStoreService _secureStore = const SecureStoreService();
  final PublicAppConfigService _publicAppConfigService =
      PublicAppConfigService();

  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;

  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();

  bool _isSubmitting = false;
  bool _obscurePassword = true;
  bool _rememberPassword = false;
  String? _errorText;

  late AnimationController _entranceController;
  late AnimationController _shimmerController;
  late AnimationController _bgController;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController();
    _passwordController = TextEditingController();

    _emailFocusNode.addListener(() => setState(() {}));
    _passwordFocusNode.addListener(() => setState(() {}));

    unawaited(_loadRememberedCredentials());

    _entranceController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500));

    // Tốc độ lướt chéo của ánh sáng (3.5 giây là mức đằm, mượt)
    _shimmerController =
        AnimationController(vsync: this, duration: _shimmerDuration);
    unawaited(_runShimmerLoop());

    // Nền chuyển động thở chậm 30 giây
    _bgController =
        AnimationController(vsync: this, duration: const Duration(seconds: 30))
          ..repeat(reverse: true);

    Timer(const Duration(milliseconds: 100), () {
      if (mounted) _entranceController.forward();
    });
  }

  @override
  void dispose() {
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _entranceController.dispose();
    _shimmerController.dispose();
    _bgController.dispose();
    super.dispose();
  }

  Future<void> _runShimmerLoop() async {
    while (mounted) {
      try {
        await _shimmerController.forward(from: 0);
      } on TickerCanceled {
        return;
      }
      if (!mounted) return;
      await Future<void>.delayed(_shimmerPauseDuration);
    }
  }

  // =========================================================================
  // LOGIC
  // =========================================================================

  bool get _showMindxSuggestion {
    final raw = _emailController.text.trim();
    return _emailFocusNode.hasFocus && raw.isNotEmpty && !raw.contains('@');
  }

  String _normalizeEmailInput(String raw, {bool appendDefaultDomain = true}) {
    final normalized = raw.trim().toLowerCase();
    if (normalized.isEmpty) return '';
    final atIndex = normalized.indexOf('@');
    if (atIndex < 0) {
      return appendDefaultDomain ? '$normalized@$_requiredDomain' : normalized;
    }
    final localPart = normalized.substring(0, atIndex).trim();
    final domain = normalized.substring(atIndex + 1).trim();
    if (localPart.isEmpty || domain.isEmpty) return '';
    return '$localPart@$domain';
  }

  String _usernameFromEmail(String email) {
    final atIndex = email.indexOf('@');
    if (atIndex <= 0) return '';
    return email.substring(0, atIndex);
  }

  Future<String> _resolveFirebaseApiKey(String backendBaseUrl) async {
    if (AppConfig.hasFirebaseApiKey) return AppConfig.firebaseApiKey.trim();
    try {
      return await _publicAppConfigService.fetchFirebaseApiKey(backendBaseUrl);
    } catch (_) {
      return '';
    }
  }

  Future<void> _loadRememberedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool(_rememberPasswordKey) ?? false;
    var savedEmail = '';
    var savedPassword = '';
    if (remember) {
      savedEmail =
          (await _secureStore.read(key: _rememberedEmailSecureKey)) ?? '';
      savedPassword =
          (await _secureStore.read(key: _rememberedPasswordSecureKey)) ?? '';
      if (savedEmail.isEmpty && savedPassword.isEmpty) {
        final legacyEmail = prefs.getString(_legacyRememberedEmailKey) ?? '';
        final legacyPassword =
            prefs.getString(_legacyRememberedPasswordKey) ?? '';
        if (legacyEmail.isNotEmpty || legacyPassword.isNotEmpty) {
          savedEmail = legacyEmail;
          savedPassword = legacyPassword;
          await _secureStore.write(
              key: _rememberedEmailSecureKey, value: savedEmail);
          await _secureStore.write(
              key: _rememberedPasswordSecureKey, value: savedPassword);
          await prefs.remove(_legacyRememberedEmailKey);
          await prefs.remove(_legacyRememberedPasswordKey);
        }
      }
    }
    if (!mounted) return;
    final normalizedEmail =
        _normalizeEmailInput(savedEmail, appendDefaultDomain: true);
    setState(() {
      _rememberPassword = remember;
      if (remember) {
        _emailController.text = normalizedEmail;
        _passwordController.text = savedPassword;
      }
    });
  }

  Future<void> _saveRememberedCredentials(
      {required String email, required String password}) async {
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
        key: _rememberedPasswordSecureKey, value: password);
    await prefs.remove(_legacyRememberedEmailKey);
    await prefs.remove(_legacyRememberedPasswordKey);
  }

  Future<void> _onRememberPasswordChanged(bool? value) async {
    final next = value ?? false;
    if (next == _rememberPassword) return;
    setState(() => _rememberPassword = next);
    final normalizedEmail =
        _normalizeEmailInput(_emailController.text, appendDefaultDomain: true);
    await _saveRememberedCredentials(
        email: normalizedEmail, password: _passwordController.text);
  }

  void _applyDefaultDomainToEmailField() {
    final current = _emailController.text;
    final normalized = _normalizeEmailInput(current, appendDefaultDomain: true);
    if (normalized.isEmpty || current.trim().toLowerCase() == normalized) {
      return;
    }
    _emailController.value = TextEditingValue(
        text: normalized,
        selection: TextSelection.collapsed(offset: normalized.length));
  }

  String? _validateEmail(String? value) {
    final normalized =
        _normalizeEmailInput(value ?? '', appendDefaultDomain: true);
    if (normalized.isEmpty) return 'Vui lòng nhập email.';
    final atIndex = normalized.indexOf('@');
    if (atIndex <= 0 || atIndex == normalized.length - 1) {
      return 'Email chưa đúng định dạng.';
    }
    if (normalized.substring(atIndex + 1) != _requiredDomain) {
      return 'Chỉ hỗ trợ email @$_requiredDomain.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    _applyDefaultDomainToEmailField();
    final email =
        _normalizeEmailInput(_emailController.text, appendDefaultDomain: true);
    final username = _usernameFromEmail(email);
    if (username.isEmpty) {
      setState(() => _errorText = 'Email chưa đúng định dạng.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });
    final backendBaseUrl = AppConfig.apiBaseUrl.trim();
    final firebaseApiKey = await _resolveFirebaseApiKey(backendBaseUrl);
    if (firebaseApiKey.isEmpty) {
      setState(() {
        _isSubmitting = false;
        _errorText = 'Thiếu Firebase API key.';
      });
      return;
    }
    try {
      final session = await widget.sessionManager.signIn(
          apiKey: firebaseApiKey,
          email: email,
          username: username,
          password: _passwordController.text,
          backendBaseUrl: backendBaseUrl);
      await _saveRememberedCredentials(
          email: email, password: _passwordController.text);
      if (!mounted) return;
      widget.onLoginSuccess(session);
    } catch (_) {
      if (!mounted) return;
      setState(
          () => _errorText = 'Đăng nhập thất bại. Kiểm tra lại thông tin.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // =========================================================================
  // UI - XÓA KÍNH MỜ, ĐỔI SANG THIẾT KẾ PHẲNG & ÁNH SÁNG LƯỚT CHÉO
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    final accents = Theme.of(context).extension<AppAccentColors>()!;
    final responsive = AppResponsive.of(context);
    final theme = Theme.of(context);

    final cardMaxWidth = responsive.clampWidth(
        320, responsive.width * (responsive.isExpanded ? 0.45 : 0.88), 460);
    final innerPadding = responsive.isCompact ? 24.0 : 36.0;

    const accentRed = Color(0xFFD32F2F);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: const Color(0xFFFFFBFB),
        body: Stack(
          children: [
            Positioned.fill(child: _buildAnimatedBackground(responsive)),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(responsive.pageHorizontalPadding,
                      20, responsive.pageHorizontalPadding, 30),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: cardMaxWidth),
                    child: _build3DEntrance(
                      child: _buildFlatForm(
                          context, accents, theme, innerPadding, accentRed),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _build3DEntrance({required Widget child}) {
    return AnimatedBuilder(
      animation: _entranceController,
      builder: (context, child) {
        final opacity = Curves.easeOut.transform(_entranceController.value);
        final scale =
            0.95 + (0.05 * Curves.easeOut.transform(_entranceController.value));
        final angle =
            (1.0 - Curves.easeOutBack.transform(_entranceController.value)) *
                -math.pi /
                24; // Giảm nhẹ độ xoay cho tinh tế

        return Opacity(
          opacity: opacity,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..scaleByDouble(scale, scale, 1, 1)
              ..rotateX(angle),
            child: child,
          ),
        );
      },
      child: child,
    );
  }

  // TẠO FORM PHẲNG, SẠCH (KHÔNG DÙNG KÍNH MỜ)
  Widget _buildFlatForm(BuildContext context, AppAccentColors accents,
      ThemeData theme, double padding, Color accentColor) {
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: Colors.white, // Nền trắng tinh, phẳng
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
            color: const Color(0xFFFDE4E4), width: 1.5), // Viền đỏ siêu nhạt
        boxShadow: [
          BoxShadow(
              color: accentColor.withValues(alpha: 0.08),
              blurRadius: 40,
              spreadRadius: 5,
              offset: const Offset(0, 10)),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context, accents, accentColor),
            const SizedBox(height: 36),
            _buildNeonInput(
                controller: _emailController,
                focusNode: _emailFocusNode,
                label: 'EMAIL',
                hint: 'Mã giáo viên',
                icon: Icons.alternate_email_rounded,
                neonColor: accentColor,
                isEmail: true),
            const SizedBox(height: 20),
            _buildNeonInput(
                controller: _passwordController,
                focusNode: _passwordFocusNode,
                label: 'MẬT KHẨU',
                hint: '••••••',
                icon: Icons.lock_outline_rounded,
                neonColor: accentColor,
                isPassword: true),
            const SizedBox(height: 20),
            _buildRunningLightCheckbox(accentColor),
            _buildErrorBlock(),
            const SizedBox(height: 32),
            _buildSubmitButton(accentColor),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
      BuildContext context, AppAccentColors accents, Color accentColor) {
    return Column(
      children: [
        _buildCyberLogo(accentColor),
        const SizedBox(height: 20),
        Text(
          'LMS Smooth Bridge',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: const Color(0xFF8E1B1B),
                fontWeight: FontWeight.w900,
                letterSpacing: -1.0,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Quản lý lớp học thông minh.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF8E1B1B).withValues(alpha: 0.7),
                height: 1.4,
              ),
        ),
      ],
    );
  }

  // LOGO VỚI ÁNH SÁNG LƯỚT CHÉO
  Widget _buildCyberLogo(Color accentColor) {
    return Container(
      width: 70,
      height: 70,
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4F4), // Nền tĩnh màu hường nhạt
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: accentColor.withValues(alpha: 0.3), width: 1.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            Center(
              child: Icon(Icons.school_rounded, color: accentColor, size: 40),
            ),
            // Ánh sáng lướt chéo qua logo
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _shimmerController,
                builder: (context, child) {
                  // Chạy từ -1.5 đến 2.5 để thoát hẳn ra khỏi viền rồi mới vòng lại (hết giật)
                  final pos = -1.5 + (4.0 * _shimmerController.value);
                  return Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(pos - 0.5, pos - 0.5),
                        end: Alignment(pos + 0.5, pos + 0.5),
                        colors: [
                          Colors.white.withValues(alpha: 0.0),
                          Colors.white.withValues(alpha: 0.6), // Vệt sáng trắng
                          Colors.white.withValues(alpha: 0.0),
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNeonInput(
      {required TextEditingController controller,
      required FocusNode focusNode,
      required String label,
      required String hint,
      required IconData icon,
      required Color neonColor,
      bool isPassword = false,
      bool isEmail = false}) {
    final hasFocus = focusNode.hasFocus;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(label,
              style: TextStyle(
                  color: hasFocus
                      ? neonColor
                      : const Color(0xFF8E1B1B).withValues(alpha: 0.6),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  letterSpacing: 1.0)),
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8F8), // Nền form sáng sủa hơn
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hasFocus
                  ? neonColor
                  : const Color(0xFFD32F2F).withValues(alpha: 0.15),
              width: hasFocus ? 2.0 : 1.0,
            ),
            boxShadow: hasFocus
                ? [
                    BoxShadow(
                        color: neonColor.withValues(alpha: 0.15),
                        blurRadius: 10,
                        spreadRadius: 0)
                  ]
                : [],
          ),
          child: TextFormField(
            focusNode: focusNode,
            controller: controller,
            obscureText: isPassword ? _obscurePassword : false,
            keyboardType:
                isEmail ? TextInputType.emailAddress : TextInputType.text,
            style: const TextStyle(color: Color(0xFF2B1A1A), fontSize: 16),
            cursorColor: neonColor,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                  color: const Color(0xFF8E1B1B).withValues(alpha: 0.4)),
              prefixIcon: Icon(icon,
                  color: hasFocus
                      ? neonColor
                      : const Color(0xFF9D4A4A).withValues(alpha: 0.5)),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              filled: true,
              fillColor: Colors.transparent,
              suffixIcon: isEmail && _showMindxSuggestion
                  ? Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Center(
                          widthFactor: 1,
                          child: Text('@$_requiredDomain',
                              style: TextStyle(
                                  color: neonColor,
                                  fontWeight: FontWeight.bold))))
                  : isPassword
                      ? IconButton(
                          icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: const Color(0xFFA34C4C)),
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword))
                      : null,
            ),
            validator: isEmail
                ? _validateEmail
                : (value) =>
                    (value ?? '').isEmpty ? 'Vui lòng nhập mật khẩu.' : null,
            onChanged: (_) {
              if (_errorText != null) setState(() => _errorText = null);
              if (isEmail) setState(() {});
            },
          ),
        ),
      ],
    );
  }

  // CHECKBOX VỚI ÁNH SÁNG LƯỚT CHÉO THEO NHỊP NÚT BẤM
// CHECKBOX PHẲNG - ÁNH SÁNG CHẠY VÒNG QUANH VIỀN
  Widget _buildRunningLightCheckbox(Color neonColor) {
    return GestureDetector(
      onTap: _isSubmitting
          ? null
          : () {
              unawaited(_onRememberPasswordChanged(!_rememberPassword));
            },
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _shimmerController,
            builder: (context, child) {
              return Container(
                width: 24,
                height: 24,
                // Hoàn toàn phẳng, không có BoxShadow (bỏ cảm giác gương/phát sáng)
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: _rememberPassword ? neonColor : Colors.transparent,
                ),
                child: _rememberPassword
                    ? const Icon(Icons.check, size: 18, color: Colors.white)
                    : Stack(
                        children: [
                          // 1. Lớp viền nền màu xám/đỏ siêu nhạt tĩnh
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: neonColor.withValues(alpha: 0.2),
                                  width: 1.5),
                            ),
                          ),
                          // 2. Vệt sáng lướt vòng tròn quanh viền
                          Positioned.fill(
                            child: ShaderMask(
                              shaderCallback: (rect) {
                                // Nhân 2 chu kỳ quay để tốc độ lướt viền vừa phải (êm ái)
                                final rotation =
                                    _shimmerController.value * 2 * math.pi;
                                return SweepGradient(
                                  colors: [
                                    neonColor.withValues(alpha: 0.0),
                                    neonColor, // Đỉnh vệt sáng
                                    neonColor.withValues(alpha: 0.0),
                                  ],
                                  stops: const [
                                    0.0,
                                    0.15,
                                    0.3
                                  ], // Vệt sáng chiếm 1 góc nhỏ trên viền
                                  transform: GradientRotation(rotation),
                                ).createShader(rect);
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  // Viền trắng để ShaderMask "nhuộm" màu vệt sáng lên
                                  border: Border.all(
                                      color: Colors.white, width: 1.5),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              );
            },
          ),
          const SizedBox(width: 12),
          Text('Ghi nhớ đăng nhập',
              style: TextStyle(
                  color: const Color(0xFF8E1B1B).withValues(alpha: 0.9),
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildErrorBlock() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      child: _errorText == null
          ? const SizedBox.shrink()
          : Container(
              margin: const EdgeInsets.only(top: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.2))),
              child: Row(children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 20),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(_errorText!,
                        style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)))
              ]),
            ),
    );
  }

  // NÚT BẤM PHẲNG + ÁNH SÁNG CHÉO MƯỢT MÀ
  Widget _buildSubmitButton(Color neonColor) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: neonColor.withValues(alpha: 0.25),
              blurRadius: 15,
              spreadRadius: 0,
              offset: const Offset(0, 5))
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            // Lớp nền tĩnh màu đỏ
            Positioned.fill(
              child: DecoratedBox(decoration: BoxDecoration(color: neonColor)),
            ),

            // Lớp ánh sáng lướt qua (KHÔNG GIẬT KHẤC)
            if (!_isSubmitting)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _shimmerController,
                  builder: (context, child) {
                    // Chạy từ -1.5 đến 2.5 để vệt sáng đi hẳn ra ngoài nút
                    final pos = -1.5 + (4.0 * _shimmerController.value);
                    return Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment(pos - 0.5, pos - 0.5),
                          end: Alignment(pos + 0.5, pos + 0.5),
                          colors: [
                            Colors.white.withValues(alpha: 0.0),
                            Colors.white.withValues(
                                alpha: 0.35), // Dải sáng trắng lướt qua
                            Colors.white.withValues(alpha: 0.0),
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                    );
                  },
                ),
              ),

            Positioned.fill(
              child: FilledButton(
                onPressed: _isSubmitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            strokeWidth: 3, color: Colors.white))
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                            Text('ĐĂNG NHẬP',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.0)),
                            SizedBox(width: 10),
                            Icon(Icons.arrow_forward_rounded,
                                color: Colors.white, size: 20)
                          ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedBackground(AppResponsive responsive) {
    const baseWhite = Color(0xFFFFFBFB);
    const accentRose = Color(0xFFFFE1E1);

    return Container(
      color: baseWhite,
      child: AnimatedBuilder(
        animation: _bgController,
        builder: (context, child) {
          final breath = _bgController.value;
          return Stack(
            children: [
              const Positioned.fill(
                  child: DecoratedBox(
                      decoration: BoxDecoration(
                          gradient: RadialGradient(
                              colors: [accentRose, baseWhite],
                              center: Alignment.center,
                              radius: 1.2)))),
              _buildSoftOrb(responsive.width * 0.1 - (20 * breath),
                  responsive.height * 0.2 + (10 * breath),
                  size: 250 + (20 * breath),
                  alpha: 0.08,
                  color: const Color(0xFFF8B4B4)),
              _buildSoftOrb(responsive.width * 0.7 + (15 * breath),
                  responsive.height * 0.6 - (15 * breath),
                  size: 300 - (10 * breath),
                  alpha: 0.06,
                  color: const Color(0xFFFFC2C2)),
              _buildSoftOrb(responsive.width * 0.4, responsive.height * 0.8,
                  size: 200 + (30 * breath),
                  alpha: 0.08,
                  color: const Color(0xFFD32F2F)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSoftOrb(double x, double y,
      {required double size,
      required double alpha,
      Color color = const Color(0xFFD32F2F)}) {
    return Positioned(
      left: x,
      top: y,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0)
            ], stops: const [
              0.5,
              1.0
            ]),
          ),
        ),
      ),
    );
  }
}
