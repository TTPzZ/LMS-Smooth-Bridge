import 'package:flutter/material.dart';

import 'models/auth_models.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_session_manager.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
    });
  }

  void _onLoginSuccess(AuthSession session) {
    setState(() {
      _session = session;
    });
  }

  Future<void> _onSignOut() async {
    await _sessionManager.signOut();
    if (!mounted) {
      return;
    }
    setState(() {
      _session = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LMS Smooth Bridge',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
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
