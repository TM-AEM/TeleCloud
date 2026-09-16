import { Router } from 'express';
import { settingsController } from '../controllers/settings.controller.js';
import { authenticate } from '../middlewares/auth.middleware.js';

const router = Router();

// حفظ والتحقق من بيانات تيليجرام وتشفيرها للمستخدم
router.post('/telegram', authenticate, settingsController.saveTelegramConfig);

// استرجاع حالة إعدادات تيليجرام
router.get('/telegram', authenticate, settingsController.getTelegramConfigStatus);

export const settingsRoutes = router;
