import rateLimit from 'express-rate-limit';

/**
 * Rate limiting middleware for public file sharing access:
 * بحد أقصى 20 محاولة كل 15 دقيقة لكل عنوان IP
 * مع رسالة خطأ عربية واضحة ومحددة عند تجاوز الحد
 */
export const shareDownloadRateLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 دقيقة
  max: 20, // 20 طلباً كحد أقصى لكل IP خلال نافذة الـ 15 دقيقة
  standardHeaders: true, // إرجاع ترويسات RateLimit-* المعيارية (RFC draft-6/7)
  legacyHeaders: false, // تعطيل ترويسات X-RateLimit-* القديمة
  message: {
    success: false,
    statusCode: 429,
    message: 'تجاوزت الحد المسموح به لمحاولات الوصول إلى روابط المشاركة (20 محاولة كل 15 دقيقة). يرجى المحاولة لاحقاً بعد انتهاء فترة الانتظار.',
  },
  handler: (_req, res, _next, options) => {
    res.status(options.statusCode).json(options.message);
  },
});
