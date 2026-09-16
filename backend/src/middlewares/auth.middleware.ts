import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { env } from '../config/env.js';
import { prisma } from '../lib/prisma.js';
import { AppError } from '../errors/app-error.js';

interface JwtPayload {
  userId: string;
  email: string;
  username: string;
}

export async function authenticate(req: Request, _res: Response, next: NextFunction): Promise<void> {
  try {
    const authHeader = req.headers.authorization;

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      throw new AppError('يرجى تسجيل الدخول أولاً للوصول إلى هذه الخدمة (Bearer Token مطلوب)', 401);
    }

    const token = authHeader.split(' ')[1];

    if (!token) {
      throw new AppError('رمز التوثيق مفقود', 401);
    }

    let decoded: JwtPayload;
    try {
      decoded = jwt.verify(token, env.JWT_SECRET) as JwtPayload;
    } catch (jwtErr: any) {
      if (jwtErr.name === 'TokenExpiredError') {
        throw new AppError('انتهت صلاحية جلسة الدخول، يرجى تسجيل الدخول مرة أخرى', 401);
      }
      throw new AppError('رمز التوثيق غير صالح', 401);
    }

    const user = await prisma.user.findUnique({
      where: { id: decoded.userId },
      select: {
        id: true,
        email: true,
        username: true,
        isTelegramConfigured: true,
      },
    });

    if (!user) {
      throw new AppError('المستخدم صاحب هذا الرمز لم يعد موجوداً', 401);
    }

    req.user = user;
    next();
  } catch (error) {
    next(error);
  }
}
