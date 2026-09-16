import express, { Request, Response } from 'express';
import cors from 'cors';
import { env } from './config/env.js';
import { apiRoutes } from './routes/index.js';
import { errorHandler } from './middlewares/error.middleware.js';
import { AppError } from './errors/app-error.js';
import { prisma } from './lib/prisma.js';
import { initCronJobs } from './jobs/cleanup.job.js';

const app = express();

// إعدادات الـ Middlewares الأساسية
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// فحص جاهزية الخادم وقاعدة البيانات
app.get('/health', async (_req: Request, res: Response) => {
  try {
    await prisma.$queryRaw`SELECT 1`;
    res.status(200).json({
      status: 'ok',
      uptime: process.uptime(),
      timestamp: new Date().toISOString(),
      database: 'connected',
      telegramApi: {
        baseUrl: env.TELEGRAM_API_BASE_URL,
        mode: env.TELEGRAM_API_BASE_URL.includes('api.telegram.org') ? 'Cloud (20MB limit)' : 'Local Server (2GB limit)',
      },
    });
  } catch (error) {
    res.status(503).json({
      status: 'error',
      database: 'disconnected',
    });
  }
});

// المسارات الأساسية للتطبيق
app.use('/api', apiRoutes);

// معالجة المسارات غير الموجودة (404)
app.use((_req: Request, _res: Response, next) => {
  next(AppError.notFound('المسار المطلوب غير موجود في خادم الـ API'));
});

// معالجة الأخطاء الشاملة
app.use(errorHandler);

// تشغيل الخادم
const PORT = env.PORT;
const server = app.listen(PORT, () => {
  console.log(`🚀 خادم التخزين السحابي يعمل بنجاح على المنفذ: ${PORT}`);
  console.log(`📁 البيئة: ${env.NODE_ENV}`);
  console.log(`🔗 نقطة البداية: http://localhost:${PORT}/api`);
  initCronJobs();
});

// إدارة الإغلاق الآمن للخادم
const gracefulShutdown = async () => {
  console.log('🔄 جاري إيقاف الخادم وإغلاق الاتصالات بأمان...');
  server.close(async () => {
    await prisma.$disconnect();
    console.log('✅ تم إغلاق خادم Express وقاعدة بيانات Prisma.');
    process.exit(0);
  });
};

process.on('SIGINT', gracefulShutdown);
process.on('SIGTERM', gracefulShutdown);

export default app;
