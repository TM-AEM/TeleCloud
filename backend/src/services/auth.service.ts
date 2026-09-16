import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { prisma } from '../lib/prisma.js';
import { env } from '../config/env.js';
import { AppError } from '../errors/app-error.js';

export interface RegisterDto {
  email: string;
  username: string;
  password: string;
}

export interface LoginDto {
  login: string; // البريد الإلكتروني أو اسم المستخدم
  password: string;
}

export class AuthService {
  /**
   * تسجيل حساب مستخدم جديد
   */
  async register(dto: RegisterDto) {
    const { email, username, password } = dto;

    if (!email || !username || !password) {
      throw AppError.badRequest('جميع الحقول (البريد، اسم المستخدم، وكلمة المرور) مطلوبة');
    }

    if (password.length < 6) {
      throw AppError.badRequest('كلمة المرور يجب أن لا تقل عن 6 أحرف');
    }

    const normalizedEmail = email.trim().toLowerCase();
    const normalizedUsername = username.trim().toLowerCase();

    // التحقق من عدم وجود البريد أو اسم المستخدم مسبقاً
    const existing = await prisma.user.findFirst({
      where: {
        OR: [
          { email: normalizedEmail },
          { username: normalizedUsername },
        ],
      },
    });

    if (existing) {
      if (existing.email === normalizedEmail) {
        throw AppError.badRequest('البريد الإلكتروني مسجل بالفعل');
      }
      throw AppError.badRequest('اسم المستخدم مأخوذ بالفعل');
    }

    // تشفير كلمة المرور
    const hashedPassword = await bcrypt.hash(password, 10);

    const user = await prisma.user.create({
      data: {
        email: normalizedEmail,
        username: normalizedUsername,
        password: hashedPassword,
      },
      select: {
        id: true,
        email: true,
        username: true,
        isTelegramConfigured: true,
        createdAt: true,
      },
    });

    // إنشاء JWT Token
    const token = this.generateToken(user.id, user.email, user.username);

    return {
      user,
      token,
    };
  }

  /**
   * تسجيل دخول المستخدم
   */
  async login(dto: LoginDto) {
    const { login, password } = dto;

    if (!login || !password) {
      throw AppError.badRequest('يرجى إدخال اسم المستخدم أو البريد وكلمة المرور');
    }

    const normalizedLogin = login.trim().toLowerCase();

    // البحث بالبريد الإلكتروني أو اسم المستخدم
    const user = await prisma.user.findFirst({
      where: {
        OR: [
          { email: normalizedLogin },
          { username: normalizedLogin },
        ],
      },
    });

    if (!user) {
      throw AppError.badRequest('بيانات الدخول غير صحيحة');
    }

    const isMatch = await bcrypt.compare(password, user.password);
    if (!isMatch) {
      throw AppError.badRequest('بيانات الدخول غير صحيحة');
    }

    const token = this.generateToken(user.id, user.email, user.username);

    return {
      user: {
        id: user.id,
        email: user.email,
        username: user.username,
        isTelegramConfigured: user.isTelegramConfigured,
        createdAt: user.createdAt,
      },
      token,
    };
  }

  /**
   * جلب بيانات الملف الشخصي للمستخدم الحالي
   */
  async getProfile(userId: string) {
    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        email: true,
        username: true,
        isTelegramConfigured: true,
        createdAt: true,
        updatedAt: true,
        _count: {
          select: {
            files: true,
            folders: true,
          },
        },
      },
    });

    if (!user) {
      throw AppError.notFound('المستخدم غير موجود');
    }

    return user;
  }

  private generateToken(userId: string, email: string, username: string): string {
    return jwt.sign(
      { userId, email, username },
      env.JWT_SECRET,
      { expiresIn: env.JWT_EXPIRES_IN as any }
    );
  }
}

export const authService = new AuthService();
