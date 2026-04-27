export type FirebaseLoginResponse = {
    idToken?: string;
    refreshToken?: string;
    expiresIn?: string;
};

export type FirebaseRefreshResponse = {
    id_token?: string;
    refresh_token?: string;
    expires_in?: string;
};

export type LmsStudent = {
    id: string;
    fullName: string;
};

export type LmsTeacherUser = {
    id: string;
    username?: string;
    fullName?: string;
};

export type LmsTeacherProfile = {
    id: string;
    user?: string;
    username?: string;
    fullName?: string;
    hourlyRate?: string;
    firebaseId?: string;
};

export type LmsTeacherRole = {
    id?: string;
    name?: string;
    shortName?: string;
};

export type LmsTeacherAssignment = {
    _id?: string;
    isActive?: boolean;
    classSiteId?: string;
    teacher?: LmsTeacherUser;
    role?: LmsTeacherRole;
};

export type LmsTeacherAttendanceRecord = {
    _id?: string;
    status?: string;
    note?: string | null;
    classSiteId?: string;
    teacher?: LmsTeacherUser;
};

export type LmsStudentAttendanceRecord = {
    _id?: string;
    status?: string;
    note?: string | null;
    comment?: string | null;
    commentByAreas?: LmsCommentByAreaRecord[];
    student?: LmsStudent;
};

export type LmsCommentByAreaRecord = {
    grade?: number | null;
    content?: string | null;
    commentAreaId?: string | null;
    type?: string | null;
};

export type LmsClassSite = {
    _id?: string;
    name?: string;
};

export type LmsClassStudent = {
    _id?: string;
    student?: LmsStudent;
    classSite?: LmsClassSite;
    activeInClass?: boolean;
};

export type LmsSlotRecord = {
    _id?: string;
    index?: number;
    date?: string;
    startTime?: string;
    endTime?: string;
    teachers?: LmsTeacherAssignment[];
    teacherAttendance?: LmsTeacherAttendanceRecord[];
    studentAttendance?: LmsStudentAttendanceRecord[];
};

export type LmsClassRecord = {
    id: string;
    name: string;
    status?: string;
    endDate?: string;
    courseProcessId?: string;
    courseProcess?: LmsCourseProcess;
    teachers?: LmsTeacherAssignment[];
    students?: LmsClassStudent[];
    classSites?: LmsClassSite[];
    slots?: LmsSlotRecord[];
};

export type LmsCourseProcess = {
    id?: string;
    defaultCommentAreas?: LmsCommentArea[];
    specificSessions?: LmsCourseProcessSpecificSession[];
};

export type LmsCourseProcessSpecificSession = {
    session?: number;
    alwaysShow?: boolean;
    commentAreas?: LmsCommentArea[];
};

export type LmsCommentArea = {
    id?: string;
    name?: string;
    fieldName?: string;
    type?: string;
    slots?: string[];
    isRequired?: boolean;
};

export type LmsSlotAttendanceStatus =
    | 'ATTENDED'
    | 'LATE_ARRIVED'
    | 'ABSENT_WITH_NOTICE'
    | 'ABSENT';

export type LmsStudentAttendancePayload = {
    _id?: string;
    student?: string;
    status?: string;
    note?: string | null;
};

export type LmsTeacherAttendancePayload = {
    _id?: string;
    teacher?: string;
    status?: string;
    note?: string | null;
    classSiteId?: string;
};

export type LmsSlotAttendanceCommand = {
    classId: string;
    slotId: string;
    classSiteId?: string;
    studentAttendance?: LmsStudentAttendancePayload[];
    teacherAttendance?: LmsTeacherAttendancePayload[];
};

export type LmsCommentByAreaCommand = {
    content: string;
    commentAreaId: string;
    type?: string;
};

export type LmsUpdateSlotStudentCommentCommand = {
    studentAttendanceId: string;
    studentId: string;
    content: string;
    byAreas?: LmsCommentByAreaCommand[];
};

export type LmsUpdateSlotCommentCommand = {
    classId: string;
    slotId: string;
    classSiteId?: string;
    sessionNumber?: number;
    courseProcessId?: string;
    studentComment: LmsUpdateSlotStudentCommentCommand;
};

export type LmsTimesheetClass = {
    id?: string;
    name?: string;
};

export type LmsClassSessionAttendance = {
    id?: string;
    startTime?: string;
    endTime?: string;
    sessionHour?: number;
    status?: string;
    class?: LmsTimesheetClass;
};

export type LmsOfficeHour = {
    id?: string;
    startTime?: string;
    endTime?: string;
    status?: string;
    type?: string;
    studentCount?: number;
    note?: string | null;
    managerNote?: string | null;
    shortName?: string;
};

export type LmsTimesheetItem = {
    id?: string;
    type?: string;
    date?: string;
    status?: string;
    teacher?: LmsTeacherProfile;
    classSessionAttendance?: LmsClassSessionAttendance;
    officeHour?: LmsOfficeHour;
};
