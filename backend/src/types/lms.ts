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

export type LmsTeacherRole = {
    id?: string;
    name?: string;
    shortName?: string;
};

export type LmsTeacherAssignment = {
    _id?: string;
    isActive?: boolean;
    teacher?: LmsTeacherUser;
    role?: LmsTeacherRole;
};

export type LmsTeacherAttendanceRecord = {
    _id?: string;
    status?: string;
    note?: string | null;
    teacher?: LmsTeacherUser;
};

export type LmsStudentAttendanceRecord = {
    _id?: string;
    status?: string;
    student?: LmsStudent;
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
    teachers?: LmsTeacherAssignment[];
    slots?: LmsSlotRecord[];
};
