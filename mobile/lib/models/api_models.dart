class AttendanceWindow {
  final String slotId;
  final int? slotIndex;
  final String? slotDate;
  final String slotStartTime;
  final String slotEndTime;
  final String attendanceOpenAt;
  final String attendanceCloseAt;
  final bool isWindowOpen;
  final int minutesUntilWindowOpen;
  final int minutesUntilWindowClose;
  final int totalStudentsInSlot;

  AttendanceWindow({
    required this.slotId,
    required this.slotIndex,
    required this.slotDate,
    required this.slotStartTime,
    required this.slotEndTime,
    required this.attendanceOpenAt,
    required this.attendanceCloseAt,
    required this.isWindowOpen,
    required this.minutesUntilWindowOpen,
    required this.minutesUntilWindowClose,
    required this.totalStudentsInSlot,
  });

  factory AttendanceWindow.fromJson(Map<String, dynamic> json) {
    return AttendanceWindow(
      slotId: (json['slotId'] ?? '').toString(),
      slotIndex: (json['slotIndex'] is int) ? json['slotIndex'] as int : null,
      slotDate: json['slotDate']?.toString(),
      slotStartTime: (json['slotStartTime'] ?? '').toString(),
      slotEndTime: (json['slotEndTime'] ?? '').toString(),
      attendanceOpenAt: (json['attendanceOpenAt'] ?? '').toString(),
      attendanceCloseAt: (json['attendanceCloseAt'] ?? '').toString(),
      isWindowOpen: json['isWindowOpen'] == true,
      minutesUntilWindowOpen: _asInt(json['minutesUntilWindowOpen']),
      minutesUntilWindowClose: _asInt(json['minutesUntilWindowClose']),
      totalStudentsInSlot: _asInt(json['totalStudentsInSlot']),
    );
  }
}

class ClassSummary {
  final String classId;
  final String className;
  final String? status;
  final String? classEndDate;
  final bool isClassEnded;
  final int totalStudents;
  final int totalSlots;
  final AttendanceWindow? nextAttendanceWindow;

  ClassSummary({
    required this.classId,
    required this.className,
    required this.status,
    required this.classEndDate,
    required this.isClassEnded,
    required this.totalStudents,
    required this.totalSlots,
    required this.nextAttendanceWindow,
  });

  factory ClassSummary.fromJson(Map<String, dynamic> json) {
    final next = json['nextAttendanceWindow'];
    return ClassSummary(
      classId: (json['classId'] ?? '').toString(),
      className: (json['className'] ?? '').toString(),
      status: json['status']?.toString(),
      classEndDate: json['classEndDate']?.toString(),
      isClassEnded: json['isClassEnded'] == true,
      totalStudents: _asInt(json['totalStudents']),
      totalSlots: _asInt(json['totalSlots']),
      nextAttendanceWindow: (next is Map<String, dynamic>)
          ? AttendanceWindow.fromJson(next)
          : null,
    );
  }
}

class ReminderItem {
  final String classId;
  final String className;
  final String? classStatus;
  final String? classEndDate;
  final String slotId;
  final int? slotIndex;
  final String slotStartTime;
  final String slotEndTime;
  final String attendanceOpenAt;
  final String attendanceCloseAt;
  final bool isWindowOpen;
  final int minutesUntilWindowOpen;
  final int minutesUntilWindowClose;
  final int totalStudentsInSlot;

  ReminderItem({
    required this.classId,
    required this.className,
    required this.classStatus,
    required this.classEndDate,
    required this.slotId,
    required this.slotIndex,
    required this.slotStartTime,
    required this.slotEndTime,
    required this.attendanceOpenAt,
    required this.attendanceCloseAt,
    required this.isWindowOpen,
    required this.minutesUntilWindowOpen,
    required this.minutesUntilWindowClose,
    required this.totalStudentsInSlot,
  });

  factory ReminderItem.fromJson(Map<String, dynamic> json) {
    return ReminderItem(
      classId: (json['classId'] ?? '').toString(),
      className: (json['className'] ?? '').toString(),
      classStatus: json['classStatus']?.toString(),
      classEndDate: json['classEndDate']?.toString(),
      slotId: (json['slotId'] ?? '').toString(),
      slotIndex: (json['slotIndex'] is int) ? json['slotIndex'] as int : null,
      slotStartTime: (json['slotStartTime'] ?? '').toString(),
      slotEndTime: (json['slotEndTime'] ?? '').toString(),
      attendanceOpenAt: (json['attendanceOpenAt'] ?? '').toString(),
      attendanceCloseAt: (json['attendanceCloseAt'] ?? '').toString(),
      isWindowOpen: json['isWindowOpen'] == true,
      minutesUntilWindowOpen: _asInt(json['minutesUntilWindowOpen']),
      minutesUntilWindowClose: _asInt(json['minutesUntilWindowClose']),
      totalStudentsInSlot: _asInt(json['totalStudentsInSlot']),
    );
  }
}

class PayrollRoleSummary {
  final String role;
  final int slotCount;
  final int classCount;
  final double totalHours;

  PayrollRoleSummary({
    required this.role,
    required this.slotCount,
    required this.classCount,
    required this.totalHours,
  });

  factory PayrollRoleSummary.fromJson(Map<String, dynamic> json) {
    return PayrollRoleSummary(
      role: (json['role'] ?? 'UNKNOWN').toString(),
      slotCount: _asInt(json['slotCount']),
      classCount: _asInt(json['classCount']),
      totalHours: _asDouble(json['totalHours']),
    );
  }
}

class PayrollSlot {
  final String classId;
  final String className;
  final String slotId;
  final int? slotIndex;
  final String startTime;
  final String? endTime;
  final String attendanceStatus;
  final String? roleName;
  final String? roleShortName;
  final double durationHours;

  PayrollSlot({
    required this.classId,
    required this.className,
    required this.slotId,
    required this.slotIndex,
    required this.startTime,
    required this.endTime,
    required this.attendanceStatus,
    required this.roleName,
    required this.roleShortName,
    required this.durationHours,
  });

  factory PayrollSlot.fromJson(Map<String, dynamic> json) {
    return PayrollSlot(
      classId: (json['classId'] ?? '').toString(),
      className: (json['className'] ?? '').toString(),
      slotId: (json['slotId'] ?? '').toString(),
      slotIndex: (json['slotIndex'] is int) ? json['slotIndex'] as int : null,
      startTime: (json['startTime'] ?? '').toString(),
      endTime: json['endTime']?.toString(),
      attendanceStatus: (json['attendanceStatus'] ?? '').toString(),
      roleName: json['roleName']?.toString(),
      roleShortName: json['roleShortName']?.toString(),
      durationHours: _asDouble(json['durationHours']),
    );
  }
}

class PayrollClass {
  final String classId;
  final String className;
  final int taughtSlotCount;
  final double totalHours;
  final List<String> roles;
  final List<PayrollSlot> slots;

  PayrollClass({
    required this.classId,
    required this.className,
    required this.taughtSlotCount,
    required this.totalHours,
    required this.roles,
    required this.slots,
  });

  factory PayrollClass.fromJson(Map<String, dynamic> json) {
    return PayrollClass(
      classId: (json['classId'] ?? '').toString(),
      className: (json['className'] ?? '').toString(),
      taughtSlotCount: _asInt(json['taughtSlotCount']),
      totalHours: _asDouble(json['totalHours']),
      roles: _asStringList(json['roles']),
      slots: _asMapList(json['slots']).map(PayrollSlot.fromJson).toList(),
    );
  }
}

class PayrollSummary {
  final int totalTaughtSlots;
  final int totalClasses;
  final double totalHours;
  final List<PayrollRoleSummary> byRole;

  PayrollSummary({
    required this.totalTaughtSlots,
    required this.totalClasses,
    required this.totalHours,
    required this.byRole,
  });

  factory PayrollSummary.fromJson(Map<String, dynamic> json) {
    return PayrollSummary(
      totalTaughtSlots: _asInt(json['totalTaughtSlots']),
      totalClasses: _asInt(json['totalClasses']),
      totalHours: _asDouble(json['totalHours']),
      byRole:
          _asMapList(json['byRole']).map(PayrollRoleSummary.fromJson).toList(),
    );
  }
}

class PayrollResponse {
  final int month;
  final int year;
  final String timezone;
  final PayrollSummary summary;
  final List<PayrollClass> classes;

  PayrollResponse({
    required this.month,
    required this.year,
    required this.timezone,
    required this.summary,
    required this.classes,
  });

  factory PayrollResponse.fromJson(Map<String, dynamic> json) {
    return PayrollResponse(
      month: _asInt(json['month']),
      year: _asInt(json['year']),
      timezone: (json['timezone'] ?? '').toString(),
      summary: PayrollSummary.fromJson(
          (json['summary'] as Map<String, dynamic>?) ?? const {}),
      classes: _asMapList(json['classes']).map(PayrollClass.fromJson).toList(),
    );
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is double) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _asDouble(dynamic value) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

List<Map<String, dynamic>> _asMapList(dynamic value) {
  if (value is List) {
    return value
        .whereType<Map>()
        .map((item) => item.map((key, v) => MapEntry(key.toString(), v)))
        .toList();
  }
  return const [];
}

List<String> _asStringList(dynamic value) {
  if (value is List) {
    return value.map((item) => item.toString()).toList();
  }
  return const [];
}
