class AttendanceWindow {
  final String slotId;
  final int? slotIndex;
  final String? slotDate;
  final String? roleName;
  final String? roleShortName;
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
    required this.roleName,
    required this.roleShortName,
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
      roleName: json['roleName']?.toString(),
      roleShortName: json['roleShortName']?.toString(),
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
      'roleName': roleName,
      'roleShortName': roleShortName,
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
  final String? classStartDate;
  final String? classEndDate;
  final bool isClassEnded;
  final int totalStudents;
  final List<String> students;
  final List<String> coTeachers;
  final int totalSlots;
  final AttendanceWindow? nextAttendanceWindow;
  final ClassCommentContext? nextCommentContext;
  final ClassCommentContext? previousCommentContext;

  ClassSummary({
    required this.classId,
    required this.className,
    required this.status,
    required this.classStartDate,
    required this.classEndDate,
    required this.isClassEnded,
    required this.totalStudents,
    required this.students,
    required this.coTeachers,
    required this.totalSlots,
    required this.nextAttendanceWindow,
    required this.nextCommentContext,
    required this.previousCommentContext,
  });

  factory ClassSummary.fromJson(Map<String, dynamic> json) {
    final next = json['nextAttendanceWindow'];
    final nextComment = json['nextCommentContext'];
    final previousComment = json['previousCommentContext'];
    return ClassSummary(
      classId: (json['classId'] ?? '').toString(),
      className: (json['className'] ?? '').toString(),
      status: json['status']?.toString(),
      classStartDate: json['classStartDate']?.toString(),
      classEndDate: json['classEndDate']?.toString(),
      isClassEnded: json['isClassEnded'] == true,
      totalStudents: _asInt(json['totalStudents']),
      students: _asStringList(json['students']),
      coTeachers: _asStringList(json['coTeachers']),
      totalSlots: _asInt(json['totalSlots']),
      nextAttendanceWindow: (next is Map<String, dynamic>)
          ? AttendanceWindow.fromJson(next)
          : null,
      nextCommentContext: (nextComment is Map<String, dynamic>)
          ? ClassCommentContext.fromJson(nextComment)
          : null,
      previousCommentContext: (previousComment is Map<String, dynamic>)
          ? ClassCommentContext.fromJson(previousComment)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'classId': classId,
      'className': className,
      'status': status,
      'classStartDate': classStartDate,
      'classEndDate': classEndDate,
      'isClassEnded': isClassEnded,
      'totalStudents': totalStudents,
      'students': students,
      'coTeachers': coTeachers,
      'totalSlots': totalSlots,
      'nextAttendanceWindow': nextAttendanceWindow?.toJson(),
      'nextCommentContext': nextCommentContext?.toJson(),
      'previousCommentContext': previousCommentContext?.toJson(),
    };
  }
}

class ClassCommentContext {
  final String? slotId;
  final int? sessionNumber;
  final String? slotStartTime;
  final String? slotEndTime;
  final int missingCommentStudentCount;
  final List<String> missingCommentStudents;

  ClassCommentContext({
    required this.slotId,
    required this.sessionNumber,
    required this.slotStartTime,
    required this.slotEndTime,
    required this.missingCommentStudentCount,
    required this.missingCommentStudents,
  });

  factory ClassCommentContext.fromJson(Map<String, dynamic> json) {
    return ClassCommentContext(
      slotId: json['slotId']?.toString(),
      sessionNumber:
          (json['sessionNumber'] is int) ? json['sessionNumber'] as int : null,
      slotStartTime: json['slotStartTime']?.toString(),
      slotEndTime: json['slotEndTime']?.toString(),
      missingCommentStudentCount: _asInt(json['missingCommentStudentCount']),
      missingCommentStudents: _asStringList(json['missingCommentStudents']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'slotId': slotId,
      'sessionNumber': sessionNumber,
      'slotStartTime': slotStartTime,
      'slotEndTime': slotEndTime,
      'missingCommentStudentCount': missingCommentStudentCount,
      'missingCommentStudents': missingCommentStudents,
    };
  }
}

class ReminderItem {
  final String classId;
  final String className;
  final String? classStatus;
  final String? classEndDate;
  final String? roleName;
  final String? roleShortName;
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
    required this.roleName,
    required this.roleShortName,
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
      roleName: json['roleName']?.toString(),
      roleShortName: json['roleShortName']?.toString(),
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
      'roleName': roleName,
      'roleShortName': roleShortName,
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

class AttendanceSaveParticipant {
  final String key;
  final String name;
  final bool isCoTeacher;
  final String status;

  AttendanceSaveParticipant({
    required this.key,
    required this.name,
    required this.isCoTeacher,
    required this.status,
  });

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'name': name,
      'isCoTeacher': isCoTeacher,
      'status': status,
    };
  }
}

class AttendanceUnresolvedParticipant {
  final String key;
  final String name;
  final bool isCoTeacher;
  final String reason;

  AttendanceUnresolvedParticipant({
    required this.key,
    required this.name,
    required this.isCoTeacher,
    required this.reason,
  });

  factory AttendanceUnresolvedParticipant.fromJson(
    Map<String, dynamic> json,
  ) {
    return AttendanceUnresolvedParticipant(
      key: (json['key'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      isCoTeacher: _asBool(json['isCoTeacher']),
      reason: (json['reason'] ?? '').toString(),
    );
  }
}

class AttendanceSaveResult {
  final String classId;
  final String slotId;
  final int requestedParticipants;
  final int appliedParticipants;
  final int updatedStudents;
  final int updatedTeachers;
  final List<String> appliedParticipantKeys;
  final List<AttendanceUnresolvedParticipant> unresolvedParticipants;

  AttendanceSaveResult({
    required this.classId,
    required this.slotId,
    required this.requestedParticipants,
    required this.appliedParticipants,
    required this.updatedStudents,
    required this.updatedTeachers,
    required this.appliedParticipantKeys,
    required this.unresolvedParticipants,
  });

  factory AttendanceSaveResult.fromJson(Map<String, dynamic> json) {
    return AttendanceSaveResult(
      classId: (json['classId'] ?? '').toString(),
      slotId: (json['slotId'] ?? '').toString(),
      requestedParticipants: _asInt(json['requestedParticipants']),
      appliedParticipants: _asInt(json['appliedParticipants']),
      updatedStudents: _asInt(json['updatedStudents']),
      updatedTeachers: _asInt(json['updatedTeachers']),
      appliedParticipantKeys: _asStringList(json['appliedParticipantKeys']),
      unresolvedParticipants: _asMapList(
        json['unresolvedParticipants'],
      ).map(AttendanceUnresolvedParticipant.fromJson).toList(),
    );
  }
}

class AttendanceCommentItem {
  final String key;
  final String name;
  final String? studentId;
  final String comment;

  AttendanceCommentItem({
    required this.key,
    required this.name,
    required this.studentId,
    required this.comment,
  });

  factory AttendanceCommentItem.fromJson(Map<String, dynamic> json) {
    return AttendanceCommentItem(
      key: (json['key'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      studentId: json['studentId']?.toString(),
      comment: (json['comment'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'name': name,
      'studentId': studentId,
      'comment': comment,
    };
  }
}

class AttendanceCommentUnresolvedParticipant {
  final String key;
  final String name;
  final String reason;

  AttendanceCommentUnresolvedParticipant({
    required this.key,
    required this.name,
    required this.reason,
  });

  factory AttendanceCommentUnresolvedParticipant.fromJson(
    Map<String, dynamic> json,
  ) {
    return AttendanceCommentUnresolvedParticipant(
      key: (json['key'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      reason: (json['reason'] ?? '').toString(),
    );
  }
}

class AttendanceCommentSaveResult {
  final String classId;
  final String slotId;
  final int requestedComments;
  final int appliedComments;
  final int updatedStudents;
  final List<String> appliedParticipantKeys;
  final List<AttendanceCommentUnresolvedParticipant> unresolvedParticipants;

  AttendanceCommentSaveResult({
    required this.classId,
    required this.slotId,
    required this.requestedComments,
    required this.appliedComments,
    required this.updatedStudents,
    required this.appliedParticipantKeys,
    required this.unresolvedParticipants,
  });

  factory AttendanceCommentSaveResult.fromJson(Map<String, dynamic> json) {
    return AttendanceCommentSaveResult(
      classId: (json['classId'] ?? '').toString(),
      slotId: (json['slotId'] ?? '').toString(),
      requestedComments: _asInt(json['requestedComments']),
      appliedComments: _asInt(json['appliedComments']),
      updatedStudents: _asInt(json['updatedStudents']),
      appliedParticipantKeys: _asStringList(json['appliedParticipantKeys']),
      unresolvedParticipants: _asMapList(
        json['unresolvedParticipants'],
      ).map(AttendanceCommentUnresolvedParticipant.fromJson).toList(),
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

bool _asBool(dynamic value) {
  if (value is bool) return value;
  final raw = value?.toString().trim().toLowerCase();
  return raw == 'true' || raw == '1' || raw == 'yes';
}
