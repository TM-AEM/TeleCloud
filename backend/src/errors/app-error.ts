export class AppError extends Error {
  public readonly statusCode: number;
  public readonly isOperational: boolean;
  public readonly details?: any;

  constructor(message: string, statusCode: number = 500, details?: any, isOperational: boolean = true) {
    super(message);
    this.statusCode = statusCode;
    this.details = details;
    this.isOperational = isOperational;
    Object.setPrototypeOf(this, new.target.prototype);
    Error.captureStackTrace(this, this.constructor);
  }

  static badRequest(message: string, details?: any) {
    return new AppError(message, 400, details);
  }

  static unauthorized(message: string = 'غير مصرح لك، يرجى تسجيل الدخول أولاً', details?: any) {
    return new AppError(message, 401, details);
  }

  static forbidden(message: string = 'غير مصرح لك بتنفيذ هذا الإجراء', details?: any) {
    return new AppError(message, 403, details);
  }

  static notFound(message: string = 'العنصر المطلوب غير موجود', details?: any) {
    return new AppError(message, 404, details);
  }

  static gone(message: string = 'العنصر المطلوب لم يعد متوفراً أو انتهت صلاحيته', details?: any) {
    return new AppError(message, 410, details);
  }

  static internal(message: string = 'حدث خطأ غير متوقع في الخادم', details?: any) {
    return new AppError(message, 500, details, false);
  }

  static telegramError(message: string, details?: any) {
    return new AppError(`خطأ في Telegram API: ${message}`, 502, details);
  }
}
