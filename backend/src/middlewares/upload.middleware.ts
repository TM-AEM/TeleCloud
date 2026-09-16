import multer from 'multer';
import { env } from '../config/env.js';
import { AppError } from '../errors/app-error.js';

// استخدام الذاكرة المؤقتة (MemoryStorage) لرفع الملف مباشرة إلى تيليجرام دون تخزين مؤقت على القرص
const storage = multer.memoryStorage();

export const upload = multer({
  storage,
  limits: {
    fileSize: env.MAX_FILE_SIZE_BYTES, // الحد الأقصى للملف
  },
  fileFilter: (_req, file, cb) => {
    // إصلاح ترميز اسم الملف باللغة العربية أو الحروف الخاصة
    file.originalname = Buffer.from(file.originalname, 'latin1').toString('utf8');
    cb(null, true);
  },
});
