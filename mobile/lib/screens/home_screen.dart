import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/app_config.dart';
import '../models/api_models.dart';
import '../models/auth_models.dart';
import '../services/auth_session_manager.dart';
import '../services/backend_api_service.dart';
import '../services/dashboard_cache_service.dart';

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
  static const Duration _classesCacheTtl = Duration(minutes: 20);
  static const Duration _remindersCacheTtl = Duration(minutes: 8);
  static const Duration _payrollCacheTtl = Duration(minutes: 20);

  late BackendApiService _api;
  final DashboardCacheService _dashboardCache = DashboardCacheService();
  late final TextEditingController _hourlyRateController;
  late final TextEditingController _manualAdjustmentController;

  late Future<List<ClassSummary>> _classesFuture;
  late Future<List<ReminderItem>> _remindersFuture;
  late Future<PayrollResponse> _payrollFuture;

  late AuthSession _session;
  bool _isHandlingAuthFailure = false;

  String? _selectedAttendanceClassId;
  String? _selectedAttendanceSlotId;
  late int _selectedPayrollMonth;
  late int _selectedPayrollYear;
  final Map<String, _AttendanceStatus> _attendanceStatuses = {};
  bool _isSubmittingAttendance = false;

  @override
  void initState() {
    super.initState();
    final currentSession = widget.sessionManager.currentSession;
    if (currentSession == null) {
      throw StateError('HomeScreen requires an active session.');
    }

    _session = currentSession;
    final now = DateTime.now();
    _selectedPayrollMonth = now.month;
    _selectedPayrollYear = now.year;
    _hourlyRateController = TextEditingController(text: '150000');
    _manualAdjustmentController = TextEditingController(text: '0');
    _api = BackendApiService(
      baseUrl: AppConfig.apiBaseUrl.trim(),
      idTokenProvider: _provideIdToken,
    );
    _reloadAll();
  }

  @override
  void dispose() {
    _hourlyRateController.dispose();
    _manualAdjustmentController.dispose();
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

  bool _isRunningClassSummary(ClassSummary cls) {
    final normalizedStatus = (cls.status ?? '').trim().toUpperCase();
    if (normalizedStatus.isNotEmpty) {
      return normalizedStatus == 'RUNNING';
    }
    return !cls.isClassEnded;
  }

  List<ClassSummary> _filterRunningClasses(List<ClassSummary> classes) {
    return classes.where(_isRunningClassSummary).toList();
  }

  Future<List<ClassSummary>> _loadClasses({
    required String username,
    required bool forceNetwork,
  }) async {
    if (!forceNetwork) {
      final cached = await _dashboardCache.loadClasses(
        username: username,
        maxAge: _classesCacheTtl,
      );
      if (cached != null) {
        return _filterRunningClasses(cached);
      }
    }

    final classes = await _api.getClasses(activeOnly: true);
    final runningClasses = _filterRunningClasses(classes);
    await _dashboardCache.saveClasses(
      username: username,
      classes: runningClasses,
    );
    return runningClasses;
  }

  Future<List<ReminderItem>> _loadReminders({
    required String username,
    required bool forceNetwork,
  }) async {
    if (!forceNetwork) {
      final cached = await _dashboardCache.loadReminders(
        username: username,
        maxAge: _remindersCacheTtl,
      );
      if (cached != null) {
        return cached;
      }
    }

    final reminders = await _api.getAttendanceReminders(
      lookAheadMinutes: 240,
      activeOnly: true,
    );
    await _dashboardCache.saveReminders(
      username: username,
      reminders: reminders,
    );
    return reminders;
  }

  Future<PayrollResponse> _loadPayroll({
    required String username,
    required int month,
    required int year,
    required bool forceNetwork,
  }) async {
    if (!forceNetwork) {
      final cached = await _dashboardCache.loadPayroll(
        username: username,
        month: month,
        year: year,
        maxAge: _payrollCacheTtl,
      );
      if (cached != null) {
        return cached;
      }
    }

    final payroll = await _api.getMonthlyPayroll(
      month: month,
      year: year,
      username: username.isEmpty ? null : username,
    );
    await _dashboardCache.savePayroll(
      username: username,
      payroll: payroll,
    );
    return payroll;
  }

  void _reloadAll({bool forceNetwork = false}) {
    final username = _session.username.trim().toLowerCase();
    setState(() {
      _classesFuture = _loadClasses(
        username: username,
        forceNetwork: forceNetwork,
      );
      _remindersFuture = _loadReminders(
        username: username,
        forceNetwork: forceNetwork,
      );
      _payrollFuture = _loadPayroll(
        username: username,
        month: _selectedPayrollMonth,
        year: _selectedPayrollYear,
        forceNetwork: forceNetwork,
      );
    });
  }

  void _reloadPayrollOnly({bool forceNetwork = false}) {
    final username = _session.username.trim().toLowerCase();
    setState(() {
      _payrollFuture = _loadPayroll(
        username: username,
        month: _selectedPayrollMonth,
        year: _selectedPayrollYear,
        forceNetwork: forceNetwork,
      );
    });
  }

  List<int> _availablePayrollYears() {
    final current = DateTime.now().year;
    return [
      current - 2,
      current - 1,
      current,
      current + 1,
    ];
  }

  double _parseHourlyRate() {
    final normalized = _hourlyRateController.text.replaceAll(
      RegExp(r'[^0-9.]'),
      '',
    );
    return double.tryParse(normalized) ?? 0;
  }

  double _parseManualAdjustment() {
    final raw = _manualAdjustmentController.text.trim().replaceAll(',', '');
    if (raw.isEmpty) {
      return 0;
    }
    final isNegative = raw.startsWith('-');
    final normalized = raw.replaceAll(RegExp(r'[^0-9.]'), '');
    final value = double.tryParse(normalized) ?? 0;
    return isNegative ? -value : value;
  }

  String _normalizeRole(String rawRole) {
    return rawRole.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _normalizeOfficeHourType(String rawType) {
    return rawType.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  bool _isTaRole(String rawRole) {
    final normalized = _normalizeRole(rawRole);
    if (normalized.isEmpty) {
      return false;
    }
    if (normalized == 'TA') {
      return true;
    }
    if (normalized.contains('ASSISTANT')) {
      return true;
    }
    return false;
  }

  bool _isMakeupRole(String rawRole) {
    final normalized = _normalizeRole(rawRole);
    if (normalized.isEmpty) {
      return false;
    }
    if (normalized == 'MAKEUP' ||
        normalized == 'MAKE UP' ||
        normalized.contains('MAKEUP')) {
      return true;
    }
    return false;
  }

  bool _isFullPayRole(String rawRole) {
    final normalized = _normalizeRole(rawRole);
    if (normalized.isEmpty) {
      return false;
    }
    if (normalized == 'LEC' || normalized.contains('LECTURER')) {
      return true;
    }
    if (normalized == 'JUDGE' || normalized.contains('JUDGE')) {
      return true;
    }
    if (normalized == 'SUP' ||
        normalized == 'SUPPLY' ||
        normalized.contains('SUPPLY')) {
      return true;
    }
    return false;
  }

  double _roleMultiplier({
    required String? roleShortName,
    required String? roleName,
  }) {
    final candidates = [roleShortName ?? '', roleName ?? ''];
    for (final role in candidates) {
      if (_isFullPayRole(role)) {
        return 1;
      }
    }
    for (final role in candidates) {
      if (_isTaRole(role)) {
        return 0.75;
      }
    }
    for (final role in candidates) {
      if (_isMakeupRole(role)) {
        return 0.75;
      }
    }
    return 0;
  }

  bool _isFixedOfficeHourType(String rawType) {
    final normalized = _normalizeOfficeHourType(rawType);
    if (normalized.isEmpty) {
      return false;
    }
    if (normalized == 'FIXED' || normalized.contains('FIXED')) {
      return true;
    }
    return false;
  }

  bool _isTrialOfficeHourType(String rawType) {
    final normalized = _normalizeOfficeHourType(rawType);
    if (normalized.isEmpty) {
      return false;
    }
    if (normalized == 'TRIAL' || normalized.contains('TRIAL')) {
      return true;
    }
    return false;
  }

  bool _isMakeupOfficeHourType(String rawType) {
    final normalized = _normalizeOfficeHourType(rawType);
    if (normalized.isEmpty) {
      return false;
    }
    if (normalized == 'MAKEUP' ||
        normalized == 'MAKE UP' ||
        normalized.contains('MAKEUP')) {
      return true;
    }
    return false;
  }

  double _calculateOfficeHourIncome(
    PayrollOfficeHour officeHour,
    double hourlyRate,
  ) {
    final rawType = officeHour.officeHourType ?? officeHour.shortName ?? '';
    if (_isFixedOfficeHourType(rawType)) {
      final cappedStudents = officeHour.studentCount < 0
          ? 0
          : (officeHour.studentCount > 7 ? 7 : officeHour.studentCount);
      return (80000 + (30000 * cappedStudents)).toDouble();
    }

    if (_isTrialOfficeHourType(rawType)) {
      final studentCount = officeHour.studentCount < 0 ? 0 : officeHour.studentCount;
      if (studentCount <= 0) {
        return 0;
      }
      return (40000 + ((studentCount - 1) * 20000)).toDouble();
    }

    if (_isMakeupOfficeHourType(rawType)) {
      return officeHour.durationHours * hourlyRate * 0.75;
    }

    return 0;
  }

  double _slotBillableHours(PayrollSlot slot) {
    return slot.durationHours;
  }

  _PayrollMoneySummary _calculatePayrollMoney(
    PayrollResponse payroll,
    double hourlyRate,
    double manualAdjustment,
  ) {
    var actualSlots = 0;
    var actualHours = 0.0;
    var classIncome = 0.0;
    for (final cls in payroll.classes) {
      for (final slot in cls.slots) {
        final billableHours = _slotBillableHours(slot) *
            _roleMultiplier(
              roleShortName: slot.roleShortName,
              roleName: slot.roleName,
            );
        actualSlots += 1;
        actualHours += billableHours;
        classIncome += billableHours * hourlyRate;
      }
    }

    var fixedOfficeHourCount = 0;
    var trialOfficeHourCount = 0;
    var makeupOfficeHourCount = 0;
    var officeHourIncome = 0.0;
    for (final officeHour in payroll.officeHours) {
      final rawType = officeHour.officeHourType ?? officeHour.shortName ?? '';
      if (_isFixedOfficeHourType(rawType)) {
        fixedOfficeHourCount += 1;
      }
      if (_isTrialOfficeHourType(rawType)) {
        trialOfficeHourCount += 1;
      }
      if (_isMakeupOfficeHourType(rawType)) {
        makeupOfficeHourCount += 1;
      }
      officeHourIncome += _calculateOfficeHourIncome(officeHour, hourlyRate);
    }

    var projectedSlots = actualSlots;
    var projectedHours = actualHours;
    var projectedClassIncome = classIncome;
    var projectedOfficeHourIncome = officeHourIncome;

    final now = DateTime.now();
    final isCurrentMonth =
        payroll.month == now.month && payroll.year == now.year;
    if (isCurrentMonth && (actualSlots > 0 || payroll.officeHours.isNotEmpty)) {
      final daysInMonth = DateTime(payroll.year, payroll.month + 1, 0).day;
      final elapsedDays = now.day.clamp(1, daysInMonth);
      final factor = daysInMonth / elapsedDays;
      projectedSlots = (actualSlots * factor).round();
      projectedHours = actualHours * factor;
      projectedClassIncome = classIncome * factor;
      projectedOfficeHourIncome = officeHourIncome * factor;
    }

    final actualIncome = classIncome + officeHourIncome + manualAdjustment;
    final projectedIncome =
        projectedClassIncome + projectedOfficeHourIncome + manualAdjustment;

    return _PayrollMoneySummary(
      actualSlots: actualSlots,
      projectedSlots: projectedSlots,
      actualHours: actualHours,
      projectedHours: projectedHours,
      classIncome: classIncome,
      officeHourIncome: officeHourIncome,
      fixedOfficeHourCount: fixedOfficeHourCount,
      trialOfficeHourCount: trialOfficeHourCount,
      makeupOfficeHourCount: makeupOfficeHourCount,
      manualAdjustment: manualAdjustment,
      actualIncome: actualIncome,
      projectedIncome: projectedIncome,
      remainingIncome: projectedIncome - actualIncome,
    );
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

  String _formatSlotDate(String? iso) {
    if (iso == null || iso.isEmpty) {
      return '--/--';
    }
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) {
      return '--/--';
    }
    return DateFormat('dd/MM').format(parsed.toLocal());
  }

  String _formatSlotTime(String? iso) {
    if (iso == null || iso.isEmpty) {
      return '--:--';
    }
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) {
      return '--:--';
    }
    return DateFormat('HH:mm').format(parsed.toLocal());
  }

  String _formatMoney(double amount) {
    final rounded = amount.roundToDouble();
    final formatter = NumberFormat('#,##0', 'en_US');
    return '${formatter.format(rounded)} VND';
  }

  String _studentKey(String classId, String studentName) {
    return '$classId::$studentName';
  }

  ClassSummary? _resolveAttendanceClass(List<ClassSummary> classes) {
    if (classes.isEmpty) {
      return null;
    }

    if (_selectedAttendanceClassId != null) {
      for (final cls in classes) {
        if (cls.classId == _selectedAttendanceClassId) {
          return cls;
        }
      }
    }

    for (final cls in classes) {
      if (cls.students.isNotEmpty) {
        return cls;
      }
    }

    return classes.first;
  }

  List<_AttendanceSlotOption> _buildAttendanceSlotOptions(
    ClassSummary selectedClass,
    List<ReminderItem> reminders,
  ) {
    final options = <_AttendanceSlotOption>[];
    final seenSlotIds = <String>{};

    for (final reminder in reminders) {
      if (reminder.classId != selectedClass.classId) {
        continue;
      }

      if (seenSlotIds.contains(reminder.slotId)) {
        continue;
      }
      seenSlotIds.add(reminder.slotId);

      options.add(
        _AttendanceSlotOption(
          slotId: reminder.slotId,
          slotIndex: reminder.slotIndex,
          label:
              'Slot ${reminder.slotIndex ?? '-'} | ${_formatDateTime(reminder.attendanceOpenAt)} -> ${_formatDateTime(reminder.attendanceCloseAt)}',
          isWindowOpen: reminder.isWindowOpen,
          attendanceOpenAt: reminder.attendanceOpenAt,
          attendanceCloseAt: reminder.attendanceCloseAt,
        ),
      );
    }

    final nextWindow = selectedClass.nextAttendanceWindow;
    if (nextWindow != null && !seenSlotIds.contains(nextWindow.slotId)) {
      options.add(
        _AttendanceSlotOption(
          slotId: nextWindow.slotId,
          slotIndex: nextWindow.slotIndex,
          label:
              'Next slot ${nextWindow.slotIndex ?? '-'} | ${_formatDateTime(nextWindow.attendanceOpenAt)} -> ${_formatDateTime(nextWindow.attendanceCloseAt)}',
          isWindowOpen: nextWindow.isWindowOpen,
          attendanceOpenAt: nextWindow.attendanceOpenAt,
          attendanceCloseAt: nextWindow.attendanceCloseAt,
        ),
      );
    }

    if (options.isEmpty) {
      options.add(
        const _AttendanceSlotOption(
          slotId: '',
          slotIndex: null,
          label: 'No active attendance window for this class',
          isWindowOpen: false,
          attendanceOpenAt: '',
          attendanceCloseAt: '',
          isPlaceholder: true,
        ),
      );
    }

    return options;
  }

  String _resolveAttendanceSlotId(List<_AttendanceSlotOption> options) {
    if (options.isEmpty) {
      return '';
    }

    if (_selectedAttendanceSlotId != null) {
      for (final option in options) {
        if (option.slotId == _selectedAttendanceSlotId) {
          return option.slotId;
        }
      }
    }

    for (final option in options) {
      if (option.isWindowOpen) {
        return option.slotId;
      }
    }

    return options.first.slotId;
  }

  void _setAllStudentsStatus(
      ClassSummary selectedClass, _AttendanceStatus status) {
    setState(() {
      for (final student in selectedClass.students) {
        _attendanceStatuses[_studentKey(selectedClass.classId, student)] =
            status;
      }
    });
  }

  int _countRecordedStudents(ClassSummary selectedClass) {
    return selectedClass.students.length;
  }

  Map<_AttendanceStatus, int> _countByStatus(ClassSummary selectedClass) {
    final summary = <_AttendanceStatus, int>{
      for (final status in _AttendanceStatus.values) status: 0,
    };

    for (final student in selectedClass.students) {
      final key = _studentKey(selectedClass.classId, student);
      final selected = _attendanceStatuses[key] ?? _AttendanceStatus.attended;
      summary[selected] = (summary[selected] ?? 0) + 1;
    }

    return summary;
  }

  String _previousSlotLabel(_AttendanceSlotOption selectedSlot, int offset) {
    final currentIndex = selectedSlot.slotIndex;
    if (currentIndex == null) {
      return offset == 2 ? '#1' : '#2';
    }

    final previousIndex = currentIndex - offset;
    if (previousIndex <= 0) {
      return '#-';
    }
    return '#$previousIndex';
  }

  Widget _buildStudentStatusAction({
    required _AttendanceStatus status,
    required _AttendanceStatus? selectedStatus,
    required VoidCallback onTap,
  }) {
    final isSelected = selectedStatus == status;
    final color = status.color;

    return SizedBox(
      height: 34,
      child: OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: isSelected ? color : Colors.black54,
          side: BorderSide(
            color: isSelected ? color : Colors.black26,
          ),
          backgroundColor: isSelected ? color.withValues(alpha: 0.12) : null,
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        icon: Icon(status.icon, size: 16),
        label: Text(
          status.displayLabel,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Future<void> _submitAttendanceDraft(
    ClassSummary selectedClass,
    _AttendanceSlotOption selectedSlot,
  ) async {
    if (_isSubmittingAttendance) {
      return;
    }

    if (selectedSlot.slotId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This class has no active attendance slot right now.'),
        ),
      );
      return;
    }

    setState(() {
      _isSubmittingAttendance = true;
    });

    try {
      final payload = {
        'classId': selectedClass.classId,
        'className': selectedClass.className,
        'slotId': selectedSlot.slotId,
        'attendanceOpenAt': selectedSlot.attendanceOpenAt,
        'attendanceCloseAt': selectedSlot.attendanceCloseAt,
        'submittedAt': DateTime.now().toIso8601String(),
        'students': selectedClass.students.map((student) {
          final key = _studentKey(selectedClass.classId, student);
          final status = _attendanceStatuses[key] ?? _AttendanceStatus.attended;
          return {
            'studentName': student,
            'status': status.code,
            'comment': '',
          };
        }).toList(),
      };

      await Future<void>.delayed(const Duration(milliseconds: 350));

      if (!mounted) {
        return;
      }

      final prettyJson = const JsonEncoder.withIndent('  ').convert(payload);
      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Attendance Payload Preview'),
            content: SizedBox(
              width: 540,
              child: SingleChildScrollView(
                child: SelectableText(
                  prettyJson,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmittingAttendance = false;
        });
      }
    }
  }

  Widget _buildUserHeader() {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: const Color(0xFFDCE6FF),
              child: Text(
                _session.username.isEmpty
                    ? '?'
                    : _session.username.substring(0, 1).toUpperCase(),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1D3FC2),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Xin chao, ${_session.username}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _session.email,
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              ),
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
          return const _EmptyView(message: 'No running classes found.');
        }

        return ListView.separated(
          itemCount: classes.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final cls = classes[index];
            final next = cls.nextAttendanceWindow;
            final sampleStudents = cls.students.take(3).join(', ');
            return ListTile(
              title: Text(cls.className),
              subtitle: Text(
                'Status: ${cls.status ?? '-'}\n'
                'Students: ${cls.totalStudents} | Slots: ${cls.totalSlots}\n'
                'Sample: ${sampleStudents.isEmpty ? '-' : sampleStudents}\n'
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

  Widget _buildAttendanceTab() {
    return FutureBuilder<List<ClassSummary>>(
      future: _classesFuture,
      builder: (context, classesSnapshot) {
        if (classesSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (classesSnapshot.hasError) {
          return _ErrorView(message: classesSnapshot.error.toString());
        }

        final classes = classesSnapshot.data ?? const [];
        if (classes.isEmpty) {
          return const _EmptyView(
              message: 'No classes available for attendance.');
        }

        return FutureBuilder<List<ReminderItem>>(
          future: _remindersFuture,
          builder: (context, remindersSnapshot) {
            if (remindersSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (remindersSnapshot.hasError) {
              return _ErrorView(message: remindersSnapshot.error.toString());
            }

            final reminders = remindersSnapshot.data ?? const [];
            final selectedClass = _resolveAttendanceClass(classes);
            if (selectedClass == null) {
              return const _EmptyView(message: 'No class selected.');
            }

            final slotOptions =
                _buildAttendanceSlotOptions(selectedClass, reminders);
            final selectedSlotId = _resolveAttendanceSlotId(slotOptions);
            final selectedSlot = slotOptions.firstWhere(
              (option) => option.slotId == selectedSlotId,
              orElse: () => slotOptions.first,
            );
            final totalStudents = selectedClass.students.length;
            final recordedStudents = _countRecordedStudents(selectedClass);
            final statusSummary = _countByStatus(selectedClass);
            final currentSlotLabel = selectedSlot.slotIndex == null
                ? 'Buoi hien tai'
                : '#${selectedSlot.slotIndex}';

            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Cau hinh diem danh',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: selectedClass.classId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'Lop hoc',
                            isDense: true,
                          ),
                          items: classes
                              .map(
                                (cls) => DropdownMenuItem<String>(
                                  value: cls.classId,
                                  child: Text(
                                      '${cls.className} (${cls.totalStudents} hoc vien)'),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setState(() {
                              _selectedAttendanceClassId = value;
                              _selectedAttendanceSlotId = null;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: selectedSlotId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'Buoi diem danh',
                            isDense: true,
                          ),
                          items: slotOptions
                              .map(
                                (slot) => DropdownMenuItem<String>(
                                  value: slot.slotId,
                                  child: Row(
                                    children: [
                                      Expanded(child: Text(slot.label)),
                                      if (slot.isWindowOpen)
                                        const Padding(
                                          padding: EdgeInsets.only(left: 8),
                                          child: Text(
                                            'OPEN',
                                            style: TextStyle(
                                              color: Colors.green,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setState(() {
                              _selectedAttendanceSlotId = value;
                            });
                          },
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Khung mo: ${_formatDateTime(selectedSlot.attendanceOpenAt)}  |  Dong: ${_formatDateTime(selectedSlot.attendanceCloseAt)}',
                          style: const TextStyle(color: Colors.black54),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Luu y: nut Save hien chi preview payload de test flow.',
                          style: TextStyle(
                            color: Colors.black54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (selectedClass.students.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Khong co hoc vien trong lop nay. Thu reload hoac doi lop.',
                      ),
                    ),
                  )
                else
                  Card(
                    margin: const EdgeInsets.only(top: 8),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                          color: const Color(0xFFF5F7FB),
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                selectedClass.className,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1F3BC8),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '$currentSlotLabel ${_formatSlotTime(selectedSlot.attendanceOpenAt)}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Text(
                                '$recordedStudents/$totalStudents da ghi nhan',
                                style: const TextStyle(
                                  color: Color(0xFF2E7D32),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minWidth: 860),
                            child: Column(
                              children: [
                                Container(
                                  padding:
                                      const EdgeInsets.fromLTRB(6, 8, 6, 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF7F8FC),
                                    border: Border.all(color: Colors.black12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      const SizedBox(
                                        width: 260,
                                        child: Text(
                                          'Kiem tra hoc vien',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 72,
                                        child: Center(
                                          child: Text(
                                            _previousSlotLabel(selectedSlot, 2),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: Colors.black54,
                                            ),
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 72,
                                        child: Center(
                                          child: Text(
                                            _previousSlotLabel(selectedSlot, 1),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: Colors.black54,
                                            ),
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 420,
                                        child: Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 6,
                                              ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF2246F0),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                '$currentSlotLabel  ${_formatSlotTime(selectedSlot.attendanceOpenAt)} ${_formatSlotDate(selectedSlot.attendanceOpenAt)}',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                'Thao tac nhanh',
                                                style: TextStyle(
                                                  color: Colors.grey.shade700,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 6),
                                ...selectedClass.students.map((studentName) {
                                  final studentKey = _studentKey(
                                    selectedClass.classId,
                                    studentName,
                                  );
                                  final selectedStatus =
                                      _attendanceStatuses[studentKey] ??
                                          _AttendanceStatus.attended;

                                  return Container(
                                    padding: const EdgeInsets.fromLTRB(
                                      6,
                                      10,
                                      6,
                                      10,
                                    ),
                                    decoration: const BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(
                                          color: Color(0x11000000),
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 260,
                                          child: Row(
                                            children: [
                                              CircleAvatar(
                                                radius: 16,
                                                backgroundColor:
                                                    const Color(0xFFE8EAEE),
                                                child: Icon(
                                                  Icons.person,
                                                  size: 18,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  studentName,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(
                                          width: 72,
                                          child: Center(
                                            child: Icon(
                                              Icons.check,
                                              color: Color(0xFF45A657),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(
                                          width: 72,
                                          child: Center(
                                            child: Icon(
                                              Icons.check,
                                              color: Color(0xFF45A657),
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          width: 420,
                                          child: Row(
                                            children: [
                                              _buildStudentStatusAction(
                                                status:
                                                    _AttendanceStatus.attended,
                                                selectedStatus: selectedStatus,
                                                onTap: () {
                                                  setState(() {
                                                    _attendanceStatuses[
                                                            studentKey] =
                                                        _AttendanceStatus
                                                            .attended;
                                                  });
                                                },
                                              ),
                                              const SizedBox(width: 6),
                                              _buildStudentStatusAction(
                                                status:
                                                    _AttendanceStatus.absent,
                                                selectedStatus: selectedStatus,
                                                onTap: () {
                                                  setState(() {
                                                    _attendanceStatuses[
                                                            studentKey] =
                                                        _AttendanceStatus
                                                            .absent;
                                                  });
                                                },
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  selectedStatus.displayLabel,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    color: selectedStatus.color,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        ),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                          color: const Color(0xFFF7F9FD),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Diem danh all',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  ...const [
                                    _AttendanceStatus.attended,
                                    _AttendanceStatus.absent,
                                  ].map(
                                    (status) => OutlinedButton.icon(
                                      onPressed: () => _setAllStudentsStatus(
                                        selectedClass,
                                        status,
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: status.color,
                                      ),
                                      icon: Icon(status.icon, size: 18),
                                      label: Text(status.displayLabel),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  ...const [
                                    _AttendanceStatus.attended,
                                    _AttendanceStatus.absent,
                                  ].map(
                                    (status) => Chip(
                                      label: Text(
                                        '${status.displayLabel}: ${statusSummary[status] ?? 0}',
                                      ),
                                      avatar: Icon(
                                        status.icon,
                                        size: 16,
                                        color: status.color,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerRight,
                                child: FilledButton.icon(
                                  onPressed: _isSubmittingAttendance
                                      ? null
                                      : () => _submitAttendanceDraft(
                                            selectedClass,
                                            selectedSlot,
                                          ),
                                  icon: _isSubmittingAttendance
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.save),
                                  label: const Text('Save'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
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
        final monthOptions = List<int>.generate(12, (index) => index + 1);
        final yearOptions = {
          ..._availablePayrollYears(),
          _selectedPayrollYear,
        }.toList()
          ..sort();
        final hourlyRate = _parseHourlyRate();
        final manualAdjustment = _parseManualAdjustment();
        final moneySummary = _calculatePayrollMoney(
          payroll,
          hourlyRate,
          manualAdjustment,
        );

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
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.end,
                      children: [
                        SizedBox(
                          width: 110,
                          child: DropdownButtonFormField<int>(
                            initialValue: _selectedPayrollMonth,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'Thang',
                              isDense: true,
                            ),
                            items: monthOptions
                                .map(
                                  (month) => DropdownMenuItem<int>(
                                    value: month,
                                    child: Text('Thang $month'),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value == null) {
                                return;
                              }
                              setState(() {
                                _selectedPayrollMonth = value;
                              });
                            },
                          ),
                        ),
                        SizedBox(
                          width: 120,
                          child: DropdownButtonFormField<int>(
                            initialValue: _selectedPayrollYear,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'Nam',
                              isDense: true,
                            ),
                            items: yearOptions
                                .map(
                                  (year) => DropdownMenuItem<int>(
                                    value: year,
                                    child: Text(year.toString()),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value == null) {
                                return;
                              }
                              setState(() {
                                _selectedPayrollYear = value;
                              });
                            },
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: () => _reloadPayrollOnly(),
                          icon: const Icon(Icons.filter_alt_outlined),
                          label: const Text('Loc'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () =>
                              _reloadPayrollOnly(forceNetwork: true),
                          icon: const Icon(Icons.cloud_sync_outlined),
                          label: const Text('Cap nhat'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _hourlyRateController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Luong theo gio (VND)',
                        hintText: 'Vi du: 150000',
                        isDense: true,
                      ),
                      onChanged: (_) {
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _manualAdjustmentController,
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                      ),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Cong bu / dieu chinh thu cong (VND)',
                        hintText: 'Vi du: 300000 hoac -200000',
                        isDense: true,
                      ),
                      onChanged: (_) {
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'So buoi da diem danh (thang dang loc): ${moneySummary.actualSlots} buoi (${moneySummary.actualHours.toStringAsFixed(2)}h)',
                    ),
                    Text(
                      'Thu nhap lop hoc (theo role): ${_formatMoney(moneySummary.classIncome)}',
                    ),
                    Text(
                      'Cong office hour: ${payroll.officeHours.length} ca (Fixed: ${moneySummary.fixedOfficeHourCount}, Trial: ${moneySummary.trialOfficeHourCount}, Makeup: ${moneySummary.makeupOfficeHourCount})',
                    ),
                    Text(
                      'Thu nhap office hour: ${_formatMoney(moneySummary.officeHourIncome)}',
                    ),
                    Text(
                      'Cong bu / dieu chinh: ${_formatMoney(moneySummary.manualAdjustment)}',
                      style: TextStyle(
                        color: moneySummary.manualAdjustment < 0
                            ? const Color(0xFFC62828)
                            : const Color(0xFF2E7D32),
                      ),
                    ),
                    Text(
                      'Tong thu nhap hien tai: ${_formatMoney(moneySummary.actualIncome)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2E7D32),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'So buoi du kien cuoi thang: ${moneySummary.projectedSlots} buoi (${moneySummary.projectedHours.toStringAsFixed(2)}h)',
                    ),
                    Text(
                      'Thu nhap du kien: ${_formatMoney(moneySummary.projectedIncome)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1D3FC2),
                      ),
                    ),
                    Text(
                      'Con lai du kien: ${_formatMoney(moneySummary.remainingIncome < 0 ? 0 : moneySummary.remainingIncome)}',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Rule tinh luong: LEC/JUDGE/SUPPLY = 100%, TA/ASSISTANT/MAKEUP = 75%, role khac = 0%. Fixed = 80,000 + 30,000 x so hoc vien (toi da 7). Trial = 40,000 cho hoc vien dau + 20,000 moi hoc vien tiep theo. Makeup office hour = 75% luong gio theo thoi luong. Co the cong them cong bu thu cong.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
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
            if (payroll.officeHours.isNotEmpty)
              Card(
                margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: ExpansionTile(
                  title: const Text('Office Hour'),
                  subtitle: Text('${payroll.officeHours.length} ca'),
                  children: payroll.officeHours
                      .map(
                        (officeHour) => ListTile(
                          dense: true,
                          title: Text(
                            '${officeHour.officeHourType ?? officeHour.shortName ?? 'UNKNOWN'} - ${officeHour.status}',
                          ),
                          subtitle: Text(
                            '${_formatDateTime(officeHour.startTime)} -> ${_formatDateTime(officeHour.endTime)}\n'
                            'Students: ${officeHour.studentCount} | ${officeHour.durationHours}h',
                          ),
                          trailing: Text(
                            _formatMoney(
                              _calculateOfficeHourIncome(officeHour, hourlyRate),
                            ),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF2E7D32),
                            ),
                          ),
                          isThreeLine: true,
                        ),
                      )
                      .toList(),
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
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('LMS Smooth Bridge'),
          actions: [
            IconButton(
              onPressed: () => _reloadAll(forceNetwork: true),
              icon: const Icon(Icons.refresh),
              tooltip: 'Reload',
            ),
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
              Tab(text: 'Attendance'),
              Tab(text: 'Payroll'),
            ],
          ),
        ),
        body: Column(
          children: [
            _buildUserHeader(),
            Expanded(
              child: TabBarView(
                children: [
                  _buildClassesTab(),
                  _buildRemindersTab(),
                  _buildAttendanceTab(),
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

enum _AttendanceStatus {
  attended,
  absent,
}

extension _AttendanceStatusLabel on _AttendanceStatus {
  String get displayLabel {
    switch (this) {
      case _AttendanceStatus.attended:
        return 'Co mat';
      case _AttendanceStatus.absent:
        return 'Vang';
    }
  }

  IconData get icon {
    switch (this) {
      case _AttendanceStatus.attended:
        return Icons.check;
      case _AttendanceStatus.absent:
        return Icons.close;
    }
  }

  Color get color {
    switch (this) {
      case _AttendanceStatus.attended:
        return const Color(0xFF2E7D32);
      case _AttendanceStatus.absent:
        return const Color(0xFFC62828);
    }
  }

  String get code {
    switch (this) {
      case _AttendanceStatus.attended:
        return 'ATTENDED';
      case _AttendanceStatus.absent:
        return 'ABSENT';
    }
  }
}

class _AttendanceSlotOption {
  final String slotId;
  final int? slotIndex;
  final String label;
  final bool isWindowOpen;
  final String attendanceOpenAt;
  final String attendanceCloseAt;
  final bool isPlaceholder;

  const _AttendanceSlotOption({
    required this.slotId,
    required this.slotIndex,
    required this.label,
    required this.isWindowOpen,
    required this.attendanceOpenAt,
    required this.attendanceCloseAt,
    this.isPlaceholder = false,
  });
}

class _PayrollMoneySummary {
  final int actualSlots;
  final int projectedSlots;
  final double actualHours;
  final double projectedHours;
  final double classIncome;
  final double officeHourIncome;
  final int fixedOfficeHourCount;
  final int trialOfficeHourCount;
  final int makeupOfficeHourCount;
  final double manualAdjustment;
  final double actualIncome;
  final double projectedIncome;
  final double remainingIncome;

  const _PayrollMoneySummary({
    required this.actualSlots,
    required this.projectedSlots,
    required this.actualHours,
    required this.projectedHours,
    required this.classIncome,
    required this.officeHourIncome,
    required this.fixedOfficeHourCount,
    required this.trialOfficeHourCount,
    required this.makeupOfficeHourCount,
    required this.manualAdjustment,
    required this.actualIncome,
    required this.projectedIncome,
    required this.remainingIncome,
  });
}
