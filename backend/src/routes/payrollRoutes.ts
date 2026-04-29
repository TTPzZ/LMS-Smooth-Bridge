import { Router, Request, Response } from 'express';
import { PayrollService } from '../services/payrollService';
import { parseBearerToken } from '../utils/requestParsers';

export function createPayrollRouter(payrollService: PayrollService): Router {
    const router = Router();

    router.get('/payroll/monthly', async (req: Request, res: Response) => {
        try {
            const idTokenFromHeader = parseBearerToken(req.headers.authorization);
            if (!idTokenFromHeader) {
                res.status(401).json({
                    success: false,
                    error: 'Authorization header khong hop le',
                    detail: 'Expected format: Bearer <id_token>'
                });
                return;
            }

            const data = await payrollService.getMonthlyPayroll({
                month: req.query.month,
                year: req.query.year,
                timezone: req.query.timezone,
                teacherId: undefined,
                username: undefined,
                itemsPerPage: req.query.itemsPerPage,
                maxPages: req.query.maxPages,
                countedStatuses: req.query.countedStatuses
            }, idTokenFromHeader);

            res.json({
                success: true,
                data
            });
        } catch (error: any) {
            const detail = error?.response?.data || error?.message || 'Payroll query failed';
            const statusCode = typeof error?.statusCode === 'number'
                ? error.statusCode
                : typeof error?.response?.status === 'number'
                    ? error.response.status
                    : 400;
            if (statusCode === 401) {
                res.status(401).json({
                    success: false,
                    error: 'Unauthorized',
                    detail: 'Invalid or expired Bearer token'
                });
                return;
            }
            res.status(statusCode).json({
                success: false,
                error: 'Khong lay duoc du lieu payroll',
                detail: statusCode >= 500 ? 'Internal server error' : 'Request failed'
            });
        }
    });

    return router;
}
