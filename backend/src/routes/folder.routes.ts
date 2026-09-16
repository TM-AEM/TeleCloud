import { Router } from 'express';
import { folderController } from '../controllers/folder.controller.js';
import { authenticate } from '../middlewares/auth.middleware.js';
import { requireTelegramConfig } from '../middlewares/require-telegram.middleware.js';

const router = Router();

// تتطلب جميع عمليات المجلدات التحقق من هوية المستخدم
router.use(authenticate);

// 1. إنشاء مجلد وهمي
router.post('/', (req, res, next) => folderController.create(req, res, next));

// 2. جلب تفاصيل مجلد
router.get('/:id', (req, res, next) => folderController.getById(req, res, next));

// 3. حذف مجلد (مع جلب إعدادات تيليجرام لحذف رسائل كافة الملفات المتداخلة)
router.delete('/:id', requireTelegramConfig, (req, res, next) => folderController.delete(req, res, next));

export const folderRoutes = router;
