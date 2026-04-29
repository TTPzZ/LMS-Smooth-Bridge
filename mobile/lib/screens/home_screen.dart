import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/api_models.dart';
import '../models/auth_models.dart';
import '../services/auth_session_manager.dart';
import '../services/backend_api_service.dart';
import '../services/dashboard_cache_service.dart';
import '../services/local_notification_service.dart';
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
  final bool showPendingCommentReminderOnLogin;

  const HomeScreen({
    super.key,
    required this.sessionManager,
    required this.onSignOut,
    this.showPendingCommentReminderOnLogin = false,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const Duration _classesCacheTtl = Duration(minutes: 20);
  static const Duration _remindersCacheTtl = Duration(minutes: 8);
  static const Duration _payrollCacheTtl = Duration(minutes: 20);
  static const Duration _tabSwitchDuration = Duration(milliseconds: 240);
  static const String _pullHintHiddenPrefix = 'home.pull_hint_hidden_v1';

  late BackendApiService _api;
  final DashboardCacheService _dashboardCache = DashboardCacheService();
  late final TextEditingController _hourlyRateController;
  late final TextEditingController _manualAdjustmentController;
  late final PageController _pageController;
  Timer? _payrollInputDebounce;

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
  bool _isPullActionsSheetOpen = false;
  bool _isShowingPullHint = false;
  bool _isShowingPendingCommentNotice = false;
  bool _didCheckPendingCommentReminder = false;
  final Map<String, GlobalKey> _classCardKeyByClassId = {};
  String? _pendingRevealClassId;
  int _pendingRevealAttempts = 0;
  List<ClassSummary>? _cachedClassesSource;
  List<ReminderItem>? _cachedRemindersSource;
  _ClassesPageComputed? _cachedClassesPageComputed;

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
    _pageController = PageController(initialPage: _selectedIndex);
    _api = BackendApiService(
      baseUrl: AppConfig.apiBaseUrl.trim(),
      idTokenProvider: _provideIdToken,
    );
    _setFutures(forceNetwork: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runPostLoginNotices());
    });
  }

  @override
  void dispose() {
    _payrollInputDebounce?.cancel();
    _pageController.dispose();
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
    );
    await _dashboardCache.savePayroll(
      username: username,
      payroll: payroll,
    );
    return payroll;
  }

  void _setFutures({required bool forceNetwork}) {
    _clearClassesPageComputedCache();
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

  void _onPayrollPeriodChanged({
    int? month,
    int? year,
  }) {
    final nextMonth = month ?? _selectedPayrollMonth;
    final nextYear = year ?? _selectedPayrollYear;
    if (nextMonth == _selectedPayrollMonth &&
        nextYear == _selectedPayrollYear) {
      return;
    }
    final username = _session.username.trim().toLowerCase();
    setState(() {
      _selectedPayrollMonth = nextMonth;
      _selectedPayrollYear = nextYear;
      _payrollFuture = _loadPayroll(
        username: username,
        month: _selectedPayrollMonth,
        year: _selectedPayrollYear,
        forceNetwork: false,
      );
    });
  }

  Future<void> _showPullActionsSheet({required int tabIndex}) async {
    if (_isPullActionsSheetOpen || !mounted) {
      return;
    }

    _isPullActionsSheetOpen = true;
    _PullQuickAction? action;
    try {
      action = await showModalBottomSheet<_PullQuickAction>(
        context: context,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.22),
        builder: (sheetContext) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF0C2548),
                      Color(0xFF1A4D93),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x3D0A1B35),
                      blurRadius: 26,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tác vụ nhanh',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Vuốt xuống từ đầu trang để mở bảng này.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.84),
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final reloadAction = _PullActionButton(
                            icon: Icons.refresh_rounded,
                            title: 'Tải lại',
                            subtitle: tabIndex == 2
                                ? 'Làm mới thu nhập'
                                : 'Làm mới dữ liệu',
                            accent: const Color(0xFF2B8CFF),
                            onPressed: () => Navigator.of(sheetContext).pop(
                              _PullQuickAction.reload,
                            ),
                          );
                          final signOutAction = _PullActionButton(
                            icon: Icons.logout_rounded,
                            title: 'Đăng xuất',
                            subtitle: 'Thoát phiên hiện tại',
                            accent: const Color(0xFFFF6B57),
                            onPressed: () => Navigator.of(sheetContext).pop(
                              _PullQuickAction.signOut,
                            ),
                          );

                          if (constraints.maxWidth >= 460) {
                            return Row(
                              children: [
                                Expanded(child: reloadAction),
                                const SizedBox(width: 10),
                                Expanded(child: signOutAction),
                              ],
                            );
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              reloadAction,
                              const SizedBox(height: 10),
                              signOutAction,
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    } finally {
      _isPullActionsSheetOpen = false;
    }

    if (!mounted || action == null) {
      return;
    }

    switch (action) {
      case _PullQuickAction.reload:
        if (tabIndex == 2) {
          await _forceRefreshPayroll();
        } else {
          await _forceRefreshAll();
        }
        break;
      case _PullQuickAction.signOut:
        await widget.onSignOut();
        break;
    }
  }

  String _pullHintAccountScope() {
    final username = _session.username.trim().toLowerCase();
    if (username.isNotEmpty) {
      return username;
    }

    final email = _session.email.trim().toLowerCase();
    if (email.isNotEmpty) {
      return email;
    }
    return 'default';
  }

  String _pullHintHiddenKey() {
    return '$_pullHintHiddenPrefix.${_pullHintAccountScope()}';
  }

  Future<bool> _isPullHintHiddenForCurrentAccount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_pullHintHiddenKey()) ?? false;
  }

  Future<void> _setPullHintHiddenForCurrentAccount(bool hidden) async {
    final prefs = await SharedPreferences.getInstance();
    if (hidden) {
      await prefs.setBool(_pullHintHiddenKey(), true);
      return;
    }
    await prefs.remove(_pullHintHiddenKey());
  }

  Future<void> _maybeShowPullHintOnLogin() async {
    if (!mounted || _isShowingPullHint) {
      return;
    }

    final isHidden = await _isPullHintHiddenForCurrentAccount();
    if (!mounted || isHidden) {
      return;
    }

    _isShowingPullHint = true;
    bool doNotShowAgain = false;
    bool didTriggerPullSheet = false;
    double accumulatedDragDown = 0;

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (statefulContext, setDialogState) {
              return GestureDetector(
                onVerticalDragUpdate: (details) {
                  final deltaY = details.primaryDelta ?? details.delta.dy;
                  if (deltaY <= 0) {
                    return;
                  }
                  accumulatedDragDown += deltaY;
                  if (accumulatedDragDown < 40 || didTriggerPullSheet) {
                    return;
                  }
                  didTriggerPullSheet = true;
                  Navigator.of(dialogContext).pop();
                  unawaited(
                    Future<void>.delayed(
                      const Duration(milliseconds: 80),
                      () async {
                        if (!mounted) {
                          return;
                        }
                        await _showPullActionsSheet(tabIndex: _selectedIndex);
                      },
                    ),
                  );
                },
                onVerticalDragEnd: (_) {
                  accumulatedDragDown = 0;
                },
                child: AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                  title: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF1457B8),
                              Color(0xFF07A5A5),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: const Icon(
                          Icons.touch_app_rounded,
                          color: Colors.white,
                          size: 21,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Mẹo thao tác nhanh',
                          style: Theme.of(statefulContext)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                    ],
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bạn có thể kéo từ trên xuống ở bất kỳ tab nào để mở nhanh 2 tùy chọn: Tải lại hoặc Đăng xuất.',
                        style: Theme.of(statefulContext).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F8FF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.swipe_down_alt_rounded,
                              size: 18,
                              color: Colors.blue.shade700,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Kéo xuống để đóng bảng này và mở tác vụ nhanh',
                                style: Theme.of(statefulContext)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Colors.blue.shade700,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        value: doNotShowAgain,
                        onChanged: (value) {
                          setDialogState(() {
                            doNotShowAgain = value ?? false;
                          });
                        },
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(
                          'Không hiển thị lại',
                          style: Theme.of(statefulContext).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      _isShowingPullHint = false;
    }

    if (doNotShowAgain) {
      await _setPullHintHiddenForCurrentAccount(true);
    }
  }

  Future<void> _runPostLoginNotices() async {
    await _maybeShowPullHintOnLogin();
    await _maybeShowPendingCommentReminderOnLogin();
  }

  Future<void> _maybeShowPendingCommentReminderOnLogin() async {
    if (!mounted ||
        !widget.showPendingCommentReminderOnLogin ||
        _didCheckPendingCommentReminder ||
        _isShowingPendingCommentNotice) {
      return;
    }

    _didCheckPendingCommentReminder = true;

    List<ClassSummary> classes;
    try {
      classes = await _classesFuture.timeout(const Duration(seconds: 20));
    } catch (_) {
      return;
    }

    if (!mounted) {
      return;
    }

    final pendingClasses = classes
        .where(
          (cls) =>
              (cls.previousCommentContext?.missingCommentStudentCount ?? 0) > 0,
        )
        .toList()
      ..sort((a, b) {
        final aCount =
            a.previousCommentContext?.missingCommentStudentCount ?? 0;
        final bCount =
            b.previousCommentContext?.missingCommentStudentCount ?? 0;
        if (aCount != bCount) {
          return bCount.compareTo(aCount);
        }
        return a.className.compareTo(b.className);
      });

    if (pendingClasses.isEmpty) {
      return;
    }

    final totalMissingComments = pendingClasses.fold<int>(
      0,
      (sum, cls) =>
          sum + (cls.previousCommentContext?.missingCommentStudentCount ?? 0),
    );
    unawaited(
      LocalNotificationService.instance.showPendingCommentReminder(
        classCount: pendingClasses.length,
        missingCommentCount: totalMissingComments,
        classNames: pendingClasses.map((item) => item.className).toList(),
      ),
    );

    _isShowingPendingCommentNotice = true;
    bool shouldOpenClassTab = false;
    try {
      shouldOpenClassTab = await showDialog<bool>(
            context: context,
            barrierDismissible: true,
            builder: (dialogContext) {
              final topClasses = pendingClasses.take(4).toList(growable: false);
              final remaining = pendingClasses.length - topClasses.length;
              return AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                title: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3E8),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        Icons.notifications_active_rounded,
                        color: Colors.orange.shade800,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Nhắc nhận xét học viên',
                        style: Theme.of(dialogContext)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bạn có ${pendingClasses.length} lớp còn thiếu nhận xét tuần trước.',
                      style: Theme.of(dialogContext).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 10),
                    ...topClasses.map((cls) {
                      final commentContext = cls.previousCommentContext;
                      final count =
                          commentContext?.missingCommentStudentCount ?? 0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Icon(
                                Icons.circle,
                                size: 8,
                                color: Color(0xFF1F4D8F),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${cls.className}: thiếu $count nhận xét',
                                style: Theme.of(dialogContext)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    if (remaining > 0)
                      Text(
                        '...và thêm $remaining lớp khác.',
                        style: Theme.of(dialogContext)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: Colors.blueGrey.shade700,
                            ),
                      ),
                  ],
                ),
                actions: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('Để sau'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text('Xem lớp'),
                  ),
                ],
              );
            },
          ) ??
          false;
    } finally {
      _isShowingPendingCommentNotice = false;
    }

    if (!mounted || !shouldOpenClassTab) {
      return;
    }

    _onDestinationSelected(1);
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

  void _onPayrollInputChanged() {
    _payrollInputDebounce?.cancel();
    _payrollInputDebounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
  }

  void _clearClassesPageComputedCache() {
    _cachedClassesSource = null;
    _cachedRemindersSource = null;
    _cachedClassesPageComputed = null;
  }

  void _onDestinationSelected(int index) {
    if (index == _selectedIndex) {
      return;
    }

    setState(() {
      _selectedIndex = index;
    });

    if (!_pageController.hasClients) {
      return;
    }
    _pageController.animateToPage(
      index,
      duration: _tabSwitchDuration,
      curve: Curves.easeOutCubic,
    );
    if (index == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _tryRevealPendingClassCard();
      });
    }
  }

  void _onTabPageChanged(int index) {
    if (index == _selectedIndex) {
      return;
    }
    setState(() {
      _selectedIndex = index;
    });
    if (index == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _tryRevealPendingClassCard();
      });
    }
  }

  GlobalKey _classCardKeyFor(String classId) {
    return _classCardKeyByClassId.putIfAbsent(
      classId,
      () => GlobalKey(debugLabel: 'class_card_$classId'),
    );
  }

  void _scheduleRevealClassCard(String classId) {
    _pendingRevealClassId = classId;
    _pendingRevealAttempts = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryRevealPendingClassCard();
    });
  }

  void _tryRevealPendingClassCard() {
    if (!mounted || _selectedIndex != 1) {
      return;
    }

    final classId = _pendingRevealClassId;
    if (classId == null || classId.isEmpty) {
      return;
    }

    final key = _classCardKeyByClassId[classId];
    final cardContext = key?.currentContext;
    if (cardContext == null) {
      if (_pendingRevealAttempts >= 24) {
        _pendingRevealClassId = null;
        _pendingRevealAttempts = 0;
        return;
      }
      _pendingRevealAttempts += 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _tryRevealPendingClassCard();
      });
      return;
    }

    _pendingRevealClassId = null;
    _pendingRevealAttempts = 0;
    unawaited(
      Scrollable.ensureVisible(
        cardContext,
        alignment: 0.02,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _jumpToClassCommentFromOverview(ClassSummary cls) {
    final classId = cls.classId.trim();
    if (classId.isEmpty) {
      return;
    }

    final nextSlotId = cls.nextAttendanceWindow?.slotId ?? '';
    final previousSlotId = cls.previousCommentContext?.slotId ?? '';
    final studentNames = cls.students;

    setState(() {
      _classSectionByClassId[classId] = _ClassCardSection.note;
    });
    _scheduleRevealClassCard(classId);
    if (_selectedIndex != 1) {
      _onDestinationSelected(1);
    } else {
      _tryRevealPendingClassCard();
    }

    unawaited(
      _loadStudentCommentsForClass(
        classId: classId,
        slotId: nextSlotId,
        studentNames: studentNames,
      ),
    );
    unawaited(
      _loadPreviousStudentCommentsForClass(
        classId: classId,
        slotId: previousSlotId,
      ),
    );
  }

  _ClassParticipantsBundle _buildParticipantsForClass(ClassSummary cls) {
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
        .toList(growable: false);
    return _ClassParticipantsBundle(
      participants: List.unmodifiable(participants),
      studentNames: List.unmodifiable(studentNames),
    );
  }

  _ClassesPageComputed _computeClassesPageData({
    required List<ClassSummary> classesSource,
    required List<ReminderItem> remindersSource,
  }) {
    if (identical(_cachedClassesSource, classesSource) &&
        identical(_cachedRemindersSource, remindersSource) &&
        _cachedClassesPageComputed != null) {
      return _cachedClassesPageComputed!;
    }

    final classes = List<ClassSummary>.from(classesSource)
      ..sort((a, b) => a.className.compareTo(b.className));
    final remindersByClassId = <String, List<ReminderItem>>{};
    for (final reminder in remindersSource) {
      remindersByClassId.putIfAbsent(reminder.classId, () => []).add(reminder);
    }
    for (final classReminders in remindersByClassId.values) {
      classReminders.sort((a, b) {
        final startDiff =
            _sortTimeMs(a.slotStartTime) - _sortTimeMs(b.slotStartTime);
        if (startDiff != 0) {
          return startDiff;
        }
        final endDiff = _sortTimeMs(a.slotEndTime) - _sortTimeMs(b.slotEndTime);
        if (endDiff != 0) {
          return endDiff;
        }
        return a.className.compareTo(b.className);
      });
    }

    final nextReminderByClassId = <String, ReminderItem?>{};
    for (final cls in classes) {
      final classReminders = remindersByClassId[cls.classId];
      nextReminderByClassId[cls.classId] =
          (classReminders != null && classReminders.isNotEmpty)
              ? classReminders.first
              : null;
    }

    String? nextStartTimeForClass(ClassSummary cls) {
      final nextReminder = nextReminderByClassId[cls.classId];
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

    final participantsByClassId = <String, _ClassParticipantsBundle>{};
    for (final cls in classes) {
      participantsByClassId[cls.classId] = _buildParticipantsForClass(cls);
    }

    final computed = _ClassesPageComputed(
      classes: List.unmodifiable(classes),
      nextReminderByClassId: Map.unmodifiable(nextReminderByClassId),
      participantsByClassId: Map.unmodifiable(participantsByClassId),
    );
    _cachedClassesSource = classesSource;
    _cachedRemindersSource = remindersSource;
    _cachedClassesPageComputed = computed;
    return computed;
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
            'Chưa có slot sắp tới để lấy nhận xét.';
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
            'Không tải được nhận xét: $error';
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
              'Tuần trước còn $missingCount học viên chưa nhận xét.',
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
            'Không tải được nhận xét buổi trước: $error';
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
      return 'Tuần trước còn ${missingNames.length} học viên chưa nhận xét: ${missingNames.join(', ')}.';
    }

    final head = missingNames.take(3).join(', ');
    return 'Tuần trước còn ${missingNames.length} học viên chưa nhận xét: $head và ${missingNames.length - 3} học viên khác.';
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
          content: Text('Chưa có slot tuần trước để lưu nhận xét.'),
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
          ? 'Lưu nhận xét tuần trước cho ${draft.name} chưa thành công ($unresolved lỗi map).'
          : 'Đã lưu nhận xét tuần trước cho ${draft.name}.';
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
        SnackBar(content: Text('Lưu nhận xét tuần trước thất bại: $error')),
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
          content: Text('Chưa có slot sắp tới để lưu nhận xét.'),
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
          ? 'Lưu nhận xét cho ${draft.name} chưa thành công ($unresolved lỗi map).'
          : 'Đã lưu nhận xét cho ${draft.name} lên LMS.';
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
        SnackBar(content: Text('Lưu nhận xét thất bại: $error')),
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
          content: Text('Không tìm thấy slot sắp tới để lưu điểm danh.'),
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
          content: Text('Chưa có ai được chọn trạng thái để lưu điểm danh.'),
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
          ? 'Đã lưu $savedCount kết quả, còn $unresolvedCount người chưa map được.'
          : 'Đã lưu $savedCount kết quả điểm danh cho lớp này.';
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
          content: Text('Lưu điểm danh thất bại: $error'),
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
                  'Chúc bạn có một ngày tốt lành.',
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

  Widget _buildResponsiveFieldPair({
    required Widget first,
    required Widget second,
    double spacing = 10,
    double breakpoint = 560,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= breakpoint) {
          return Row(
            children: [
              Expanded(child: first),
              SizedBox(width: spacing),
              Expanded(child: second),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            first,
            SizedBox(height: spacing),
            second,
          ],
        );
      },
    );
  }

  Widget _buildOverviewPage() {
    return RefreshIndicator(
      onRefresh: () => _showPullActionsSheet(tabIndex: 0),
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
            title: 'Lớp chưa nhận xét',
            subtitle: 'Các lớp còn học viên chưa nhận xét tuần trước',
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
                    message: 'Không có lớp nào chưa nhận xét tuần trước.',
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
                        ? 'Còn $missingCount học viên chưa nhận xét.'
                        : moreCount > 0
                            ? 'Còn $missingCount học viên: $preview và $moreCount học viên khác.'
                            : 'Còn $missingCount học viên: $preview.';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.blueGrey.shade100),
                      ),
                      child: ListTile(
                        onTap: () => _jumpToClassCommentFromOverview(cls),
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
      onRefresh: () => _showPullActionsSheet(tabIndex: 1),
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
          final classesSource =
              payload.isNotEmpty && payload.first is List<ClassSummary>
                  ? payload.first as List<ClassSummary>
                  : const <ClassSummary>[];
          final remindersSource =
              payload.length > 1 && payload[1] is List<ReminderItem>
                  ? payload[1] as List<ReminderItem>
                  : const <ReminderItem>[];

          if (classesSource.isEmpty) {
            return const _EmptyView(message: 'Không có lớp đang hoạt động.');
          }

          final computed = _computeClassesPageData(
            classesSource: classesSource,
            remindersSource: remindersSource,
          );
          final classes = computed.classes;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _tryRevealPendingClassCard();
          });

          return ListView.separated(
            key: const PageStorageKey<String>('classes_list_view'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            itemCount: classes.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final cls = classes[index];
              final nextReminder = computed.nextReminderByClassId[cls.classId];
              final roleLabel = nextReminder != null
                  ? (nextReminder.roleShortName ??
                      nextReminder.roleName ??
                      'Chưa rõ vai trò')
                  : 'Chưa rõ vai trò';
              final participantBundle =
                  computed.participantsByClassId[cls.classId] ??
                      _buildParticipantsForClass(cls);
              final participants = participantBundle.participants;
              final studentNames = participantBundle.studentNames;

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
                  ? 'Học viên chưa nhận xét (buổi ${cls.previousCommentContext!.sessionNumber})'
                  : 'Học viên chưa nhận xét (tuần trước)';
              final classStartLabel = _formatDateTime(cls.classStartDate);
              final classEndLabel = _formatDateTime(cls.classEndDate);
              final isAttendanceWindowOpen = nextReminder?.isWindowOpen ??
                  cls.nextAttendanceWindow?.isWindowOpen ??
                  false;
              final attendanceRemainingLabel = isAttendanceWindowOpen
                  ? 'Còn ${_formatDurationMinutesVi(nextReminder?.minutesUntilWindowClose ?? cls.nextAttendanceWindow?.minutesUntilWindowClose ?? 0, compact: true)} để điểm danh'
                  : (nextClassStartTime != null &&
                          nextClassStartTime.trim().isNotEmpty
                      ? 'Còn ${_formatDayHourMinuteCountdown(nextClassStartTime)} đến buổi học tiếp theo'
                      : 'Chưa có buổi học tiếp theo');

              return Card(
                key: _classCardKeyFor(cls.classId),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final titleWidget = Text(
                            cls.className,
                            style: Theme.of(context).textTheme.titleMedium,
                          );
                          final countdownWidget = _Pill(
                            label: countdownBadge,
                            background: const Color(0xFFE3EEFF),
                            foreground: const Color(0xFF154EA3),
                            icon: Icons.schedule_rounded,
                          );

                          if (constraints.maxWidth < 420) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                titleWidget,
                                const SizedBox(height: 8),
                                countdownWidget,
                              ],
                            );
                          }

                          return Row(
                            children: [
                              Expanded(child: titleWidget),
                              const SizedBox(width: 8),
                              countdownWidget,
                            ],
                          );
                        },
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
                          if (previousMissingCount > 0)
                            _MiniStat(
                              icon: Icons.warning_amber_rounded,
                              label:
                                  '$previousMissingCount học viên chưa nhận xét tuần trước',
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
                                label: 'Chi tiết',
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
                                label: 'Điểm danh',
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
                                label: 'Nhận xét',
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
                                'Thông tin lớp học',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(
                                      color: const Color(0xFF1C4ED8),
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                              const SizedBox(height: 6),
                              Text('Số lượng học viên: ${cls.totalStudents}'),
                              const SizedBox(height: 4),
                              Text('Vai trò của bạn: $roleLabel'),
                              const SizedBox(height: 8),
                              Text('Bắt đầu khóa học: $classStartLabel'),
                              const SizedBox(height: 4),
                              Text('Kết thúc khóa học: $classEndLabel'),
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
                                  'Buổi sắp tới: ${_formatDateTime(nextReminder.slotStartTime)} - '
                                  '${_formatDateTime(nextReminder.slotEndTime)}',
                                ),
                                const SizedBox(height: 4),
                                Text('Buổi ${nextReminder.slotIndex ?? '-'}'),
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
                                'Điểm danh (${participants.length})',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Có $presentCount · Trễ $lateCount · Có phép $excusedCount · Không phép $unexcusedCount',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 8),
                              if (participants.isEmpty)
                                const Text(
                                  'Chưa có học viên/đồng giáo viên để điểm danh.',
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
                                          ? 'Đang lưu điểm danh...'
                                          : 'Lưu kết quả điểm danh',
                                    ),
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
                                previousCommentHeader,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 8),
                              if (previousSlotId.isEmpty)
                                const _EmptyLabel(
                                  message:
                                      'Chưa có dữ liệu tuần trước để kiểm tra nhận xét.',
                                )
                              else if (isLoadingPreviousComments)
                                const _InlineLoading()
                              else if (previousCommentsError != null)
                                _ErrorLabel(message: previousCommentsError)
                              else if (previousCommentDrafts.isEmpty)
                                const _EmptyLabel(
                                  message:
                                      'Tuần trước tất cả học viên đã có nhận xét.',
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
                                                'Nhập nhận xét cho học viên tuần trước',
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
                                                  ? 'Đang lưu...'
                                                  : 'Lưu nhận xét tuần trước',
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
                                'Nhận xét từng học viên',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 8),
                              if (saveSlotId.isEmpty)
                                const _EmptyLabel(
                                  message: 'Chưa có slot sắp tới để nhận xét.',
                                )
                              else if (isLoadingComments)
                                const _InlineLoading()
                              else if (commentsError != null)
                                _ErrorLabel(message: commentsError)
                              else if (commentDrafts.isEmpty)
                                const _EmptyLabel(
                                  message:
                                      'Chưa có học viên để nhận xét cho slot này.',
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
                                                'Nhập nhận xét cho học viên này',
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
                                                  ? 'Đang lưu...'
                                                  : 'Lưu nhận xét học viên này',
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
      onRefresh: () => _showPullActionsSheet(tabIndex: 2),
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
            key: const PageStorageKey<String>('payroll_list_view'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              _SectionCard(
                title: 'Bộ lọc kỳ lương',
                child: Column(
                  children: [
                    _buildResponsiveFieldPair(
                      first: DropdownButtonFormField<int>(
                        initialValue: _selectedPayrollMonth,
                        decoration: const InputDecoration(labelText: 'Thang'),
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
                          _onPayrollPeriodChanged(month: value);
                        },
                      ),
                      second: DropdownButtonFormField<int>(
                        initialValue: _selectedPayrollYear,
                        decoration: const InputDecoration(labelText: 'Nam'),
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
                          _onPayrollPeriodChanged(year: value);
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildResponsiveFieldPair(
                      first: TextField(
                        controller: _hourlyRateController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Luong theo gio (VND)',
                          hintText: 'Vi du: 150000',
                        ),
                        onChanged: (_) => _onPayrollInputChanged(),
                      ),
                      second: TextField(
                        controller: _manualAdjustmentController,
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Cong bu / dieu chinh',
                          hintText: 'Vi du: 300000 hoac -200000',
                        ),
                        onChanged: (_) => _onPayrollInputChanged(),
                      ),
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
                              '${moneySummary.actualSlots} buổi (${moneySummary.actualHours.toStringAsFixed(2)}h)',
                        ),
                        _MiniStat(
                          icon: Icons.auto_graph_rounded,
                          label:
                              '${moneySummary.projectedSlots} buổi dự kiến (${moneySummary.projectedHours.toStringAsFixed(2)}h)',
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
                          trailing: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 120),
                            child: Text(
                              _formatMoney(
                                _calculateOfficeHourIncome(
                                    officeHour, hourlyRate),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: Colors.green.shade700,
                                    fontWeight: FontWeight.w800,
                                  ),
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
                          key: PageStorageKey<String>(
                            'payroll_class_tile_${cls.classId}',
                          ),
                          tilePadding:
                              const EdgeInsets.symmetric(horizontal: 12),
                          childrenPadding:
                              const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          title: Text(cls.className),
                          subtitle: Text(
                            '${cls.taughtSlotCount} slots · ${cls.totalHours}h',
                          ),
                          trailing: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 120),
                            child: Text(
                              _formatMoney(classIncome),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    color: Colors.green.shade700,
                                    fontWeight: FontWeight.w800,
                                  ),
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

  Widget _buildTabPage(int index) {
    switch (index) {
      case 0:
        return _buildOverviewPage();
      case 1:
        return _buildClassesPage();
      case 2:
        return _buildPayrollPage();
      default:
        return _buildOverviewPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['Tổng quan', 'Lớp học', 'Thu nhập'];
    final safeIndex = _selectedIndex.clamp(0, titles.length - 1);
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[safeIndex]),
      ),
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: _onTabPageChanged,
        itemCount: titles.length,
        itemBuilder: (context, index) {
          return RepaintBoundary(
            key: PageStorageKey<String>('home_tab_page_$index'),
            child: _buildTabPage(index),
          );
        },
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
          onDestinationSelected: _onDestinationSelected,
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
    final constraints = wide
        ? const BoxConstraints(
            minWidth: 180,
            maxWidth: 420,
            minHeight: 116,
          )
        : const BoxConstraints(
            minWidth: 130,
            maxWidth: 260,
            minHeight: 116,
          );

    return ConstrainedBox(
      constraints: constraints,
      child: Container(
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: const Color(0xFF2958C7)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: foreground),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          ],
        ),
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

class _PullActionButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onPressed;

  const _PullActionButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.22),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 18, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.82),
                            fontWeight: FontWeight.w600,
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

class _ClassParticipantsBundle {
  final List<_AttendanceParticipant> participants;
  final List<String> studentNames;

  const _ClassParticipantsBundle({
    required this.participants,
    required this.studentNames,
  });
}

class _ClassesPageComputed {
  final List<ClassSummary> classes;
  final Map<String, ReminderItem?> nextReminderByClassId;
  final Map<String, _ClassParticipantsBundle> participantsByClassId;

  const _ClassesPageComputed({
    required this.classes,
    required this.nextReminderByClassId,
    required this.participantsByClassId,
  });
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

enum _PullQuickAction {
  reload,
  signOut,
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
