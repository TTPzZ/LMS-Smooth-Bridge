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
    parts.add('$days ngÃƒÆ’Ã‚Â y');
  }
  if (hours > 0) {
    parts.add('$hours giÃƒÂ¡Ã‚Â»Ã‚Â');
  }
  if (mins > 0 || parts.isEmpty) {
    parts.add('$mins phÃƒÆ’Ã‚Âºt');
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
  late Future<List<Object>> _classesAndRemindersFuture;
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
  final Map<String, bool> _attendanceSavingByClassId = {};
  final Map<String, _ClassCardSection?> _classSectionByClassId = {};
  final Map<String, List<_StudentCommentDraft>> _studentCommentDraftByClassId =
      {};
  final Map<String, List<_StudentCommentDraft>>
      _previousStudentCommentDraftByClassId = {};
  final Map<String, String> _studentCommentSlotByClassId = {};
  final Map<String, String> _previousStudentCommentSlotByClassId = {};
  final Map<String, bool> _studentCommentLoadingByClassId = {};
  final Map<String, bool> _previousStudentCommentLoadingByClassId = {};
  final Map<String, bool> _studentCommentSavingByClassId = {};
  final Map<String, bool> _previousStudentCommentSavingByClassId = {};
  final Map<String, String?> _studentCommentSavingDraftKeyByClassId = {};
  final Map<String, String?> _previousStudentCommentSavingDraftKeyByClassId =
      {};
  final Map<String, String?> _studentCommentErrorByClassId = {};
  final Map<String, String?> _previousStudentCommentErrorByClassId = {};
  final Set<String> _previousCommentWarningShown = {};

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
            content: Text(
                'PhiÃƒÆ’Ã‚Âªn Ãƒâ€žÃ¢â‚¬ËœÃƒâ€žÃ†â€™ng nhÃƒÂ¡Ã‚ÂºÃ‚Â­p Ãƒâ€žÃ¢â‚¬ËœÃƒÆ’Ã‚Â£ hÃƒÂ¡Ã‚ÂºÃ‚Â¿t hÃƒÂ¡Ã‚ÂºÃ‚Â¡n. Vui lÃƒÆ’Ã‚Â²ng Ãƒâ€žÃ¢â‚¬ËœÃƒâ€žÃ†â€™ng nhÃƒÂ¡Ã‚ÂºÃ‚Â­p lÃƒÂ¡Ã‚ÂºÃ‚Â¡i.')),
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
      _classesAndRemindersFuture = Future.wait<Object>([
        _classesFuture,
        _remindersFuture,
      ]);
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

  String _formatDayHourMinuteCountdown(String? slotStartTime) {
    final start = _parseDateTimeLoose(slotStartTime);
    if (start == null) {
      return '--';
    }

    var totalMinutes = start.difference(DateTime.now()).inMinutes;
    if (totalMinutes < 0) {
      totalMinutes = 0;
    }

    final days = totalMinutes ~/ (24 * 60);
    final hours = (totalMinutes % (24 * 60)) ~/ 60;
    final mins = totalMinutes % 60;

    if (days > 0) {
      return '${days}d ${hours}h ${mins}m';
    }
    if (hours > 0) {
      return '${hours}h ${mins}m';
    }
    return '${mins}m';
  }

  void _toggleClassSection({
    required String classId,
    required _ClassCardSection section,
  }) {
    setState(() {
      final current = _classSectionByClassId.containsKey(classId)
          ? _classSectionByClassId[classId]
          : null;
      if (current == section) {
        _classSectionByClassId[classId] = null;
      } else {
        _classSectionByClassId[classId] = section;
      }
    });
  }

  List<_StudentCommentDraft> _fallbackStudentComments(
    List<String> studentNames,
  ) {
    final seen = <String>{};
    final drafts = <_StudentCommentDraft>[];
    for (final rawName in studentNames) {
      final name = rawName.trim();
      if (name.isEmpty || !seen.add(name.toLowerCase())) {
        continue;
      }
      drafts.add(
        _StudentCommentDraft(
          key: 'student::$name',
          name: name,
          studentId: null,
          comment: '',
        ),
      );
    }
    return drafts;
  }

  Future<void> _loadStudentCommentsForClass({
    required String classId,
    required String slotId,
    required List<String> studentNames,
    bool force = false,
  }) async {
    final normalizedSlotId = slotId.trim();
    if (normalizedSlotId.isEmpty) {
      setState(() {
        _studentCommentDraftByClassId[classId] =
            _fallbackStudentComments(studentNames);
        _studentCommentSlotByClassId.remove(classId);
        _studentCommentErrorByClassId[classId] =
            'Chua co slot sap toi de lay nhan xet.';
      });
      return;
    }

    final alreadyLoaded =
        _studentCommentSlotByClassId[classId] == normalizedSlotId &&
            _studentCommentDraftByClassId.containsKey(classId) &&
            _studentCommentErrorByClassId[classId] == null;
    if (!force && alreadyLoaded) {
      return;
    }

    setState(() {
      _studentCommentLoadingByClassId[classId] = true;
      _studentCommentErrorByClassId[classId] = null;
    });

    try {
      final comments = await _api.getSlotAttendanceComments(
        classId: classId,
        slotId: normalizedSlotId,
      );
      final drafts = comments.isNotEmpty
          ? comments
              .map(
                (item) => _StudentCommentDraft(
                  key: item.key,
                  name: item.name,
                  studentId: item.studentId,
                  comment: item.comment,
                ),
              )
              .toList()
          : _fallbackStudentComments(studentNames);
      setState(() {
        _studentCommentDraftByClassId[classId] = drafts;
        _studentCommentSlotByClassId[classId] = normalizedSlotId;
        _studentCommentErrorByClassId[classId] = null;
      });
    } catch (error) {
      setState(() {
        _studentCommentDraftByClassId[classId] =
            _studentCommentDraftByClassId[classId] ??
                _fallbackStudentComments(studentNames);
        _studentCommentErrorByClassId[classId] =
            'Khong tai duoc nhan xet: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _studentCommentLoadingByClassId[classId] = false;
        });
      }
    }
  }

  Future<void> _loadPreviousStudentCommentsForClass({
    required String classId,
    required String slotId,
    bool force = false,
  }) async {
    final normalizedSlotId = slotId.trim();
    if (normalizedSlotId.isEmpty) {
      setState(() {
        _previousStudentCommentDraftByClassId[classId] = const [];
        _previousStudentCommentSlotByClassId.remove(classId);
        _previousStudentCommentErrorByClassId[classId] = null;
      });
      return;
    }

    final alreadyLoaded =
        _previousStudentCommentSlotByClassId[classId] == normalizedSlotId &&
            _previousStudentCommentDraftByClassId.containsKey(classId) &&
            _previousStudentCommentErrorByClassId[classId] == null;
    if (!force && alreadyLoaded) {
      return;
    }

    setState(() {
      _previousStudentCommentLoadingByClassId[classId] = true;
      _previousStudentCommentErrorByClassId[classId] = null;
    });

    try {
      final comments = await _api.getSlotAttendanceComments(
        classId: classId,
        slotId: normalizedSlotId,
      );
      final allDrafts = comments
          .map(
            (item) => _StudentCommentDraft(
              key: item.key,
              name: item.name,
              studentId: item.studentId,
              comment: item.comment,
            ),
          )
          .toList();
      final drafts =
          allDrafts.where((item) => item.comment.trim().isEmpty).toList();
      setState(() {
        _previousStudentCommentDraftByClassId[classId] = drafts;
        _previousStudentCommentSlotByClassId[classId] = normalizedSlotId;
        _previousStudentCommentErrorByClassId[classId] = null;
      });

      final missingCount = drafts.length;
      final warningKey = '$classId::$normalizedSlotId';
      if (missingCount > 0 &&
          mounted &&
          !_previousCommentWarningShown.contains(warningKey)) {
        _previousCommentWarningShown.add(warningKey);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Tuan truoc con $missingCount hoc vien chua nhan xet.',
            ),
          ),
        );
      }
    } catch (error) {
      setState(() {
        _previousStudentCommentDraftByClassId[classId] =
            _previousStudentCommentDraftByClassId[classId] ??
                const <_StudentCommentDraft>[];
        _previousStudentCommentErrorByClassId[classId] =
            'Khong tai duoc nhan xet buoi truoc: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _previousStudentCommentLoadingByClassId[classId] = false;
        });
      }
    }
  }

  String _buildMissingPreviousCommentMessage(
    List<_StudentCommentDraft> drafts,
  ) {
    final missingNames = drafts
        .where((item) => item.comment.trim().isEmpty)
        .map((item) => item.name.trim())
        .where((name) => name.isNotEmpty)
        .toList();
    if (missingNames.isEmpty) {
      return '';
    }

    if (missingNames.length <= 3) {
      return 'Tuan truoc con ${missingNames.length} hoc vien chua nhan xet: ${missingNames.join(', ')}.';
    }

    final head = missingNames.take(3).join(', ');
    return 'Tuan truoc con ${missingNames.length} hoc vien chua nhan xet: $head va ${missingNames.length - 3} hoc vien khac.';
  }

  void _updatePreviousStudentCommentDraft({
    required String classId,
    required String key,
    required String comment,
  }) {
    final drafts = _previousStudentCommentDraftByClassId[classId];
    if (drafts == null || drafts.isEmpty) {
      return;
    }

    final index = drafts.indexWhere((item) => item.key == key);
    if (index < 0) {
      return;
    }

    setState(() {
      drafts[index] = drafts[index].copyWith(comment: comment);
      _previousStudentCommentDraftByClassId[classId] =
          List<_StudentCommentDraft>.from(drafts);
    });
  }

  Future<void> _savePreviousWeekStudentCommentForClass({
    required String classId,
    required String slotId,
    required _StudentCommentDraft draft,
  }) async {
    final normalizedSlotId = slotId.trim();
    if (normalizedSlotId.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chua co slot tuan truoc de luu nhan xet.'),
        ),
      );
      return;
    }

    if (_previousStudentCommentSavingByClassId[classId] == true) {
      return;
    }

    setState(() {
      _previousStudentCommentSavingByClassId[classId] = true;
      _previousStudentCommentSavingDraftKeyByClassId[classId] = draft.key;
      _previousStudentCommentErrorByClassId[classId] = null;
    });

    try {
      final result = await _api.saveSlotAttendanceComments(
        classId: classId,
        slotId: normalizedSlotId,
        comments: [
          AttendanceCommentItem(
            key: draft.key,
            name: draft.name,
            studentId: draft.studentId,
            comment: draft.comment,
          ),
        ],
      );

      if (!mounted) {
        return;
      }

      final unresolved = result.unresolvedParticipants.length;
      final message = unresolved > 0
          ? 'Luu nhan xet tuan truoc cho ${draft.name} chua thanh cong ($unresolved loi map).'
          : 'Da luu nhan xet tuan truoc cho ${draft.name}.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );

      await _loadPreviousStudentCommentsForClass(
        classId: classId,
        slotId: normalizedSlotId,
        force: true,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _previousStudentCommentErrorByClassId[classId] = error.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Luu nhan xet tuan truoc that bai: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _previousStudentCommentSavingByClassId[classId] = false;
          _previousStudentCommentSavingDraftKeyByClassId.remove(classId);
        });
      }
    }
  }

  void _updateStudentCommentDraft({
    required String classId,
    required String key,
    required String comment,
  }) {
    final drafts = _studentCommentDraftByClassId[classId];
    if (drafts == null || drafts.isEmpty) {
      return;
    }

    final index = drafts.indexWhere((item) => item.key == key);
    if (index < 0) {
      return;
    }

    setState(() {
      drafts[index] = drafts[index].copyWith(comment: comment);
      _studentCommentDraftByClassId[classId] = List<_StudentCommentDraft>.from(
        drafts,
      );
    });
  }

  Future<void> _saveSingleStudentCommentForClass({
    required String classId,
    required String slotId,
    required _StudentCommentDraft draft,
    required List<String> studentNames,
  }) async {
    final normalizedSlotId = slotId.trim();
    if (normalizedSlotId.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chua co slot sap toi de luu nhan xet.'),
        ),
      );
      return;
    }

    if (_studentCommentSavingByClassId[classId] == true) {
      return;
    }

    setState(() {
      _studentCommentSavingByClassId[classId] = true;
      _studentCommentSavingDraftKeyByClassId[classId] = draft.key;
      _studentCommentErrorByClassId[classId] = null;
    });

    try {
      final result = await _api.saveSlotAttendanceComments(
        classId: classId,
        slotId: normalizedSlotId,
        comments: [
          AttendanceCommentItem(
            key: draft.key,
            name: draft.name,
            studentId: draft.studentId,
            comment: draft.comment,
          ),
        ],
      );

      if (!mounted) {
        return;
      }

      final unresolved = result.unresolvedParticipants.length;
      final message = unresolved > 0
          ? 'Luu nhan xet cho ${draft.name} chua thanh cong ($unresolved loi map).'
          : 'Da luu nhan xet cho ${draft.name} len LMS.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );

      await _loadStudentCommentsForClass(
        classId: classId,
        slotId: normalizedSlotId,
        studentNames: studentNames,
        force: true,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _studentCommentErrorByClassId[classId] = error.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Luu nhan xet that bai: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _studentCommentSavingByClassId[classId] = false;
          _studentCommentSavingDraftKeyByClassId.remove(classId);
        });
      }
    }
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
        return 'CÃƒÆ’Ã‚Â³';
      case _AttendanceUiStatus.late:
        return 'Ãƒâ€žÃ‚Âi trÃƒÂ¡Ã‚Â»Ã¢â‚¬Â¦';
      case _AttendanceUiStatus.excusedAbsent:
        return 'NghÃƒÂ¡Ã‚Â»Ã¢â‚¬Â° cÃƒÆ’Ã‚Â³ phÃƒÆ’Ã‚Â©p';
      case _AttendanceUiStatus.unexcusedAbsent:
        return 'NghÃƒÂ¡Ã‚Â»Ã¢â‚¬Â° khÃƒÆ’Ã‚Â´ng phÃƒÆ’Ã‚Â©p';
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

  String _attendanceApiStatus(_AttendanceUiStatus status) {
    switch (status) {
      case _AttendanceUiStatus.present:
        return 'ATTENDED';
      case _AttendanceUiStatus.late:
        return 'LATE_ARRIVED';
      case _AttendanceUiStatus.excusedAbsent:
        return 'ABSENT_WITH_NOTICE';
      case _AttendanceUiStatus.unexcusedAbsent:
        return 'ABSENT';
    }
  }

  Future<void> _saveAttendanceForClass({
    required String classId,
    required String slotId,
    required List<_AttendanceParticipant> participants,
  }) async {
    if (_attendanceSavingByClassId[classId] == true) {
      return;
    }
    if (slotId.trim().isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Khong tim thay slot sap toi de luu diem danh.'),
        ),
      );
      return;
    }

    final snapshot = _buildAttendanceSnapshotForClass(
      classId: classId,
      participants: participants,
    );
    final participantByKey = <String, _AttendanceParticipant>{};
    for (final item in participants) {
      participantByKey[item.key] = item;
    }

    final selectedParticipants = <AttendanceSaveParticipant>[];
    snapshot.forEach((participantKey, status) {
      final participant = participantByKey[participantKey];
      if (participant == null) {
        return;
      }

      selectedParticipants.add(
        AttendanceSaveParticipant(
          key: participant.key,
          name: participant.name,
          isCoTeacher: participant.isCoTeacher,
          status: _attendanceApiStatus(status),
        ),
      );
    });

    if (selectedParticipants.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chua co ai duoc chon trang thai de luu diem danh.'),
        ),
      );
      return;
    }

    setState(() {
      _attendanceSavingByClassId[classId] = true;
    });

    try {
      final result = await _api.saveSlotAttendance(
        classId: classId,
        slotId: slotId,
        participants: selectedParticipants,
      );

      final appliedKeySet = result.appliedParticipantKeys.toSet();
      final savedSnapshot = Map<String, _AttendanceUiStatus>.from(snapshot);
      if (appliedKeySet.isNotEmpty) {
        savedSnapshot.removeWhere((key, _) => !appliedKeySet.contains(key));
      }

      setState(() {
        _attendanceSavedSnapshotByClassId[classId] = savedSnapshot;
        _attendanceSavedAtByClassId[classId] = DateTime.now();
      });

      if (!mounted) {
        return;
      }

      final unresolvedCount = result.unresolvedParticipants.length;
      final savedCount = result.appliedParticipants;
      final saveMessage = unresolvedCount > 0
          ? 'Da luu $savedCount ket qua, con $unresolvedCount nguoi chua map duoc.'
          : 'Da luu $savedCount ket qua diem danh cho lop nay.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(saveMessage),
          backgroundColor:
              unresolvedCount > 0 ? Colors.orange.shade700 : Colors.green[700],
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Luu diem danh that bai: $error'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _attendanceSavingByClassId[classId] = false;
        });
      }
    }
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
                  'Xin chÃƒÆ’Ã‚Â o, ${_session.username}',
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
                  'ChÃƒÆ’Ã‚Âºc bÃƒÂ¡Ã‚ÂºÃ‚Â¡n cÃƒÆ’Ã‚Â³ mÃƒÂ¡Ã‚Â»Ã¢â€žÂ¢t ngÃƒÆ’Ã‚Â y dÃƒÂ¡Ã‚ÂºÃ‚Â¡y thÃƒÂ¡Ã‚ÂºÃ‚Â­t hiÃƒÂ¡Ã‚Â»Ã¢â‚¬Â¡u quÃƒÂ¡Ã‚ÂºÃ‚Â£.',
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
            title: 'TÃƒÂ¡Ã‚Â»Ã¢â‚¬Â¢ng quan nhanh',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FutureBuilder<List<ClassSummary>>(
                  future: _classesFuture,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const _KpiTile.loading(
                          label:
                              'LÃƒÂ¡Ã‚Â»Ã¢â‚¬Âºp Ãƒâ€žÃ¢â‚¬Ëœang dÃƒÂ¡Ã‚ÂºÃ‚Â¡y');
                    }
                    final classes = snapshot.data ?? const <ClassSummary>[];
                    final students = classes.fold<int>(
                      0,
                      (sum, cls) => sum + cls.totalStudents,
                    );
                    return _KpiTile(
                      label: 'LÃƒÂ¡Ã‚Â»Ã¢â‚¬Âºp Ãƒâ€žÃ¢â‚¬Ëœang dÃƒÂ¡Ã‚ÂºÃ‚Â¡y',
                      value: classes.length.toString(),
                      hint: '$students hÃƒÂ¡Ã‚Â»Ã‚Âc viÃƒÆ’Ã‚Âªn',
                      icon: Icons.menu_book_rounded,
                    );
                  },
                ),
                FutureBuilder<List<ReminderItem>>(
                  future: _remindersFuture,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const _KpiTile.loading(
                          label:
                              'LÃƒÂ¡Ã‚Â»Ã¢â‚¬Â¹ch sÃƒÂ¡Ã‚ÂºÃ‚Â¯p tÃƒÂ¡Ã‚Â»Ã¢â‚¬Âºi');
                    }
                    final reminders = snapshot.data ?? const <ReminderItem>[];
                    final openCount =
                        reminders.where((item) => item.isWindowOpen).length;
                    return _KpiTile(
                      label:
                          'LÃƒÂ¡Ã‚Â»Ã¢â‚¬Â¹ch sÃƒÂ¡Ã‚ÂºÃ‚Â¯p tÃƒÂ¡Ã‚Â»Ã¢â‚¬Âºi',
                      value: reminders.length.toString(),
                      hint: '$openCount khung Ãƒâ€žÃ¢â‚¬Ëœang mÃƒÂ¡Ã‚Â»Ã…Â¸',
                      icon: Icons.event_available_rounded,
                    );
                  },
                ),
                FutureBuilder<PayrollResponse>(
                  future: _payrollFuture,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const _KpiTile.loading(
                          label: 'Thu nhÃƒÂ¡Ã‚ÂºÃ‚Â­p');
                    }
                    final payroll = snapshot.data!;
                    final money = _calculatePayrollMoney(
                      payroll,
                      _parseHourlyRate(),
                      _parseManualAdjustment(),
                    );
                    return _KpiTile(
                      label:
                          'Thu nhÃƒÂ¡Ã‚ÂºÃ‚Â­p hiÃƒÂ¡Ã‚Â»Ã¢â‚¬Â¡n tÃƒÂ¡Ã‚ÂºÃ‚Â¡i',
                      value: _formatMoney(money.actualIncome),
                      hint: 'ThÃƒÆ’Ã‚Â¡ng ${payroll.month}/${payroll.year}',
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
            title: 'Lop chua nhan xet',
            subtitle: 'Cac lop con hoc vien chua nhan xet tuan truoc',
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
                final pendingClasses = classes
                    .where(
                      (cls) =>
                          (cls.previousCommentContext
                                  ?.missingCommentStudentCount ??
                              0) >
                          0,
                    )
                    .toList()
                  ..sort((a, b) {
                    final aCount =
                        a.previousCommentContext?.missingCommentStudentCount ??
                            0;
                    final bCount =
                        b.previousCommentContext?.missingCommentStudentCount ??
                            0;
                    if (aCount != bCount) {
                      return bCount.compareTo(aCount);
                    }
                    final aStart = _parseDateTimeLoose(
                          a.previousCommentContext?.slotStartTime,
                        )?.millisecondsSinceEpoch ??
                        0;
                    final bStart = _parseDateTimeLoose(
                          b.previousCommentContext?.slotStartTime,
                        )?.millisecondsSinceEpoch ??
                        0;
                    return bStart.compareTo(aStart);
                  });
                if (pendingClasses.isEmpty) {
                  return const _EmptyLabel(
                    message: 'Khong co lop nao chua nhan xet tuan truoc.',
                  );
                }
                return Column(
                  children: pendingClasses.take(6).map((cls) {
                    final commentContext = cls.previousCommentContext;
                    final missingCount =
                        commentContext?.missingCommentStudentCount ?? 0;
                    final sessionLabel = commentContext?.sessionNumber != null
                        ? 'Buoi ${commentContext!.sessionNumber}'
                        : 'Tuan truoc';
                    final slotStartLabel =
                        _formatDateTime(commentContext?.slotStartTime);
                    final missingNames =
                        commentContext?.missingCommentStudents ??
                            const <String>[];
                    final preview = missingNames.take(2).join(', ');
                    final moreCount =
                        missingNames.length > 2 ? missingNames.length - 2 : 0;
                    final detailText = preview.isEmpty
                        ? 'Con $missingCount hoc vien chua nhan xet.'
                        : moreCount > 0
                            ? 'Con $missingCount hoc vien: $preview va $moreCount hoc vien khac.'
                            : 'Con $missingCount hoc vien: $preview.';
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
                          cls.className,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        subtitle: Text(
                          '$sessionLabel - $slotStartLabel\n$detailText',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: _Pill(
                          label: '$missingCount HV',
                          background: const Color(0xFFFFF4E5),
                          foreground: const Color(0xFF92400E),
                          icon: Icons.warning_amber_rounded,
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
            title:
                'LÃƒÂ¡Ã‚Â»Ã¢â‚¬Âºp hÃƒÂ¡Ã‚Â»Ã‚Âc Ãƒâ€žÃ¢â‚¬Ëœang phÃƒÂ¡Ã‚Â»Ã‚Â¥ trÃƒÆ’Ã‚Â¡ch',
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
                  return const _EmptyLabel(
                      message:
                          'ChÃƒâ€ Ã‚Â°a cÃƒÆ’Ã‚Â³ lÃƒÂ¡Ã‚Â»Ã¢â‚¬Âºp Ãƒâ€žÃ¢â‚¬Ëœang chÃƒÂ¡Ã‚ÂºÃ‚Â¡y.');
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
                            '${cls.className} Ãƒâ€šÃ‚Â· ${cls.totalStudents} HV',
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
        future: _classesAndRemindersFuture,
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
            return const _EmptyView(
                message:
                    'KhÃƒÆ’Ã‚Â´ng cÃƒÆ’Ã‚Â³ lÃƒÂ¡Ã‚Â»Ã¢â‚¬Âºp Ãƒâ€žÃ¢â‚¬Ëœang hoÃƒÂ¡Ã‚ÂºÃ‚Â¡t Ãƒâ€žÃ¢â‚¬ËœÃƒÂ¡Ã‚Â»Ã¢â€žÂ¢ng.');
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
            key: const PageStorageKey<String>('classes_list_view'),
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
                      'ChÃƒâ€ Ã‚Â°a rÃƒÆ’Ã‚Âµ vai trÃƒÆ’Ã‚Â²')
                  : 'ChÃƒâ€ Ã‚Â°a rÃƒÆ’Ã‚Âµ vai trÃƒÆ’Ã‚Â²';
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
              final studentNames = cls.students
                  .map((item) => item.trim())
                  .where((item) => item.isNotEmpty)
                  .toList();

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
              final isSavingAttendance =
                  _attendanceSavingByClassId[cls.classId] == true;
              final saveSlotId = (nextReminder?.slotId.isNotEmpty == true)
                  ? nextReminder!.slotId
                  : (cls.nextAttendanceWindow?.slotId ?? '');
              final nextClassStartTime = nextReminder?.slotStartTime ??
                  cls.nextAttendanceWindow?.slotStartTime;
              final countdownBadge =
                  _formatDayHourMinuteCountdown(nextClassStartTime);
              final selectedSection =
                  _classSectionByClassId.containsKey(cls.classId)
                      ? _classSectionByClassId[cls.classId]
                      : null;
              final commentDrafts =
                  _studentCommentDraftByClassId[cls.classId] ??
                      const <_StudentCommentDraft>[];
              final previousCommentDrafts =
                  _previousStudentCommentDraftByClassId[cls.classId] ??
                      const <_StudentCommentDraft>[];
              final previousMissingCount =
                  cls.previousCommentContext?.missingCommentStudentCount ?? 0;
              final isLoadingComments =
                  _studentCommentLoadingByClassId[cls.classId] == true;
              final isLoadingPreviousComments =
                  _previousStudentCommentLoadingByClassId[cls.classId] == true;
              final isSavingComments =
                  _studentCommentSavingByClassId[cls.classId] == true;
              final isSavingPreviousComments =
                  _previousStudentCommentSavingByClassId[cls.classId] == true;
              final savingDraftKey =
                  _studentCommentSavingDraftKeyByClassId[cls.classId];
              final savingPreviousDraftKey =
                  _previousStudentCommentSavingDraftKeyByClassId[cls.classId];
              final commentsError = _studentCommentErrorByClassId[cls.classId];
              final previousCommentsError =
                  _previousStudentCommentErrorByClassId[cls.classId];
              final previousSlotId = cls.previousCommentContext?.slotId ?? '';
              final previousMissingMessage =
                  _buildMissingPreviousCommentMessage(previousCommentDrafts);
              final previousCommentHeader = cls
                          .previousCommentContext?.sessionNumber !=
                      null
                  ? 'Hoc vien chua nhan xet (buoi ${cls.previousCommentContext!.sessionNumber})'
                  : 'Hoc vien chua nhan xet (tuan truoc)';
              final classStartLabel = _formatDateTime(cls.classStartDate);
              final classEndLabel = _formatDateTime(cls.classEndDate);
              final isAttendanceWindowOpen = nextReminder?.isWindowOpen ??
                  cls.nextAttendanceWindow?.isWindowOpen ??
                  false;
              final attendanceRemainingLabel = isAttendanceWindowOpen
                  ? 'Con ${_formatDurationMinutesVi(nextReminder?.minutesUntilWindowClose ?? cls.nextAttendanceWindow?.minutesUntilWindowClose ?? 0, compact: true)} de diem danh'
                  : (nextClassStartTime != null &&
                          nextClassStartTime.trim().isNotEmpty
                      ? 'Con ${_formatDayHourMinuteCountdown(nextClassStartTime)} den buoi hoc tiep theo'
                      : 'Chua co buoi hoc tiep theo');

              return Card(
                key: ValueKey<String>('class_card_${cls.classId}'),
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
                            label: countdownBadge,
                            background: const Color(0xFFE3EEFF),
                            foreground: const Color(0xFF154EA3),
                            icon: Icons.schedule_rounded,
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
                            label:
                                '${cls.totalStudents} hÃƒÂ¡Ã‚Â»Ã‚Âc viÃƒÆ’Ã‚Âªn',
                          ),
                          if (cls.coTeachers.isNotEmpty)
                            _MiniStat(
                              icon: Icons.groups_rounded,
                              label:
                                  '${cls.coTeachers.length} Ãƒâ€žÃ¢â‚¬ËœÃƒÂ¡Ã‚Â»Ã¢â‚¬Å“ng giÃƒÆ’Ã‚Â¡o viÃƒÆ’Ã‚Âªn',
                            ),
                          if (previousMissingCount > 0)
                            _MiniStat(
                              icon: Icons.warning_amber_rounded,
                              label:
                                  '$previousMissingCount hÃƒÂ¡Ã‚Â»Ã‚Âc viÃƒÆ’Ã‚Âªn chÃƒâ€ Ã‚Â°a nhÃƒÂ¡Ã‚ÂºÃ‚Â­n xÃƒÆ’Ã‚Â©t tuÃƒÂ¡Ã‚ÂºÃ‚Â§n trÃƒâ€ Ã‚Â°ÃƒÂ¡Ã‚Â»Ã¢â‚¬Âºc',
                            ),
                        ],
                      ),
                      if (cls.coTeachers.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Ãƒâ€žÃ‚ÂÃƒÂ¡Ã‚Â»Ã¢â‚¬Å“ng giÃƒÆ’Ã‚Â¡o viÃƒÆ’Ã‚Âªn: ${cls.coTeachers.join(', ')}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.blueGrey.shade700,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F6FC),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _ClassSectionButton(
                                label: 'Chi tiÃƒÂ¡Ã‚ÂºÃ‚Â¿t',
                                icon: Icons.info_outline_rounded,
                                selected: selectedSection ==
                                    _ClassCardSection.details,
                                onPressed: () {
                                  _toggleClassSection(
                                    classId: cls.classId,
                                    section: _ClassCardSection.details,
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _ClassSectionButton(
                                label: 'Ãƒâ€žÃ‚ÂiÃƒÂ¡Ã‚Â»Ã†â€™m danh',
                                icon: Icons.fact_check_outlined,
                                selected: selectedSection ==
                                    _ClassCardSection.attendance,
                                onPressed: () {
                                  _toggleClassSection(
                                    classId: cls.classId,
                                    section: _ClassCardSection.attendance,
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _ClassSectionButton(
                                label: 'NhÃƒÂ¡Ã‚ÂºÃ‚Â­n xÃƒÆ’Ã‚Â©t',
                                icon: Icons.edit_note_rounded,
                                selected:
                                    selectedSection == _ClassCardSection.note,
                                onPressed: () {
                                  final isActive =
                                      selectedSection == _ClassCardSection.note;
                                  _toggleClassSection(
                                    classId: cls.classId,
                                    section: _ClassCardSection.note,
                                  );
                                  if (!isActive) {
                                    final previousSlotId =
                                        cls.previousCommentContext?.slotId ??
                                            '';
                                    _loadStudentCommentsForClass(
                                      classId: cls.classId,
                                      slotId: saveSlotId,
                                      studentNames: studentNames,
                                    );
                                    _loadPreviousStudentCommentsForClass(
                                      classId: cls.classId,
                                      slotId: previousSlotId,
                                    );
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (selectedSection != null) const SizedBox(height: 10),
                      if (selectedSection == _ClassCardSection.details) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F7FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Thong tin lop hoc',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(
                                      color: const Color(0xFF1C4ED8),
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                              const SizedBox(height: 6),
                              Text('So luong hoc vien: ${cls.totalStudents}'),
                              const SizedBox(height: 4),
                              Text('Role cua toi: $roleLabel'),
                              const SizedBox(height: 8),
                              Text('Bat dau khoa hoc: $classStartLabel'),
                              const SizedBox(height: 4),
                              Text('Ket thuc khoa hoc: $classEndLabel'),
                              const SizedBox(height: 8),
                              _MiniStat(
                                icon: isAttendanceWindowOpen
                                    ? Icons.login_rounded
                                    : Icons.schedule_rounded,
                                label: attendanceRemainingLabel,
                              ),
                              if (nextReminder != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Buoi sap toi: ${_formatDateTime(nextReminder.slotStartTime)} - '
                                  '${_formatDateTime(nextReminder.slotEndTime)}',
                                ),
                                const SizedBox(height: 4),
                                Text('Slot ${nextReminder.slotIndex ?? '-'}'),
                              ],
                            ],
                          ),
                        ),
                      ] else if (selectedSection ==
                          _ClassCardSection.attendance) ...[
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blueGrey.shade100),
                          ),
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ãƒâ€žÃ‚ÂiÃƒÂ¡Ã‚Â»Ã†â€™m danh (${participants.length})',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Co $presentCount Ãƒâ€šÃ‚Â· Tre $lateCount Ãƒâ€šÃ‚Â· Co phep $excusedCount Ãƒâ€šÃ‚Â· Khong phep $unexcusedCount',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 8),
                              if (participants.isEmpty)
                                const Text(
                                  'ChÃƒâ€ Ã‚Â°a cÃƒÆ’Ã‚Â³ hÃƒÂ¡Ã‚Â»Ã‚Âc viÃƒÆ’Ã‚Âªn/Ãƒâ€žÃ¢â‚¬ËœÃƒÂ¡Ã‚Â»Ã¢â‚¬Å“ng giÃƒÆ’Ã‚Â¡o viÃƒÆ’Ã‚Âªn Ãƒâ€žÃ¢â‚¬ËœÃƒÂ¡Ã‚Â»Ã†â€™ Ãƒâ€žÃ¢â‚¬ËœiÃƒÂ¡Ã‚Â»Ã†â€™m danh.',
                                )
                              else ...[
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
                                                label:
                                                    'Ãƒâ€žÃ‚ÂÃƒÂ¡Ã‚Â»Ã¢â‚¬Å“ng GV',
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
                                          children:
                                              _AttendanceUiStatus.values.map(
                                            (option) {
                                              final isSelected =
                                                  status == option;
                                              return Tooltip(
                                                message: _attendanceStatusLabel(
                                                  option,
                                                ),
                                                triggerMode: TooltipTriggerMode
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
                                                        : Colors
                                                            .blueGrey.shade200,
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
                                          ).toList(),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                                const SizedBox(height: 4),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton.icon(
                                    onPressed: participants.isEmpty ||
                                            isSavingAttendance
                                        ? null
                                        : () => _saveAttendanceForClass(
                                              classId: cls.classId,
                                              slotId: saveSlotId,
                                              participants: participants,
                                            ),
                                    icon: isSavingAttendance
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.save_rounded),
                                    label: Text(
                                      isSavingAttendance
                                          ? 'Ãƒâ€žÃ‚Âang lÃƒâ€ Ã‚Â°u Ãƒâ€žÃ¢â‚¬ËœiÃƒÂ¡Ã‚Â»Ã†â€™m danh...'
                                          : 'LÃƒâ€ Ã‚Â°u kÃƒÂ¡Ã‚ÂºÃ‚Â¿t quÃƒÂ¡Ã‚ÂºÃ‚Â£ Ãƒâ€žÃ¢â‚¬ËœiÃƒÂ¡Ã‚Â»Ã†â€™m danh',
                                    ),
                                  ),
                                ),
                                if (savedAt != null) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'Ãƒâ€žÃ‚ÂÃƒÆ’Ã‚Â£ lÃƒâ€ Ã‚Â°u lÃƒÆ’Ã‚Âºc ${DateFormat('HH:mm:ss - dd/MM/yyyy').format(savedAt)}'
                                    '${isDirty ? ' Ãƒâ€šÃ‚Â· CÃƒÆ’Ã‚Â³ thay Ãƒâ€žÃ¢â‚¬ËœÃƒÂ¡Ã‚Â»Ã¢â‚¬Â¢i chÃƒâ€ Ã‚Â°a lÃƒâ€ Ã‚Â°u' : ''}',
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
                            ],
                          ),
                        ),
                      ] else if (selectedSection == _ClassCardSection.note) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7F8FB),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blueGrey.shade100),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Nhan xet tung hoc vien',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 8),
                              if (saveSlotId.isEmpty)
                                const _EmptyLabel(
                                  message: 'Chua co slot sap toi de nhan xet.',
                                )
                              else if (isLoadingComments)
                                const _InlineLoading()
                              else if (commentsError != null)
                                _ErrorLabel(message: commentsError)
                              else if (commentDrafts.isEmpty)
                                const _EmptyLabel(
                                  message:
                                      'Chua co hoc vien de nhan xet cho slot nay.',
                                )
                              else ...[
                                ...commentDrafts.map((item) {
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFF),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.name,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                        const SizedBox(height: 6),
                                        TextFormField(
                                          key: ValueKey<String>(
                                            'comment_${cls.classId}_${item.key}_$saveSlotId',
                                          ),
                                          initialValue: item.comment,
                                          minLines: 2,
                                          maxLines: 4,
                                          decoration: const InputDecoration(
                                            hintText:
                                                'Nhap nhan xet cho hoc vien nay',
                                          ),
                                          onChanged: (value) {
                                            _updateStudentCommentDraft(
                                              classId: cls.classId,
                                              key: item.key,
                                              comment: value,
                                            );
                                          },
                                        ),
                                        const SizedBox(height: 8),
                                        SizedBox(
                                          width: double.infinity,
                                          child: FilledButton.icon(
                                            onPressed: isSavingComments
                                                ? null
                                                : () =>
                                                    _saveSingleStudentCommentForClass(
                                                      classId: cls.classId,
                                                      slotId: saveSlotId,
                                                      draft: item,
                                                      studentNames:
                                                          studentNames,
                                                    ),
                                            icon: isSavingComments &&
                                                    savingDraftKey == item.key
                                                ? const SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                                  )
                                                : const Icon(
                                                    Icons.save_rounded,
                                                  ),
                                            label: Text(
                                              isSavingComments &&
                                                      savingDraftKey == item.key
                                                  ? 'Dang luu...'
                                                  : 'Luu nhan xet hoc vien nay',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                              const SizedBox(height: 10),
                              const Divider(height: 1),
                              const SizedBox(height: 10),
                              Text(
                                previousCommentHeader,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 8),
                              if (previousSlotId.isEmpty)
                                const _EmptyLabel(
                                  message:
                                      'Chua co du lieu tuan truoc de kiem tra nhan xet.',
                                )
                              else if (isLoadingPreviousComments)
                                const _InlineLoading()
                              else if (previousCommentsError != null)
                                _ErrorLabel(message: previousCommentsError)
                              else if (previousCommentDrafts.isEmpty)
                                const _EmptyLabel(
                                  message:
                                      'Tuan truoc tat ca hoc vien da co nhan xet.',
                                )
                              else ...[
                                if (previousMissingMessage.isNotEmpty)
                                  Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF4E5),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                          color: const Color(0xFFF5D0A9)),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Padding(
                                          padding: EdgeInsets.only(top: 1),
                                          child: Icon(
                                            Icons.warning_amber_rounded,
                                            color: Color(0xFFB45309),
                                            size: 18,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            previousMissingMessage,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color:
                                                      const Color(0xFF92400E),
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ...previousCommentDrafts.map((item) {
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFFBEB),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: const Color(0xFFF3D9AA),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.name,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        TextFormField(
                                          key: ValueKey<String>(
                                            'previous_comment_${cls.classId}_${item.key}_$previousSlotId',
                                          ),
                                          initialValue: item.comment,
                                          minLines: 2,
                                          maxLines: 4,
                                          decoration: const InputDecoration(
                                            hintText:
                                                'Nhap nhan xet cho hoc vien tuan truoc',
                                          ),
                                          onChanged: (value) {
                                            _updatePreviousStudentCommentDraft(
                                              classId: cls.classId,
                                              key: item.key,
                                              comment: value,
                                            );
                                          },
                                        ),
                                        const SizedBox(height: 8),
                                        SizedBox(
                                          width: double.infinity,
                                          child: FilledButton.icon(
                                            onPressed: isSavingPreviousComments
                                                ? null
                                                : () =>
                                                    _savePreviousWeekStudentCommentForClass(
                                                      classId: cls.classId,
                                                      slotId: previousSlotId,
                                                      draft: item,
                                                    ),
                                            icon: isSavingPreviousComments &&
                                                    savingPreviousDraftKey ==
                                                        item.key
                                                ? const SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                                  )
                                                : const Icon(
                                                    Icons.save_rounded,
                                                  ),
                                            label: Text(
                                              isSavingPreviousComments &&
                                                      savingPreviousDraftKey ==
                                                          item.key
                                                  ? 'Dang luu...'
                                                  : 'Luu nhan xet tuan truoc',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ],
                          ),
                        ),
                      ],
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
            return const _EmptyView(
                message:
                    'KhÃƒÆ’Ã‚Â´ng cÃƒÆ’Ã‚Â³ dÃƒÂ¡Ã‚Â»Ã‚Â¯ liÃƒÂ¡Ã‚Â»Ã¢â‚¬Â¡u thu nhÃƒÂ¡Ã‚ÂºÃ‚Â­p.');
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
                title:
                    'BÃƒÂ¡Ã‚Â»Ã¢â€žÂ¢ lÃƒÂ¡Ã‚Â»Ã‚Âc kÃƒÂ¡Ã‚Â»Ã‚Â³ lÃƒâ€ Ã‚Â°Ãƒâ€ Ã‚Â¡ng',
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: _selectedPayrollMonth,
                            decoration: const InputDecoration(
                                labelText: 'ThÃƒÆ’Ã‚Â¡ng'),
                            items: monthOptions
                                .map(
                                  (month) => DropdownMenuItem<int>(
                                    value: month,
                                    child: Text('ThÃƒÆ’Ã‚Â¡ng $month'),
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
                            decoration: const InputDecoration(
                                labelText: 'NÃƒâ€žÃ†â€™m'),
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
                              labelText:
                                  'LÃƒâ€ Ã‚Â°Ãƒâ€ Ã‚Â¡ng theo giÃƒÂ¡Ã‚Â»Ã‚Â (VND)',
                              hintText: 'VÃƒÆ’Ã‚Â­ dÃƒÂ¡Ã‚Â»Ã‚Â¥: 150000',
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
                              labelText:
                                  'CÃƒÆ’Ã‚Â´ng bÃƒÆ’Ã‚Â¹ / Ãƒâ€žÃ¢â‚¬ËœiÃƒÂ¡Ã‚Â»Ã‚Âu chÃƒÂ¡Ã‚Â»Ã¢â‚¬Â°nh',
                              hintText:
                                  'VÃƒÆ’Ã‚Â­ dÃƒÂ¡Ã‚Â»Ã‚Â¥: 300000 hoÃƒÂ¡Ã‚ÂºÃ‚Â·c -200000',
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
                            label: const Text(
                                'Xem dÃƒÂ¡Ã‚Â»Ã‚Â¯ liÃƒÂ¡Ã‚Â»Ã¢â‚¬Â¡u'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _forceRefreshPayroll,
                            icon: const Icon(Icons.cloud_sync_rounded),
                            label: const Text(
                                'CÃƒÂ¡Ã‚ÂºÃ‚Â­p nhÃƒÂ¡Ã‚ÂºÃ‚Â­t mÃƒÂ¡Ã‚Â»Ã¢â‚¬Âºi'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title:
                    'TÃƒÂ¡Ã‚Â»Ã¢â‚¬Â¢ng hÃƒÂ¡Ã‚Â»Ã‚Â£p thu nhÃƒÂ¡Ã‚ÂºÃ‚Â­p ${payroll.month}/${payroll.year}',
                subtitle:
                    'Ãƒâ€žÃ‚ÂÃƒÆ’Ã‚Â£ tÃƒÆ’Ã‚Â­nh role + office hour + cÃƒÆ’Ã‚Â´ng bÃƒÆ’Ã‚Â¹ thÃƒÂ¡Ã‚Â»Ã‚Â§ cÃƒÆ’Ã‚Â´ng',
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
                      'Thu nhÃƒÂ¡Ã‚ÂºÃ‚Â­p lÃƒÂ¡Ã‚Â»Ã¢â‚¬Âºp hÃƒÂ¡Ã‚Â»Ã‚Âc: ${_formatMoney(moneySummary.classIncome)}',
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Thu nhÃƒÂ¡Ã‚ÂºÃ‚Â­p office hour: ${_formatMoney(moneySummary.officeHourIncome)}',
                    ),
                    Text(
                      'CÃƒÆ’Ã‚Â´ng bÃƒÆ’Ã‚Â¹ / Ãƒâ€žÃ¢â‚¬ËœiÃƒÂ¡Ã‚Â»Ã‚Âu chÃƒÂ¡Ã‚Â»Ã¢â‚¬Â°nh: ${_formatMoney(moneySummary.manualAdjustment)}',
                      style: TextStyle(
                        color: moneySummary.manualAdjustment < 0
                            ? Colors.red.shade700
                            : Colors.green.shade700,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'TÃƒÂ¡Ã‚Â»Ã¢â‚¬Â¢ng hiÃƒÂ¡Ã‚Â»Ã¢â‚¬Â¡n tÃƒÂ¡Ã‚ÂºÃ‚Â¡i: ${_formatMoney(moneySummary.actualIncome)}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.green.shade700,
                          ),
                    ),
                    Text(
                      'TÃƒÂ¡Ã‚Â»Ã¢â‚¬Â¢ng dÃƒÂ¡Ã‚Â»Ã‚Â± kiÃƒÂ¡Ã‚ÂºÃ‚Â¿n cuÃƒÂ¡Ã‚Â»Ã¢â‚¬Ëœi thÃƒÆ’Ã‚Â¡ng: ${_formatMoney(moneySummary.projectedIncome)}',
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
                            '${role.role}: ${role.slotCount} slots Ãƒâ€šÃ‚Â· ${role.totalHours}h',
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              if (payroll.officeHours.isNotEmpty) ...[
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'Chi tiÃƒÂ¡Ã‚ÂºÃ‚Â¿t office hour',
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
                          title:
                              Text('$typeLabel Ãƒâ€šÃ‚Â· ${officeHour.status}'),
                          subtitle: Text(
                            '${_formatDateTime(officeHour.startTime)} - ${_formatDateTime(officeHour.endTime)}\n'
                            '${officeHour.studentCount} hÃƒÂ¡Ã‚Â»Ã‚Âc viÃƒÆ’Ã‚Âªn Ãƒâ€šÃ‚Â· ${officeHour.durationHours}h',
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
                  title: 'Chi tiÃƒÂ¡Ã‚ÂºÃ‚Â¿t theo lÃƒÂ¡Ã‚Â»Ã¢â‚¬Âºp',
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
                            '${cls.taughtSlotCount} slots Ãƒâ€šÃ‚Â· ${cls.totalHours}h',
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
                                    'Slot ${slot.slotIndex ?? '-'} Ãƒâ€šÃ‚Â· ${slot.attendanceStatus}',
                                  ),
                                  subtitle: Text(
                                    '${_formatDateTime(slot.startTime)} - ${_formatDateTime(slot.endTime)}\n'
                                    'Vai trÃƒÆ’Ã‚Â² ${slot.roleShortName ?? slot.roleName ?? 'UNKNOWN'} Ãƒâ€šÃ‚Â· ${slot.durationHours}h',
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
    final titles = [
      'TÃƒÂ¡Ã‚Â»Ã¢â‚¬Â¢ng quan',
      'LÃƒÂ¡Ã‚Â»Ã¢â‚¬Âºp hÃƒÂ¡Ã‚Â»Ã‚Âc',
      'Thu nhÃƒÂ¡Ã‚ÂºÃ‚Â­p'
    ];
    final safeIndex = _selectedIndex.clamp(0, titles.length - 1);
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[safeIndex]),
        actions: [
          IconButton(
            onPressed: _forceRefreshAll,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'LÃƒÆ’Ã‚Â m mÃƒÂ¡Ã‚Â»Ã¢â‚¬Âºi',
          ),
          IconButton(
            onPressed: widget.onSignOut,
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Ãƒâ€žÃ‚ÂÃƒâ€žÃ†â€™ng xuÃƒÂ¡Ã‚ÂºÃ‚Â¥t',
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
              label: 'TÃƒÂ¡Ã‚Â»Ã¢â‚¬Â¢ng quan',
            ),
            NavigationDestination(
              icon: Icon(Icons.class_outlined),
              selectedIcon: Icon(Icons.class_rounded),
              label: 'LÃƒÂ¡Ã‚Â»Ã¢â‚¬Âºp hÃƒÂ¡Ã‚Â»Ã‚Âc',
            ),
            NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined),
              selectedIcon: Icon(Icons.account_balance_wallet_rounded),
              label: 'Thu nhÃƒÂ¡Ã‚ÂºÃ‚Â­p',
            ),
          ],
        ),
      ),
      floatingActionButton: safeIndex == 2
          ? FloatingActionButton.extended(
              onPressed: _forceRefreshPayroll,
              icon: const Icon(Icons.sync_rounded),
              label: const Text(
                  'CÃƒÂ¡Ã‚ÂºÃ‚Â­p nhÃƒÂ¡Ã‚ÂºÃ‚Â­t lÃƒâ€ Ã‚Â°Ãƒâ€ Ã‚Â¡ng'),
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
        hint = 'Ãƒâ€žÃ‚Âang tÃƒÂ¡Ã‚ÂºÃ‚Â£i',
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

class _ClassSectionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  const _ClassSectionButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        backgroundColor:
            selected ? const Color(0xFFE3EEFF) : const Color(0xFFF9FBFF),
        foregroundColor:
            selected ? const Color(0xFF1C4ED8) : Colors.blueGrey.shade700,
      ),
      icon: Icon(icon, size: 16),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
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

class _StudentCommentDraft {
  final String key;
  final String name;
  final String? studentId;
  final String comment;

  const _StudentCommentDraft({
    required this.key,
    required this.name,
    required this.studentId,
    required this.comment,
  });

  _StudentCommentDraft copyWith({
    String? key,
    String? name,
    String? studentId,
    String? comment,
  }) {
    return _StudentCommentDraft(
      key: key ?? this.key,
      name: name ?? this.name,
      studentId: studentId ?? this.studentId,
      comment: comment ?? this.comment,
    );
  }
}

enum _ClassCardSection {
  details,
  attendance,
  note,
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
