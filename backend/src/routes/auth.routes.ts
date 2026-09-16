import { Router } from 'express';
import { authController } from '../controllers/auth.controller.js';
import { authenticate } from '../middlewares/auth.middleware.js';

const router = Router();

// تسجيل حساب جديد
router.post('/register', authController.register);

// تسجيل الدخول
router.post('/login', authController.login);

// الملف الشخصي للمستخدم الحالي
router.get('/me', authenticate, authController.me);

export const authRoutes = router;
