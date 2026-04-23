import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/api_models.dart';
import '../models/auth_models.dart';
import '../services/auth_session_manager.dart';
import '../services/backend_api_service.dart';

const String _defaultApiBase = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:3000/api',
);

class HomeScreen extends StatefulWidget {
  final AuthSessionManager sessionManager;
  final Future<void> Function() onSignOut;

  const HomeScreen({
    super.key,
    required this.sessionManager,
    required this.onSignOut,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final TextEditingController _baseUrlController;
  late final TextEditingController _usernameController;
  late final TextEditingController _monthController;
  late final TextEditingController _yearController;
  late BackendApiService _api;

  late Future<List<ClassSummary>> _classesFuture;
  late Future<List<ReminderItem>> _remindersFuture;
  late Future<PayrollResponse> _payrollFuture;

  late AuthSession _session;
  bool _isHandlingAuthFailure = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final currentSession = widget.sessionManager.currentSession;
    if (currentSession == null) {
      throw StateError('HomeScreen requires an active session.');
    }

    _session = currentSession;
    _baseUrlController = TextEditingController(
      text: _session.backendBaseUrl.isEmpty
          ? _defaultApiBase
          : _session.backendBaseUrl,
    );
    _usernameController = TextEditingController();
    _monthController = TextEditingController(text: now.month.toString());
    _yearController = TextEditingController(text: now.year.toString());

    _api = BackendApiService(
      baseUrl: _baseUrlController.text.trim(),
      idTokenProvider: _provideIdToken,
    );
    _reloadAll();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _usernameController.dispose();
    _monthController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  Future<String?> _provideIdToken({bool forceRefresh = false}) async {
    try {
      final previousSession = _session;
      final token = await widget.sessionManager.getValidIdToken(
        forceRefresh: forceRefresh,
      );
      final latestSession = widget.sessionManager.currentSession;
      if (latestSession != null &&
          latestSession != previousSession &&
          mounted) {
        setState(() {
          _session = latestSession;
        });
      }
      return token;
    } catch (_) {
      await _handleAuthFailure();
      rethrow;
    }
  }

  Future<void> _handleAuthFailure() async {
    if (_isHandlingAuthFailure) {
      return;
    }
    _isHandlingAuthFailure = true;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Session expired. Please sign in again.'),
        ),
      );
    }

    await widget.onSignOut();
  }

  Future<void> _applyConfigAndReload() async {
    final raw = _baseUrlController.text.trim();
    if (raw.isEmpty) {
      return;
    }

    final updatedSession =
        await widget.sessionManager.updateBackendBaseUrl(raw);
    if (!mounted) {
      return;
    }

    setState(() {
      _session = updatedSession;
      _api = BackendApiService(
        baseUrl: raw,
        idTokenProvider: _provideIdToken,
      );
    });
    _reloadAll();
  }

  void _reloadAll() {
    setState(() {
      _classesFuture = _api.getClasses(activeOnly: false);
      _remindersFuture = _api.getAttendanceReminders(lookAheadMinutes: 240);
      _payrollFuture = _api.getMonthlyPayroll(
        month: int.tryParse(_monthController.text) ?? DateTime.now().month,
        year: int.tryParse(_yearController.text) ?? DateTime.now().year,
        username: _usernameController.text.trim().isEmpty
            ? null
            : _usernameController.text.trim(),
      );
    });
  }

  Future<void> _forceRefreshToken() async {
    try {
      final refreshed = await widget.sessionManager.ensureSession(
        forceRefresh: true,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _session = refreshed;
      });
      _reloadAll();

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Token refreshed successfully.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Refresh failed: $error')),
      );
    }
  }

  String _formatDateTime(String? iso) {
    if (iso == null || iso.isEmpty) {
      return '-';
    }
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) {
      return iso;
    }
    return DateFormat('yyyy-MM-dd HH:mm').format(parsed.toLocal());
  }

  String _formatExpiry(AuthSession session) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final remainMs = session.expiresAtMs - now;
    final remainMinutes = (remainMs / 60000).floor();

    if (remainMinutes < 0) {
      return '${DateFormat('yyyy-MM-dd HH:mm:ss').format(session.expiresAt.toLocal())} (expired)';
    }
    return '${DateFormat('yyyy-MM-dd HH:mm:ss').format(session.expiresAt.toLocal())} (T-${remainMinutes}m)';
  }

  Widget _buildTokenBlock({
    required String label,
    required String value,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black26),
            borderRadius: BorderRadius.circular(8),
            color: Colors.black.withValues(alpha: 0.02),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAuthPanel() {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Auth Session',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text('Email: ${_session.email}'),
            Text('Token expires: ${_formatExpiry(_session)}'),
            const SizedBox(height: 8),
            _buildTokenBlock(label: 'id_token', value: _session.idToken),
            const SizedBox(height: 8),
            _buildTokenBlock(
              label: 'refresh_token',
              value: _session.refreshToken,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _forceRefreshToken,
                  icon: const Icon(Icons.token),
                  label: const Text('Force Refresh Token'),
                ),
                OutlinedButton.icon(
                  onPressed: widget.onSignOut,
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign Out'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigPanel() {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Backend Config',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _baseUrlController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'API Base URL',
                hintText: 'http://10.0.2.2:3000/api',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 140,
                  child: TextField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Username',
                      isDense: true,
                    ),
                  ),
                ),
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: _monthController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Month',
                      isDense: true,
                    ),
                  ),
                ),
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _yearController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Year',
                      isDense: true,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _applyConfigAndReload,
                  icon: const Icon(Icons.sync),
                  label: const Text('Reload'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClassesTab() {
    return FutureBuilder<List<ClassSummary>>(
      future: _classesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ErrorView(message: snapshot.error.toString());
        }

        final classes = snapshot.data ?? const [];
        if (classes.isEmpty) {
          return const _EmptyView(message: 'No classes found.');
        }

        return ListView.separated(
          itemCount: classes.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final cls = classes[index];
            final next = cls.nextAttendanceWindow;
            return ListTile(
              title: Text(cls.className),
              subtitle: Text(
                'Status: ${cls.status ?? '-'}\n'
                'Students: ${cls.totalStudents} | Slots: ${cls.totalSlots}\n'
                'End date: ${_formatDateTime(cls.classEndDate)}\n'
                'Next attendance: ${next != null ? _formatDateTime(next.attendanceOpenAt) : '-'}',
              ),
              isThreeLine: true,
            );
          },
        );
      },
    );
  }

  Widget _buildRemindersTab() {
    return FutureBuilder<List<ReminderItem>>(
      future: _remindersFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ErrorView(message: snapshot.error.toString());
        }

        final reminders = snapshot.data ?? const [];
        if (reminders.isEmpty) {
          return const _EmptyView(
              message: 'No reminder slots in look-ahead window.');
        }

        return ListView.separated(
          itemCount: reminders.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final item = reminders[index];
            return ListTile(
              leading: Icon(
                item.isWindowOpen ? Icons.alarm_on : Icons.schedule,
                color: item.isWindowOpen ? Colors.green : Colors.orange,
              ),
              title: Text(item.className),
              subtitle: Text(
                'Role slot: ${item.slotIndex ?? '-'} | Students: ${item.totalStudentsInSlot}\n'
                'Open: ${_formatDateTime(item.attendanceOpenAt)}\n'
                'Close: ${_formatDateTime(item.attendanceCloseAt)}',
              ),
              trailing: Text(
                item.isWindowOpen
                    ? 'OPEN'
                    : 'T-${item.minutesUntilWindowOpen}m',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              isThreeLine: true,
            );
          },
        );
      },
    );
  }

  Widget _buildPayrollTab() {
    return FutureBuilder<PayrollResponse>(
      future: _payrollFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ErrorView(message: snapshot.error.toString());
        }
        final payroll = snapshot.data;
        if (payroll == null) {
          return const _EmptyView(message: 'No payroll data.');
        }

        return ListView(
          children: [
            Card(
              margin: const EdgeInsets.all(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Payroll ${payroll.month}/${payroll.year}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                        'Total taught slots: ${payroll.summary.totalTaughtSlots}'),
                    Text('Total classes: ${payroll.summary.totalClasses}'),
                    Text('Total hours: ${payroll.summary.totalHours}'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: payroll.summary.byRole
                          .map(
                            (role) => Chip(
                              label: Text(
                                '${role.role}: ${role.slotCount} slots (${role.totalHours}h)',
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
            ...payroll.classes.map(
              (cls) => Card(
                margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: ExpansionTile(
                  title: Text(cls.className),
                  subtitle: Text(
                    '${cls.taughtSlotCount} slots | ${cls.totalHours}h | ${cls.roles.join(', ')}',
                  ),
                  children: cls.slots
                      .map(
                        (slot) => ListTile(
                          dense: true,
                          title: Text(
                            'Slot ${slot.slotIndex ?? '-'} - ${slot.attendanceStatus}',
                          ),
                          subtitle: Text(
                            '${_formatDateTime(slot.startTime)} -> ${_formatDateTime(slot.endTime)}\n'
                            'Role: ${slot.roleShortName ?? slot.roleName ?? 'UNKNOWN'} | ${slot.durationHours}h',
                          ),
                          isThreeLine: true,
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('LMS Smooth Bridge'),
          actions: [
            IconButton(
              onPressed: widget.onSignOut,
              icon: const Icon(Icons.logout),
              tooltip: 'Sign out',
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Classes'),
              Tab(text: 'Reminders'),
              Tab(text: 'Payroll'),
            ],
          ),
        ),
        body: Column(
          children: [
            _buildConfigPanel(),
            _buildAuthPanel(),
            const Divider(height: 1),
            Expanded(
              child: TabBarView(
                children: [
                  _buildClassesTab(),
                  _buildRemindersTab(),
                  _buildPayrollTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          message,
          style: const TextStyle(color: Colors.red),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final String message;
  const _EmptyView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style: const TextStyle(color: Colors.black54),
      ),
    );
  }
}
