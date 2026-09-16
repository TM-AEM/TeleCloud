import { Router } from 'express';
import { shareController } from '../controllers/share.controller.js';
import { authenticate } from '../middlewares/auth.middleware.js';

const router = Router();

// مسارات إدارة الروابط المشاركة تتطلب تسجيل الدخول (JWT)
router.use(authenticate);

/**
 * إلغاء رابط المشاركة فوراً للمستخدم صاحب الملف
 * DELETE /api/shares/:shareId
 */
router.delete('/:shareId', (req, res, next) => shareController.revokeShare(req, res, next));

export const sharesManagementRoutes = router;
