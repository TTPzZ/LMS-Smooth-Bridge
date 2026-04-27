import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'models/auth_models.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_session_manager.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  runApp(const SmoothBridgeApp());
}

class SmoothBridgeApp extends StatefulWidget {
  const SmoothBridgeApp({super.key});

  @override
  State<SmoothBridgeApp> createState() => _SmoothBridgeAppState();
}

class _SmoothBridgeAppState extends State<SmoothBridgeApp> {
  final AuthSessionManager _sessionManager = AuthSessionManager();

  AuthSession? _session;
  bool _isRestoringSession = true;
  bool _showPendingCommentReminderOnNextHomeOpen = false;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final restored = await _sessionManager.restoreSession();
    if (!mounted) {
      return;
    }

    setState(() {
      _session = restored;
      _isRestoringSession = false;
      _showPendingCommentReminderOnNextHomeOpen = false;
    });
  }

  void _onLoginSuccess(AuthSession session) {
    setState(() {
      _session = session;
      _showPendingCommentReminderOnNextHomeOpen = true;
    });
  }

  Future<void> _onSignOut() async {
    await _sessionManager.signOut();
    if (!mounted) {
      return;
    }
    setState(() {
      _session = null;
      _showPendingCommentReminderOnNextHomeOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LMS Smooth Bridge',
      theme: AppTheme.light(),
      builder: (context, child) {
        if (child == null) {
          return const SizedBox.shrink();
        }

        final mediaQuery = MediaQuery.of(context);
        final clampedTextScaler = mediaQuery.textScaler.clamp(
          minScaleFactor: 0.9,
          maxScaleFactor: 1.25,
        );

        return MediaQuery(
          data: mediaQuery.copyWith(textScaler: clampedTextScaler),
          child: child,
        );
      },
      home: _isRestoringSession
          ? const _BootScreen()
          : (_session == null
              ? LoginScreen(
                  sessionManager: _sessionManager,
                  onLoginSuccess: _onLoginSuccess,
                )
              : HomeScreen(
                  sessionManager: _sessionManager,
                  onSignOut: _onSignOut,
                  showPendingCommentReminderOnLogin:
                      _showPendingCommentReminderOnNextHomeOpen,
                )),
      debugShowCheckedModeBanner: false,
    );
  }
}

class _BootScreen extends StatelessWidget {
  const _BootScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
