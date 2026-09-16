import { Router } from 'express';
import { shareController } from '../controllers/share.controller.js';

const router = Router();

/**
 * مسار عام (Public، بدون JWT) لتحميل الملف بواسطة الرمز المميز
 * محمي بـ Rate Limiter بحد أقصى 20 محاولة كل 15 دقيقة لكل عنوان IP
 * GET /api/share/:token
 */
router.get('/:token', shareController.rateLimiter, (req, res, next) => shareController.downloadSharedFile(req, res, next));

export const shareRoutes = router;
