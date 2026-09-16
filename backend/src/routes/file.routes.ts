import { Router } from 'express';
import { fileController } from '../controllers/file.controller.js';
import { shareController } from '../controllers/share.controller.js';
import { upload } from '../middlewares/upload.middleware.js';
import { authenticate } from '../middlewares/auth.middleware.js';
import { requireTelegramConfig } from '../middlewares/require-telegram.middleware.js';

const router = Router();

// تتطلب جميع مسارات الملفات التحقق من جلسة المستخدم أولاً
router.use(authenticate);

// 1. عرض قائمة الملفات والمجلدات الخاصة بالمستخدم (دعم pagination وفلترة parent_folder_id)
router.get('/', (req, res, next) => fileController.list(req, res, next));

// 2. رفع ملف وتخزينه في تيليجرام (يتطلب وجود بيانات تيليجرام مفعلة للمستخدم)
router.post('/upload', requireTelegramConfig, upload.single('file'), (req, res, next) => fileController.upload(req, res, next));

// 3. تنزيل ملف كـ Stream من تيليجرام
router.get('/:id/download', requireTelegramConfig, (req, res, next) => fileController.download(req, res, next));

// 4. إنشاء رابط مشاركة لملف (POST /api/files/:id/share)
router.post('/:id/share', (req, res, next) => shareController.createShare(req, res, next));

// 5. عرض روابط المشاركة الخاصة بملف (GET /api/files/:id/shares)
router.get('/:id/shares', (req, res, next) => shareController.getFileShares(req, res, next));

// 6. حذف ملف من تيليجرام ومن قاعدة البيانات
router.delete('/:id', requireTelegramConfig, (req, res, next) => fileController.delete(req, res, next));

export const fileRoutes = router;

