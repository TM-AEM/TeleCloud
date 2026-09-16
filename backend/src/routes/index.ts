import { Router } from 'express';
import { authRoutes } from './auth.routes.js';
import { settingsRoutes } from './settings.routes.js';
import { fileRoutes } from './file.routes.js';
import { folderRoutes } from './folder.routes.js';
import { shareRoutes } from './share.routes.js';
import { sharesManagementRoutes } from './shares.routes.js';

const router = Router();

// مسارات المصادقة والمستخدمين (تسجيل جديد وتسجيل دخول)
router.use('/auth', authRoutes);

// مسارات إعدادات تيليجرام الخاصة بكل مستخدم
router.use('/settings', settingsRoutes);

// مسارات الملفات والمجلدات المعزولة لكل مستخدم
router.use('/files', fileRoutes);
router.use('/folders', folderRoutes);

// مسار مشاركة الملفات العام (Public - بدون JWT: GET /api/share/:token)
router.use('/share', shareRoutes);

// مسار إدارة روابط المشاركة المحمي (Protected - يتطلب JWT: DELETE /api/shares/:shareId)
router.use('/shares', sharesManagementRoutes);

export const apiRoutes = router;


