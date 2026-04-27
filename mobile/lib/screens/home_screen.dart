import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/app_config.dart';
import '../models/api_models.dart';
import '../models/auth_models.dart';
import '../services/auth_session_manager.dart';
import '../services/backend_api_service.dart';
import '../services/dashboard_cache_service.dart';
import '../theme/app_theme.dart';

String _formatDurationMinutesVi(
  int minutes, {
  bool compact = false,
}) {
  final safeMinutes = minutes < 0 ? 0 : minutes;
  final days = safeMinutes ~/ (24 * 60);
  final hours = (safeMinutes % (24 * 60)) ~/ 60;
  final mins = safeMinutes % 60;

  if (compact) {
    if (days > 0) {
      return '${days}d ${hours}h';
    }
    if (hours > 0) {
      return '${hours}h ${mins}m';
    }
    return '${mins}m';
  }

  final parts = <String>[];
  if (days > 0) {
    parts.add('$days ngày');
  }
  if (hours > 0) {
    parts.add('$hours giờ');
  }
  if (mins > 0 || parts.isEmpty) {
    parts.add('$mins phút');
  }
  return parts.join(' ');
}

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
  int _selectedIndex = 0;
  late int _selectedPayrollMonth;
  late int _selectedPayrollYear;
  final Map<String, _AttendanceUiStatus> _attendanceDraft = {};
  final Map<String, Map<String, _AttendanceUiStatus>>
      _attendanceSavedSnapshotByClassId = {};
  final Map<String, DateTime> _attendanceSavedAtByClassId = {};

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
    _setFutures(forceNetwork: false);
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
            content:
                Text('Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.')),
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

    final classes = await _api.getClasses(
      activeOnly: true,
      username: username,
    );
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
      lookAheadMinutes: 7 * 24 * 60,
      maxSlots: 200,
      activeOnly: true,
      username: username,
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

  void _setFutures({required bool forceNetwork}) {
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

  Future<void> _forceRefreshAll() async {
    _setFutures(forceNetwork: true);
    try {
      await Future.wait([
        _classesFuture,
        _remindersFuture,
        _payrollFuture,
      ]);
    } catch (_) {
      // Errors are rendered by each FutureBuilder.
    }
  }

  Future<void> _forceRefreshPayroll() async {
    _reloadPayrollOnly(forceNetwork: true);
    try {
      await _payrollFuture;
    } catch (_) {
      // Errors are rendered by FutureBuilder.
    }
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
    return normalized == 'TA' || normalized.contains('ASSISTANT');
  }

  bool _isMakeupRole(String rawRole) {
    final normalized = _normalizeRole(rawRole);
    if (normalized.isEmpty) {
      return false;
    }
    return normalized == 'MAKEUP' ||
        normalized == 'MAKE UP' ||
        normalized.contains('MAKEUP');
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
    return normalized == 'FIXED' || normalized.contains('FIXED');
  }

  bool _isTrialOfficeHourType(String rawType) {
    final normalized = _normalizeOfficeHourType(rawType);
    if (normalized.isEmpty) {
      return false;
    }
    return normalized == 'TRIAL' || normalized.contains('TRIAL');
  }

  bool _isMakeupOfficeHourType(String rawType) {
    final normalized = _normalizeOfficeHourType(rawType);
    if (normalized.isEmpty) {
      return false;
    }
    return normalized == 'MAKEUP' ||
        normalized == 'MAKE UP' ||
        normalized.contains('MAKEUP');
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
      final studentCount =
          officeHour.studentCount < 0 ? 0 : officeHour.studentCount;
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

  double _calculateClassIncome(PayrollClass cls, double hourlyRate) {
    var total = 0.0;
    for (final slot in cls.slots) {
      total += slot.durationHours *
          _roleMultiplier(
            roleShortName: slot.roleShortName,
            roleName: slot.roleName,
          ) *
          hourlyRate;
    }
    return total;
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
        final billableHours = slot.durationHours *
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

  String _formatMoney(double amount) {
    final rounded = amount.roundToDouble();
    final formatter = NumberFormat('#,##0', 'en_US');
    return '${formatter.format(rounded)} VND';
  }

  String _formatDateTime(String? iso) {
    if (iso == null || iso.isEmpty) {
      return '-';
    }
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) {
      return iso;
    }
    return DateFormat('dd/MM/yyyy - HH:mm').format(parsed.toLocal());
  }

  DateTime? _parseDateTimeLoose(String? value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) {
      return null;
    }

    final parsed = DateTime.tryParse(raw);
    if (parsed != null) {
      return parsed.toLocal();
    }

    if (RegExp(r'^\d{13}$').hasMatch(raw)) {
      final ms = int.tryParse(raw);
      if (ms != null) {
        return DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
      }
    }

    if (RegExp(r'^\d{10}$').hasMatch(raw)) {
      final seconds = int.tryParse(raw);
      if (seconds != null) {
        return DateTime.fromMillisecondsSinceEpoch(seconds * 1000).toLocal();
      }
    }

    return null;
  }

  int _sortTimeMs(String? value) {
    final parsed = _parseDateTimeLoose(value);
    if (parsed == null) {
      return 1 << 30;
    }
    return parsed.millisecondsSinceEpoch;
  }

  String _formatCompactCountdownToClass(String? slotStartTime) {
    final start = _parseDateTimeLoose(slotStartTime);
    if (start == null) {
      return '--';
    }

    return _formatDurationMinutesVi(
      start.difference(DateTime.now()).inMinutes,
      compact: true,
    );
  }

  String _attendanceParticipantKey({
    required String name,
    required bool isCoTeacher,
  }) {
    final kind = isCoTeacher ? 'co_teacher' : 'student';
    return '$kind::$name';
  }

  String _attendanceDraftKey({
    required String classId,
    required String participantKey,
  }) {
    return '$classId::$participantKey';
  }

  _AttendanceUiStatus? _attendanceStatusFor({
    required String classId,
    required String participantKey,
  }) {
    return _attendanceDraft[_attendanceDraftKey(
      classId: classId,
      participantKey: participantKey,
    )];
  }

  void _setAttendanceStatus({
    required String classId,
    required String participantKey,
    required _AttendanceUiStatus? status,
  }) {
    final key = _attendanceDraftKey(
      classId: classId,
      participantKey: participantKey,
    );
    setState(() {
      if (status == null) {
        _attendanceDraft.remove(key);
      } else {
        _attendanceDraft[key] = status;
      }
    });
  }

  int _countAttendanceStatus({
    required String classId,
    required List<_AttendanceParticipant> participants,
    required _AttendanceUiStatus status,
  }) {
    var count = 0;
    for (final participant in participants) {
      if (_attendanceStatusFor(
            classId: classId,
            participantKey: participant.key,
          ) ==
          status) {
        count += 1;
      }
    }
    return count;
  }

  Map<String, _AttendanceUiStatus> _buildAttendanceSnapshotForClass({
    required String classId,
    required List<_AttendanceParticipant> participants,
  }) {
    final result = <String, _AttendanceUiStatus>{};
    for (final participant in participants) {
      final status = _attendanceStatusFor(
        classId: classId,
        participantKey: participant.key,
      );
      if (status != null) {
        result[participant.key] = status;
      }
    }
    return result;
  }

  bool _mapAttendanceEquals(
    Map<String, _AttendanceUiStatus> a,
    Map<String, _AttendanceUiStatus> b,
  ) {
    if (a.length != b.length) {
      return false;
    }
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  bool _isAttendanceDirtyForClass({
    required String classId,
    required List<_AttendanceParticipant> participants,
  }) {
    final current = _buildAttendanceSnapshotForClass(
      classId: classId,
      participants: participants,
    );
    final saved = _attendanceSavedSnapshotByClassId[classId] ?? const {};
    return !_mapAttendanceEquals(current, saved);
  }

  String _attendanceStatusLabel(_AttendanceUiStatus status) {
    switch (status) {
      case _AttendanceUiStatus.present:
        return 'Có';
      case _AttendanceUiStatus.late:
        return 'Đi trễ';
      case _AttendanceUiStatus.excusedAbsent:
        return 'Nghỉ có phép';
      case _AttendanceUiStatus.unexcusedAbsent:
        return 'Nghỉ không phép';
    }
  }

  IconData _attendanceStatusIcon(_AttendanceUiStatus status) {
    switch (status) {
      case _AttendanceUiStatus.present:
        return Icons.check_circle_rounded;
      case _AttendanceUiStatus.late:
        return Icons.watch_later_rounded;
      case _AttendanceUiStatus.excusedAbsent:
        return Icons.event_busy_rounded;
      case _AttendanceUiStatus.unexcusedAbsent:
        return Icons.cancel_rounded;
    }
  }

  Color _attendanceStatusColor(_AttendanceUiStatus status) {
    switch (status) {
      case _AttendanceUiStatus.present:
        return Colors.green.shade700;
      case _AttendanceUiStatus.late:
        return Colors.orange.shade700;
      case _AttendanceUiStatus.excusedAbsent:
        return Colors.blue.shade700;
      case _AttendanceUiStatus.unexcusedAbsent:
        return Colors.red.shade700;
    }
  }

  void _saveAttendanceForClass({
    required String classId,
    required List<_AttendanceParticipant> participants,
  }) {
    final snapshot = _buildAttendanceSnapshotForClass(
      classId: classId,
      participants: participants,
    );

    setState(() {
      _attendanceSavedSnapshotByClassId[classId] = snapshot;
      _attendanceSavedAtByClassId[classId] = DateTime.now();
    });

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text('Đã lưu ${snapshot.length} kết quả điểm danh cho lớp này.'),
      ),
    );
  }

  Widget _buildUserHeader() {
    final accents = Theme.of(context).extension<AppAccentColors>()!;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.blue.shade700,
            Colors.blue.shade500,
            const Color(0xFF07A5A5),
          ],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.white.withValues(alpha: 0.22),
            child: Text(
              _session.username.isEmpty
                  ? '?'
                  : _session.username.substring(0, 1).toUpperCase(),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Xin chào, ${_session.username}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  _session.email,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Chúc bạn có một ngày dạy thật hiệu quả.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.84),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.auto_awesome_rounded,
            color: accents.warning.withValues(alpha: 0.85),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewPage() {
    return RefreshIndicator(
      onRefresh: _forceRefreshAll,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
        children: [
          _buildUserHeader(),
          const SizedBox(height: 10),
          _SectionCard(
            title: 'Tổng quan nhanh',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FutureBuilder<List<ClassSummary>>(
                  future: _classesFuture,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const _KpiTile.loading(label: 'Lớp đang dạy');
                    }
                    final classes = snapshot.data ?? const <ClassSummary>[];
                    final students = classes.fold<int>(
                      0,
                      (sum, cls) => sum + cls.totalStudents,
                    );
                    return _KpiTile(
                      label: 'Lớp đang dạy',
                      value: classes.length.toString(),
                      hint: '$students học viên',
                      icon: Icons.menu_book_rounded,
                    );
                  },
                ),
                FutureBuilder<List<ReminderItem>>(
                  future: _remindersFuture,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const _KpiTile.loading(label: 'Lịch sắp tới');
                    }
                    final reminders = snapshot.data ?? const <ReminderItem>[];
                    final openCount =
                        reminders.where((item) => item.isWindowOpen).length;
                    return _KpiTile(
                      label: 'Lịch sắp tới',
                      value: reminders.length.toString(),
                      hint: '$openCount khung đang mở',
                      icon: Icons.event_available_rounded,
                    );
                  },
                ),
                FutureBuilder<PayrollResponse>(
                  future: _payrollFuture,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const _KpiTile.loading(label: 'Thu nhập');
                    }
                    final payroll = snapshot.data!;
                    final money = _calculatePayrollMoney(
                      payroll,
                      _parseHourlyRate(),
                      _parseManualAdjustment(),
                    );
                    return _KpiTile(
                      label: 'Thu nhập hiện tại',
                      value: _formatMoney(money.actualIncome),
                      hint: 'Tháng ${payroll.month}/${payroll.year}',
                      icon: Icons.payments_rounded,
                      wide: true,
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Lịch dạy gần nhất',
            subtitle: 'Tập trung vào các ca cần xử lý sớm',
            child: FutureBuilder<List<ReminderItem>>(
              future: _remindersFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const _InlineLoading();
                }
                if (snapshot.hasError) {
                  return _ErrorLabel(message: snapshot.error.toString());
                }
                final reminders = snapshot.data ?? const <ReminderItem>[];
                if (reminders.isEmpty) {
                  return const _EmptyLabel(
                    message: 'Không có lịch sắp tới trong khung hiện tại.',
                  );
                }
                return Column(
                  children: reminders.take(4).map((reminder) {
                    final badge = _ReminderBadge.fromReminder(reminder);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.blueGrey.shade100),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        title: Text(
                          reminder.className,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        subtitle: Text(
                          'Slot ${reminder.slotIndex ?? '-'}  ·  ${_formatDateTime(reminder.slotStartTime)}',
                        ),
                        trailing: _Pill(
                          label: badge.label,
                          background: badge.background,
                          foreground: badge.foreground,
                          icon: badge.icon,
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Lớp học đang phụ trách',
            child: FutureBuilder<List<ClassSummary>>(
              future: _classesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const _InlineLoading();
                }
                if (snapshot.hasError) {
                  return _ErrorLabel(message: snapshot.error.toString());
                }
                final classes = snapshot.data ?? const <ClassSummary>[];
                if (classes.isEmpty) {
                  return const _EmptyLabel(message: 'Chưa có lớp đang chạy.');
                }

                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: classes
                      .take(8)
                      .map(
                        (cls) => Chip(
                          avatar: const Icon(Icons.school_rounded, size: 16),
                          label: Text(
                            '${cls.className} · ${cls.totalStudents} HV',
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClassesPage() {
    return RefreshIndicator(
      onRefresh: _forceRefreshAll,
      child: FutureBuilder<List<Object>>(
        future: Future.wait<Object>([
          _classesFuture,
          _remindersFuture,
        ]),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorView(message: snapshot.error.toString());
          }

          final payload = snapshot.data ?? const <Object>[];
          final classes = List<ClassSummary>.from(
            payload.isNotEmpty && payload.first is List<ClassSummary>
                ? payload.first as List<ClassSummary>
                : const <ClassSummary>[],
          )..sort((a, b) => a.className.compareTo(b.className));

          final reminders = List<ReminderItem>.from(
            payload.length > 1 && payload[1] is List<ReminderItem>
                ? payload[1] as List<ReminderItem>
                : const <ReminderItem>[],
          );

          if (classes.isEmpty) {
            return const _EmptyView(message: 'Không có lớp đang hoạt động.');
          }

          final remindersByClassId = <String, List<ReminderItem>>{};
          for (final reminder in reminders) {
            remindersByClassId
                .putIfAbsent(reminder.classId, () => [])
                .add(reminder);
          }
          for (final classReminders in remindersByClassId.values) {
            classReminders.sort((a, b) {
              final startDiff =
                  _sortTimeMs(a.slotStartTime) - _sortTimeMs(b.slotStartTime);
              if (startDiff != 0) {
                return startDiff;
              }
              final endDiff =
                  _sortTimeMs(a.slotEndTime) - _sortTimeMs(b.slotEndTime);
              if (endDiff != 0) {
                return endDiff;
              }
              return a.className.compareTo(b.className);
            });
          }

          ReminderItem? nextReminderForClass(ClassSummary cls) {
            final classReminders = remindersByClassId[cls.classId];
            if (classReminders == null || classReminders.isEmpty) {
              return null;
            }
            return classReminders.first;
          }

          String? nextStartTimeForClass(ClassSummary cls) {
            final nextReminder = nextReminderForClass(cls);
            if (nextReminder != null) {
              return nextReminder.slotStartTime;
            }
            return cls.nextAttendanceWindow?.slotStartTime;
          }

          classes.sort((a, b) {
            final aNextStart = nextStartTimeForClass(a);
            final bNextStart = nextStartTimeForClass(b);
            final aHasNext = aNextStart != null && aNextStart.trim().isNotEmpty;
            final bHasNext = bNextStart != null && bNextStart.trim().isNotEmpty;

            if (aHasNext && bHasNext) {
              final diff = _sortTimeMs(aNextStart) - _sortTimeMs(bNextStart);
              if (diff != 0) {
                return diff;
              }
            }
            if (aHasNext != bHasNext) {
              return aHasNext ? -1 : 1;
            }
            return a.className.compareTo(b.className);
          });

          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            itemCount: classes.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final cls = classes[index];
              final nextReminder = nextReminderForClass(cls);
              final roleLabel = nextReminder != null
                  ? (nextReminder.roleShortName ??
                      nextReminder.roleName ??
                      'Chưa rõ vai trò')
                  : 'Chưa rõ vai trò';
              final participants = <_AttendanceParticipant>[];
              final participantSeen = <String>{};

              void addParticipants(
                List<String> names, {
                required bool isCoTeacher,
              }) {
                for (final rawName in names) {
                  final name = rawName.trim();
                  if (name.isEmpty) {
                    continue;
                  }
                  final participantKey = _attendanceParticipantKey(
                    name: name,
                    isCoTeacher: isCoTeacher,
                  );
                  if (!participantSeen.add(participantKey)) {
                    continue;
                  }
                  participants.add(
                    _AttendanceParticipant(
                      key: participantKey,
                      name: name,
                      isCoTeacher: isCoTeacher,
                    ),
                  );
                }
              }

              addParticipants(cls.students, isCoTeacher: false);
              addParticipants(cls.coTeachers, isCoTeacher: true);

              final presentCount = _countAttendanceStatus(
                classId: cls.classId,
                participants: participants,
                status: _AttendanceUiStatus.present,
              );
              final lateCount = _countAttendanceStatus(
                classId: cls.classId,
                participants: participants,
                status: _AttendanceUiStatus.late,
              );
              final excusedCount = _countAttendanceStatus(
                classId: cls.classId,
                participants: participants,
                status: _AttendanceUiStatus.excusedAbsent,
              );
              final unexcusedCount = _countAttendanceStatus(
                classId: cls.classId,
                participants: participants,
                status: _AttendanceUiStatus.unexcusedAbsent,
              );
              final isDirty = _isAttendanceDirtyForClass(
                classId: cls.classId,
                participants: participants,
              );
              final savedAt = _attendanceSavedAtByClassId[cls.classId];

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              cls.className,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          _Pill(
                            label: (cls.status ?? 'RUNNING').toUpperCase(),
                            background: const Color(0xFFE3EEFF),
                            foreground: const Color(0xFF154EA3),
                            icon: Icons.circle,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _MiniStat(
                            icon: Icons.group_rounded,
                            label: '${cls.totalStudents} học viên',
                          ),
                          if (cls.coTeachers.isNotEmpty)
                            _MiniStat(
                              icon: Icons.groups_rounded,
                              label: '${cls.coTeachers.length} đồng giáo viên',
                            ),
                          if (nextReminder != null)
                            _MiniStat(
                              icon: Icons.timer_rounded,
                              label:
                                  'Tới lớp: ${_formatCompactCountdownToClass(nextReminder.slotStartTime)}',
                            ),
                        ],
                      ),
                      if (cls.coTeachers.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Đồng giáo viên: ${cls.coTeachers.join(', ')}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.blueGrey.shade700,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      if (nextReminder != null) ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F7FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Buổi sắp tới',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(
                                      color: const Color(0xFF1C4ED8),
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                              const SizedBox(height: 6),
                              Text('Role của bạn: $roleLabel'),
                              Text(
                                'Thời gian buổi học: ${_formatDateTime(nextReminder.slotStartTime)} - '
                                '${_formatDateTime(nextReminder.slotEndTime)}',
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _MiniStat(
                                    icon: Icons.login_rounded,
                                    label: nextReminder.isWindowOpen
                                        ? 'Đóng điểm danh sau: ${_formatDurationMinutesVi(nextReminder.minutesUntilWindowClose, compact: true)}'
                                        : 'Mở điểm danh sau: ${_formatDurationMinutesVi(nextReminder.minutesUntilWindowOpen, compact: true)}',
                                  ),
                                  _MiniStat(
                                    icon: Icons.tag_rounded,
                                    label:
                                        'Slot ${nextReminder.slotIndex ?? '-'}',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7F8FB),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                              'Chưa có buổi học sắp tới cho lớp này.'),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blueGrey.shade100),
                        ),
                        child: ExpansionTile(
                          tilePadding:
                              const EdgeInsets.symmetric(horizontal: 12),
                          childrenPadding:
                              const EdgeInsets.fromLTRB(12, 0, 12, 10),
                          title: Text('Điểm danh (${participants.length})'),
                          subtitle: Text(
                            'Có $presentCount · Trễ $lateCount · Có phép $excusedCount · Không phép $unexcusedCount',
                          ),
                          children: participants.isEmpty
                              ? const [
                                  Padding(
                                    padding: EdgeInsets.only(bottom: 8),
                                    child: Text(
                                      'Chưa có học viên/đồng giáo viên để điểm danh.',
                                    ),
                                  ),
                                ]
                              : [
                                  ...participants.map((participant) {
                                    final status = _attendanceStatusFor(
                                      classId: cls.classId,
                                      participantKey: participant.key,
                                    );

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF8FAFF),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  participant.name,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                ),
                                              ),
                                              if (participant.isCoTeacher)
                                                _Pill(
                                                  label: 'Đồng GV',
                                                  background:
                                                      const Color(0xFFE3EEFF),
                                                  foreground:
                                                      const Color(0xFF1C4ED8),
                                                  icon: Icons.groups_rounded,
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              ..._AttendanceUiStatus.values.map(
                                                (option) {
                                                  final isSelected =
                                                      status == option;
                                                  return Tooltip(
                                                    message:
                                                        _attendanceStatusLabel(
                                                      option,
                                                    ),
                                                    triggerMode:
                                                        TooltipTriggerMode
                                                            .longPress,
                                                    child: ChoiceChip(
                                                      label: Icon(
                                                        _attendanceStatusIcon(
                                                          option,
                                                        ),
                                                        size: 18,
                                                      ),
                                                      selected: isSelected,
                                                      selectedColor:
                                                          _attendanceStatusColor(
                                                        option,
                                                      ).withValues(alpha: 0.18),
                                                      side: BorderSide(
                                                        color: isSelected
                                                            ? _attendanceStatusColor(
                                                                option,
                                                              )
                                                            : Colors.blueGrey
                                                                .shade200,
                                                      ),
                                                      onSelected: (selected) {
                                                        _setAttendanceStatus(
                                                          classId: cls.classId,
                                                          participantKey:
                                                              participant.key,
                                                          status: selected
                                                              ? option
                                                              : null,
                                                        );
                                                      },
                                                    ),
                                                  );
                                                },
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                  const SizedBox(height: 4),
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton.icon(
                                      onPressed: participants.isEmpty
                                          ? null
                                          : () => _saveAttendanceForClass(
                                                classId: cls.classId,
                                                participants: participants,
                                              ),
                                      icon: const Icon(Icons.save_rounded),
                                      label:
                                          const Text('Lưu kết quả điểm danh'),
                                    ),
                                  ),
                                  if (savedAt != null) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      'Đã lưu lúc ${DateFormat('HH:mm:ss - dd/MM/yyyy').format(savedAt)}'
                                      '${isDirty ? ' · Có thay đổi chưa lưu' : ''}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: isDirty
                                                ? Colors.orange.shade800
                                                : Colors.green.shade700,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ],
                                ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildPayrollPage() {
    final monthOptions = List<int>.generate(12, (index) => index + 1);
    final yearOptions = {
      ..._availablePayrollYears(),
      _selectedPayrollYear,
    }.toList()
      ..sort();

    return RefreshIndicator(
      onRefresh: _forceRefreshPayroll,
      child: FutureBuilder<PayrollResponse>(
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
            return const _EmptyView(message: 'Không có dữ liệu thu nhập.');
          }

          final hourlyRate = _parseHourlyRate();
          final manualAdjustment = _parseManualAdjustment();
          final moneySummary = _calculatePayrollMoney(
            payroll,
            hourlyRate,
            manualAdjustment,
          );

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              _SectionCard(
                title: 'Bộ lọc kỳ lương',
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: _selectedPayrollMonth,
                            decoration:
                                const InputDecoration(labelText: 'Tháng'),
                            items: monthOptions
                                .map(
                                  (month) => DropdownMenuItem<int>(
                                    value: month,
                                    child: Text('Tháng $month'),
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
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: _selectedPayrollYear,
                            decoration: const InputDecoration(labelText: 'Năm'),
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
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _hourlyRateController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Lương theo giờ (VND)',
                              hintText: 'Ví dụ: 150000',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _manualAdjustmentController,
                            keyboardType: const TextInputType.numberWithOptions(
                              signed: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Công bù / điều chỉnh',
                              hintText: 'Ví dụ: 300000 hoặc -200000',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => _reloadPayrollOnly(),
                            icon: const Icon(Icons.filter_alt_rounded),
                            label: const Text('Xem dữ liệu'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _forceRefreshPayroll,
                            icon: const Icon(Icons.cloud_sync_rounded),
                            label: const Text('Cập nhật mới'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: 'Tổng hợp thu nhập ${payroll.month}/${payroll.year}',
                subtitle: 'Đã tính role + office hour + công bù thủ công',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _MiniStat(
                          icon: Icons.check_circle_rounded,
                          label:
                              '${moneySummary.actualSlots} buoi (${moneySummary.actualHours.toStringAsFixed(2)}h)',
                        ),
                        _MiniStat(
                          icon: Icons.auto_graph_rounded,
                          label:
                              '${moneySummary.projectedSlots} buoi du kien (${moneySummary.projectedHours.toStringAsFixed(2)}h)',
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Thu nhập lớp học: ${_formatMoney(moneySummary.classIncome)}',
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Thu nhập office hour: ${_formatMoney(moneySummary.officeHourIncome)}',
                    ),
                    Text(
                      'Công bù / điều chỉnh: ${_formatMoney(moneySummary.manualAdjustment)}',
                      style: TextStyle(
                        color: moneySummary.manualAdjustment < 0
                            ? Colors.red.shade700
                            : Colors.green.shade700,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tổng hiện tại: ${_formatMoney(moneySummary.actualIncome)}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.green.shade700,
                          ),
                    ),
                    Text(
                      'Tổng dự kiến cuối tháng: ${_formatMoney(moneySummary.projectedIncome)}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: const Color(0xFF1C4ED8),
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Office hour: ${payroll.officeHours.length} ca '
                      '(Fixed ${moneySummary.fixedOfficeHourCount}, '
                      'Trial ${moneySummary.trialOfficeHourCount}, '
                      'Makeup ${moneySummary.makeupOfficeHourCount})',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: 'Theo role',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: payroll.summary.byRole
                      .map(
                        (role) => Chip(
                          label: Text(
                            '${role.role}: ${role.slotCount} slots · ${role.totalHours}h',
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              if (payroll.officeHours.isNotEmpty) ...[
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'Chi tiết office hour',
                  child: Column(
                    children: payroll.officeHours.map((officeHour) {
                      final typeLabel = officeHour.officeHourType ??
                          officeHour.shortName ??
                          'UNKNOWN';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blueGrey.shade100),
                        ),
                        child: ListTile(
                          title: Text('$typeLabel · ${officeHour.status}'),
                          subtitle: Text(
                            '${_formatDateTime(officeHour.startTime)} - ${_formatDateTime(officeHour.endTime)}\n'
                            '${officeHour.studentCount} học viên · ${officeHour.durationHours}h',
                          ),
                          trailing: Text(
                            _formatMoney(
                              _calculateOfficeHourIncome(
                                  officeHour, hourlyRate),
                            ),
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: Colors.green.shade700,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          isThreeLine: true,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
              if (payroll.classes.isNotEmpty) ...[
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'Chi tiết theo lớp',
                  child: Column(
                    children: payroll.classes.map((cls) {
                      final classIncome =
                          _calculateClassIncome(cls, hourlyRate);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blueGrey.shade100),
                        ),
                        child: ExpansionTile(
                          tilePadding:
                              const EdgeInsets.symmetric(horizontal: 12),
                          childrenPadding:
                              const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          title: Text(cls.className),
                          subtitle: Text(
                            '${cls.taughtSlotCount} slots · ${cls.totalHours}h',
                          ),
                          trailing: Text(
                            _formatMoney(classIncome),
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  color: Colors.green.shade700,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          children: cls.slots
                              .map(
                                (slot) => ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    'Slot ${slot.slotIndex ?? '-'} · ${slot.attendanceStatus}',
                                  ),
                                  subtitle: Text(
                                    '${_formatDateTime(slot.startTime)} - ${_formatDateTime(slot.endTime)}\n'
                                    'Vai trò ${slot.roleShortName ?? slot.roleName ?? 'UNKNOWN'} · ${slot.durationHours}h',
                                  ),
                                  isThreeLine: true,
                                ),
                              )
                              .toList(),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accents = Theme.of(context).extension<AppAccentColors>()!;
    final titles = ['Tổng quan', 'Lớp học', 'Thu nhập'];
    final safeIndex = _selectedIndex.clamp(0, titles.length - 1);
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[safeIndex]),
        actions: [
          IconButton(
            onPressed: _forceRefreshAll,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Làm mới',
          ),
          IconButton(
            onPressed: widget.onSignOut,
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Đăng xuất',
          ),
        ],
      ),
      body: IndexedStack(
        index: safeIndex,
        children: [
          _buildOverviewPage(),
          _buildClassesPage(),
          _buildPayrollPage(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Colors.blueGrey.shade100),
          ),
        ),
        child: NavigationBar(
          selectedIndex: safeIndex,
          onDestinationSelected: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard_rounded),
              label: 'Tổng quan',
            ),
            NavigationDestination(
              icon: Icon(Icons.class_outlined),
              selectedIcon: Icon(Icons.class_rounded),
              label: 'Lớp học',
            ),
            NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined),
              selectedIcon: Icon(Icons.account_balance_wallet_rounded),
              label: 'Thu nhập',
            ),
          ],
        ),
      ),
      floatingActionButton: safeIndex == 2
          ? FloatingActionButton.extended(
              onPressed: _forceRefreshPayroll,
              icon: const Icon(Icons.sync_rounded),
              label: const Text('Cập nhật lương'),
              backgroundColor: accents.ink,
              foregroundColor: Colors.white,
            )
          : null,
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.child,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final accents = Theme.of(context).extension<AppAccentColors>()!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: accents.ink,
                  ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: accents.mutedInk,
                    ),
              ),
            ],
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  final String label;
  final String value;
  final String hint;
  final IconData icon;
  final bool wide;
  final bool loading;

  const _KpiTile({
    required this.label,
    required this.value,
    required this.hint,
    required this.icon,
    this.wide = false,
  }) : loading = false;

  const _KpiTile.loading({
    required this.label,
  })  : value = '...',
        hint = 'Đang tải',
        icon = Icons.hourglass_top_rounded,
        wide = false,
        loading = true;

  @override
  Widget build(BuildContext context) {
    final width = wide ? 320.0 : 154.0;
    return Container(
      width: width,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: const Color(0xFFF5F8FF),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: const Color(0xFF1C4ED8)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (loading)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 4),
          Text(
            hint,
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MiniStat({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: const Color(0xFFF5F8FF),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF2958C7)),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;

  const _Pill({
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _ReminderBadge {
  final String label;
  final Color background;
  final Color foreground;
  final IconData icon;

  const _ReminderBadge({
    required this.label,
    required this.background,
    required this.foreground,
    required this.icon,
  });

  factory _ReminderBadge.fromReminder(ReminderItem reminder) {
    if (reminder.isWindowOpen) {
      return const _ReminderBadge(
        label: 'Đang mở',
        background: Color(0xFFDDF7E8),
        foreground: Color(0xFF0F9D58),
        icon: Icons.check_circle_rounded,
      );
    }

    if (reminder.minutesUntilWindowOpen > 0) {
      return _ReminderBadge(
        label:
            'Còn ${_formatDurationMinutesVi(reminder.minutesUntilWindowOpen)}',
        background: const Color(0xFFE3EEFF),
        foreground: const Color(0xFF1C4ED8),
        icon: Icons.schedule_rounded,
      );
    }

    return const _ReminderBadge(
      label: 'Sắp đóng',
      background: Color(0xFFFFF1DD),
      foreground: Color(0xFFD97706),
      icon: Icons.warning_amber_rounded,
    );
  }
}

class _InlineLoading extends StatelessWidget {
  const _InlineLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _ErrorLabel extends StatelessWidget {
  final String message;

  const _ErrorLabel({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.red.shade700,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _EmptyLabel extends StatelessWidget {
  final String message;

  const _EmptyLabel({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall,
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
    final accents = Theme.of(context).extension<AppAccentColors>()!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_rounded,
              size: 40,
              color: accents.mutedInk.withValues(alpha: 0.8),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: accents.mutedInk,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _AttendanceParticipant {
  final String key;
  final String name;
  final bool isCoTeacher;

  const _AttendanceParticipant({
    required this.key,
    required this.name,
    required this.isCoTeacher,
  });
}

enum _AttendanceUiStatus {
  present,
  late,
  excusedAbsent,
  unexcusedAbsent,
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
