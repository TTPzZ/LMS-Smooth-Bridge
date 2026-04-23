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

  Map<String, dynamic> toJson() {
    return {
      'slotId': slotId,
      'slotIndex': slotIndex,
      'slotDate': slotDate,
      'slotStartTime': slotStartTime,
      'slotEndTime': slotEndTime,
      'attendanceOpenAt': attendanceOpenAt,
      'attendanceCloseAt': attendanceCloseAt,
      'isWindowOpen': isWindowOpen,
      'minutesUntilWindowOpen': minutesUntilWindowOpen,
      'minutesUntilWindowClose': minutesUntilWindowClose,
      'totalStudentsInSlot': totalStudentsInSlot,
    };
  }
}

class ClassSummary {
  final String classId;
  final String className;
  final String? status;
  final String? classEndDate;
  final bool isClassEnded;
  final int totalStudents;
  final List<String> students;
  final int totalSlots;
  final AttendanceWindow? nextAttendanceWindow;

  ClassSummary({
    required this.classId,
    required this.className,
    required this.status,
    required this.classEndDate,
    required this.isClassEnded,
    required this.totalStudents,
    required this.students,
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
      students: _asStringList(json['students']),
      totalSlots: _asInt(json['totalSlots']),
      nextAttendanceWindow: (next is Map<String, dynamic>)
          ? AttendanceWindow.fromJson(next)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'classId': classId,
      'className': className,
      'status': status,
      'classEndDate': classEndDate,
      'isClassEnded': isClassEnded,
      'totalStudents': totalStudents,
      'students': students,
      'totalSlots': totalSlots,
      'nextAttendanceWindow': nextAttendanceWindow?.toJson(),
    };
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

  Map<String, dynamic> toJson() {
    return {
      'classId': classId,
      'className': className,
      'classStatus': classStatus,
      'classEndDate': classEndDate,
      'slotId': slotId,
      'slotIndex': slotIndex,
      'slotStartTime': slotStartTime,
      'slotEndTime': slotEndTime,
      'attendanceOpenAt': attendanceOpenAt,
      'attendanceCloseAt': attendanceCloseAt,
      'isWindowOpen': isWindowOpen,
      'minutesUntilWindowOpen': minutesUntilWindowOpen,
      'minutesUntilWindowClose': minutesUntilWindowClose,
      'totalStudentsInSlot': totalStudentsInSlot,
    };
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

  Map<String, dynamic> toJson() {
    return {
      'role': role,
      'slotCount': slotCount,
      'classCount': classCount,
      'totalHours': totalHours,
    };
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

  Map<String, dynamic> toJson() {
    return {
      'classId': classId,
      'className': className,
      'slotId': slotId,
      'slotIndex': slotIndex,
      'startTime': startTime,
      'endTime': endTime,
      'attendanceStatus': attendanceStatus,
      'roleName': roleName,
      'roleShortName': roleShortName,
      'durationHours': durationHours,
    };
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

  Map<String, dynamic> toJson() {
    return {
      'classId': classId,
      'className': className,
      'taughtSlotCount': taughtSlotCount,
      'totalHours': totalHours,
      'roles': roles,
      'slots': slots.map((item) => item.toJson()).toList(),
    };
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

  Map<String, dynamic> toJson() {
    return {
      'totalTaughtSlots': totalTaughtSlots,
      'totalClasses': totalClasses,
      'totalHours': totalHours,
      'byRole': byRole.map((item) => item.toJson()).toList(),
    };
  }
}

class PayrollProjection {
  final int totalAssignedSlots;
  final double totalAssignedHours;
  final List<PayrollRoleSummary> byRole;

  PayrollProjection({
    required this.totalAssignedSlots,
    required this.totalAssignedHours,
    required this.byRole,
  });

  factory PayrollProjection.fromJson(Map<String, dynamic> json) {
    return PayrollProjection(
      totalAssignedSlots: _asInt(json['totalAssignedSlots']),
      totalAssignedHours: _asDouble(json['totalAssignedHours']),
      byRole:
          _asMapList(json['byRole']).map(PayrollRoleSummary.fromJson).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'totalAssignedSlots': totalAssignedSlots,
      'totalAssignedHours': totalAssignedHours,
      'byRole': byRole.map((item) => item.toJson()).toList(),
    };
  }
}

class PayrollOfficeHour {
  final String timesheetId;
  final String? officeHourId;
  final String startTime;
  final String? endTime;
  final String status;
  final String? officeHourType;
  final int studentCount;
  final double durationHours;
  final String? note;
  final String? managerNote;
  final String? shortName;

  PayrollOfficeHour({
    required this.timesheetId,
    required this.officeHourId,
    required this.startTime,
    required this.endTime,
    required this.status,
    required this.officeHourType,
    required this.studentCount,
    required this.durationHours,
    required this.note,
    required this.managerNote,
    required this.shortName,
  });

  factory PayrollOfficeHour.fromJson(Map<String, dynamic> json) {
    return PayrollOfficeHour(
      timesheetId: (json['timesheetId'] ?? '').toString(),
      officeHourId: json['officeHourId']?.toString(),
      startTime: (json['startTime'] ?? '').toString(),
      endTime: json['endTime']?.toString(),
      status: (json['status'] ?? '').toString(),
      officeHourType: json['officeHourType']?.toString(),
      studentCount: _asInt(json['studentCount']),
      durationHours: _asDouble(json['durationHours']),
      note: json['note']?.toString(),
      managerNote: json['managerNote']?.toString(),
      shortName: json['shortName']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'timesheetId': timesheetId,
      'officeHourId': officeHourId,
      'startTime': startTime,
      'endTime': endTime,
      'status': status,
      'officeHourType': officeHourType,
      'studentCount': studentCount,
      'durationHours': durationHours,
      'note': note,
      'managerNote': managerNote,
      'shortName': shortName,
    };
  }
}

class PayrollResponse {
  final int month;
  final int year;
  final String timezone;
  final PayrollSummary summary;
  final PayrollProjection? projection;
  final List<PayrollOfficeHour> officeHours;
  final List<PayrollClass> classes;

  PayrollResponse({
    required this.month,
    required this.year,
    required this.timezone,
    required this.summary,
    required this.projection,
    required this.officeHours,
    required this.classes,
  });

  factory PayrollResponse.fromJson(Map<String, dynamic> json) {
    final projectionRaw = json['projection'];
    return PayrollResponse(
      month: _asInt(json['month']),
      year: _asInt(json['year']),
      timezone: (json['timezone'] ?? '').toString(),
      summary: PayrollSummary.fromJson(
          (json['summary'] as Map<String, dynamic>?) ?? const {}),
      projection: (projectionRaw is Map)
          ? PayrollProjection.fromJson(
              projectionRaw
                  .map((key, value) => MapEntry(key.toString(), value)),
            )
          : null,
      officeHours: _asMapList(
        json['officeHours'],
      ).map(PayrollOfficeHour.fromJson).toList(),
      classes: _asMapList(json['classes']).map(PayrollClass.fromJson).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'month': month,
      'year': year,
      'timezone': timezone,
      'summary': summary.toJson(),
      'projection': projection?.toJson(),
      'officeHours': officeHours.map((item) => item.toJson()).toList(),
      'classes': classes.map((item) => item.toJson()).toList(),
    };
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
