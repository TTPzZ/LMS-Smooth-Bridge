import express, { Request, Response } from 'express';
import cors from 'cors';
import axios from 'axios';

const app = express();
const PORT = 3000;
const LMS_GRAPHQL_URL = 'https://lms-api.mindx.edu.vn/graphql';
const DEFAULT_ITEMS_PER_PAGE = 50;
const DEFAULT_MAX_PAGES = 10;

app.use(cors());
app.use(express.json());

const TEMP_ID_TOKEN = "eyJhbGciOiJSUzI1NiIsImtpZCI6IjNiMDk1NzQ3YmY4MzMxZWE0YWQ1M2YzNzBjNjMyNjAxNzliMGQyM2EiLCJ0eXAiOiJKV1QifQ.eyJuYW1lIjoiVGjDom4gVHLhu41uZyBQaMO6YyIsImlkIjoiNjRlY2E5MTY1YjcxOTA0ZTJhM2Q1ZTE0IiwidXNlcm5hbWUiOiJwaHVjdGhhbjI5OSIsImlzcyI6Imh0dHBzOi8vc2VjdXJldG9rZW4uZ29vZ2xlLmNvbS9taW5keC1lZHUtcHJvZCIsImF1ZCI6Im1pbmR4LWVkdS1wcm9kIiwiYXV0aF90aW1lIjoxNzc2ODU1NjU4LCJ1c2VyX2lkIjoiN0dVRGwxc2dseFBtU2ZueGZENnhaVWhkclgyMyIsInN1YiI6IjdHVURsMXNnbHhQbVNmbnhmRDZ4WlVoZHJYMjMiLCJpYXQiOjE3NzY4NTU2NTgsImV4cCI6MTc3Njg1OTI1OCwiZW1haWwiOiJwaHVjdGhhbjI5OUBtaW5keC5uZXQudm4iLCJlbWFpbF92ZXJpZmllZCI6dHJ1ZSwicGhvbmVfbnVtYmVyIjoiKzg0OTMzNjE4MjU3IiwiZmlyZWJhc2UiOnsiaWRlbnRpdGllcyI6eyJlbWFpbCI6WyJwaHVjdGhhbjI5OUBtaW5keC5uZXQudm4iXSwicGhvbmUiOlsiKzg0OTMzNjE4MjU3Il19LCJzaWduX2luX3Byb3ZpZGVyIjoicGFzc3dvcmQifX0.gTd1ohbg8L_DNTBpwgvseKJoOsZESVhFH8o_ZidjWMC3tmP0_SfLaIoCkUbgqBZXPnVX8HpAx7xoBMmlhL36dM4ucCRYXa-k0jZ8oO93I54yYBKhp55OOTakoXKHK6yZ84GL2cXjPZytEEW3NACVfknVRZQ97LKQbiKHOV8JfRYzN1JsXrhUzb9Gf2UVElGdqT-MXeGUnoyamdM8VOh_ZUnkO5Cl4Pgui-G8JzYKoDpjbg8cQzV8e3Fg4F08AVFijAo5ALJXNz4nupBcOpkQqgqiHfzBHBuMML54B0wWHSiBmGbqwcxXjSxZtInvBqVMzSEozZzG4n4GxBgID3k-eg";

type LmsStudent = {
    id: string;
    fullName: string;
};

type LmsClassRecord = {
    id: string;
    name: string;
    status?: string;
    endDate?: string;
    slots?: Array<{
        studentAttendance?: Array<{
            student?: LmsStudent;
        }>;
    }>;
};

function parseIntegerQuery(value: unknown, fallback: number): number {
    const parsedValue = Number.parseInt(String(value ?? ''), 10);
    if (Number.isNaN(parsedValue) || parsedValue <= 0) {
        return fallback;
    }

    return parsedValue;
}

function parseBooleanQuery(value: unknown, fallback: boolean): boolean {
    if (value === undefined || value === null) {
        return fallback;
    }

    const normalized = String(value).toLowerCase();
    if (normalized === '1' || normalized === 'true' || normalized === 'yes') {
        return true;
    }

    if (normalized === '0' || normalized === 'false' || normalized === 'no') {
        return false;
    }

    return fallback;
}

function hasNotEnded(endDate: string | undefined, now: Date): boolean {
    if (!endDate) {
        return true;
    }

    const endDateValue = new Date(endDate);
    if (Number.isNaN(endDateValue.getTime())) {
        return true;
    }

    return endDateValue >= now;
}

function normalizeClassStatus(status: string | undefined): string | undefined {
    if (!status) {
        return undefined;
    }

    return status.trim().toUpperCase();
}

function isRunningClass(cls: LmsClassRecord, now: Date): boolean {
    const normalizedStatus = normalizeClassStatus(cls.status);
    if (normalizedStatus) {
        return normalizedStatus === 'RUNNING';
    }

    return hasNotEnded(cls.endDate, now);
}

async function getClassesPage(pageIndex: number, itemsPerPage: number): Promise<LmsClassRecord[]> {
    const graphqlQuery = {
        operationName: 'GetClasses',
        query: `query GetClasses($pageIndex: Int!, $itemsPerPage: Int!) {
          classes(payload: {pageIndex: $pageIndex, itemsPerPage: $itemsPerPage}) {
            data {
              id
              name
              status
              endDate
              slots {
                studentAttendance {
                  student {
                    id
                    fullName
                  }
                }
              }
            }
          }
        }`,
        variables: {
            pageIndex,
            itemsPerPage
        }
    };

    const response = await axios.post(LMS_GRAPHQL_URL, graphqlQuery, {
        headers: {
            Authorization: `Bearer ${TEMP_ID_TOKEN}`,
            'Content-Type': 'application/json'
        }
    });

    const graphqlErrors = response.data?.errors;
    if (Array.isArray(graphqlErrors) && graphqlErrors.length > 0) {
        const errorMessage = graphqlErrors
            .map((item: any) => item?.message)
            .filter(Boolean)
            .join(' | ');
        throw new Error(errorMessage || 'GraphQL returned unknown errors');
    }

    const classes = response.data?.data?.classes?.data;
    if (!Array.isArray(classes)) {
        return [];
    }

    return classes as LmsClassRecord[];
}

app.get('/api/classes', async (req: Request, res: Response) => {
    try {
        const itemsPerPage = parseIntegerQuery(req.query.itemsPerPage, DEFAULT_ITEMS_PER_PAGE);
        const maxPages = parseIntegerQuery(req.query.maxPages, DEFAULT_MAX_PAGES);
        const activeOnly = parseBooleanQuery(req.query.activeOnly, true);
        const now = new Date();
        const rawClasses: LmsClassRecord[] = [];
        let fetchedPages = 0;

        for (let pageIndex = 0; pageIndex < maxPages; pageIndex += 1) {
            const pageData = await getClassesPage(pageIndex, itemsPerPage);
            fetchedPages += 1;

            if (pageData.length === 0) {
                break;
            }

            rawClasses.push(...pageData);

            if (pageData.length < itemsPerPage) {
                break;
            }
        }

        const uniqueClasses = new Map<string, LmsClassRecord>();
        rawClasses.forEach((cls) => {
            if (cls?.id && !uniqueClasses.has(cls.id)) {
                uniqueClasses.set(cls.id, cls);
            }
        });

        const cleanClasses = Array.from(uniqueClasses.values())
            .filter((cls) => (activeOnly ? isRunningClass(cls, now) : true))
            .map((cls) => {
                const studentMap = new Map<string, string>();

                (cls.slots || []).forEach((slot) => {
                    (slot.studentAttendance || []).forEach((attendance) => {
                        const student = attendance.student;
                        if (student?.id && student.fullName) {
                            studentMap.set(student.id, student.fullName);
                        }
                    });
                });

                return {
                    classId: cls.id,
                    className: cls.name,
                    status: normalizeClassStatus(cls.status) ?? null,
                    endDate: cls.endDate,
                    totalStudents: studentMap.size,
                    students: Array.from(studentMap.values())
                };
            });

        res.json({
            success: true,
            data: cleanClasses,
            meta: {
                fetchedPages,
                itemsPerPage,
                maxPages,
                activeOnly,
                totalRawClasses: rawClasses.length,
                totalUniqueClasses: uniqueClasses.size,
                returnedClasses: cleanClasses.length
            }
        });

    } catch (error: any) {
        const statusCode = error?.response?.status || 500;
        const detail = error?.response?.data || error?.message;
        console.error('Loi:', detail);
        res.status(statusCode).json({
            success: false,
            error: 'Loi ket noi API',
            detail
        });
    }
});

app.listen(PORT, () => {
    console.log(`Server dang chay tai http://localhost:${PORT}`);
});
