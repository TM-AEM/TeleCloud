# Telegram Cloud Storage Multi-Tenant Backend API (Node.js + Express + TypeScript + Prisma + PostgreSQL)

خادم Backend متكامل لتطبيق تخزين سحابي متعدد المستخدمين (**Multi-Tenant**) يعتمد على **Telegram Bot API** كمساحة تخزين فعلية، ويستخدم **PostgreSQL** مع **Prisma ORM** لتخزين البيانات الوصفية (Metadata)، وهيكلية المجلدات الوهمية، وإدارة حسابات المستخدمين.

---

## 🔒 آلية العمل الجديدة (Multi-Tenant Architecture)

تم تصميم النظام ليكون متعدد المستخدمين وآمناً بالكامل دون الحاجة لتثبيت بيانات تيليجرام في إعدادات السيرفر:

1. **تسجيل الحساب (Registration & Login)**:
   - يسجل كل مستخدم حسابه الخاص عبر البريد أو اسم المستخدم وكلمة مرور مشفرة بواسطة `bcrypt`.
   - يحصل المستخدم على رمز توثيق **JWT Bearer Token** يُستخدم في جميع الطلبات اللاحقة.

2. **إعداد مساحة تيليجرام الخاصة بكل مستخدم (User Settings)**:
   - من شاشة الإعدادات داخل التطبيق، يرسل المستخدم بيانات تيليجرام الخاصة به:
     - `telegramBotToken`: توكن البوت الخاص به من [@BotFather](https://t.me/BotFather).
     - `telegramChannelId`: معرّف القناة الخاصة به (يبدأ بـ `-100`) والتي أضاف البوت فيها كـ مشرف (Admin).
     - `telegramApiId` و `telegramApiHash`: المعرفات الخاصة به من [my.telegram.org](https://my.telegram.org).
   - يقوم الخادم فوراً بعمل **استدعاء تجريبي مباشر** (`getMe` و `getChat`) للتحقق من صحة التوكن ووصول البوت للقناة.
   - يتم **تشفير هذه البيانات الأربعة بخوارزمية التشفير العسكري AES-256-GCM** باستخدام مفتاح السيرفر السري `ENCRYPTION_SECRET_KEY` قبل حفظها في قاعدة البيانات.

3. **الاستخدام اللحظي الآمن (On-the-fly Decryption)**:
   - عند تنفيذ أي طلب رفع، تنزيل، أو حذف، يتحقق الوسيط (`requireTelegramConfig`) من هوية المستخدم ويقوم بفك تشفير بيانات تيليجرام الخاصة به **في الذاكرة العشوائية (In-Memory) فقط طوال فترة معالجة الطلب**.
   - لا يتم حفظ البيانات المفكوكة في أي مكان دائم، ولا تظهر إطلاقاً في استجابات الـ API.

4. **عزل كامل للبيانات (Full Tenant Isolation)**:
   - كل مستخدم لديه مساحة تخزين خاصة به بالكامل.
   - جميع الملفات والمجلدات مرتبطة بـ `userId`.
   - يستحيل على أي مستخدم استعراض أو تنزيل أو حذف ملفات ومجلدات مستخدم آخر.

---

## ⚡ مقارنة: السيرفر السحابي (api.telegram.org) مقابل السيرفر المحلي (Local Bot API)

| الميزة | السيرفر السحابي (`api.telegram.org`) | السيرفر المحلي (`telegram/bot-api` Docker) |
| :--- | :--- | :--- |
| **الحد الأقصى للتنزيل (`getFile`)** | **20 ميجابايت (20MB)** | **2000 ميجابايت (2GB)** 🚀 |
| **الحد الأقصى للرفع (`sendDocument`)** | 50 ميجابايت (50MB) | **2000 ميجابايت (2GB)** 🚀 |
| **السرعة وزمن الاستجابة** | تعتمد على سرعة الاتصال بخوادم تيليجرام | أسرع بكثير (معالجة الملفات محلياً مع الـ Bot API) |
| **إعدادات السيرفر** | لا تتطلب تشغيل حاوية وسيطة | تشغيل حاوية `telegram-bot-api` عبر Docker Compose |

---

## 🛠️ المتطلبات الأساسية وتجهيز البيئة (Prerequisites)

1. **Node.js** (الإصدار 18 أو أحدث)
2. **Docker & Docker Compose** (لتشغيل PostgreSQL وسيرفر Telegram Bot API المحلي)

### 1. تثبيت الحزم
```bash
cd backend
npm install
```

### 2. إعداد ملف البيئة (.env)
انسخ النموذج الجاهز:
```bash
cp .env.example .env
```

محتوى ملف `.env` (لاحظ أنه لا يحتوي على أي توكنات أو بيانات تيليجرام خاصة بالمستخدمين):
```env
PORT=4000
NODE_ENV=development

# رابط قاعدة البيانات
DATABASE_URL="postgresql://postgres:postgrespassword@localhost:5432/telegram_cloud_db?schema=public"

# مفتاح JWT السري
JWT_SECRET="my-super-secret-jwt-key-change-this-in-production"
JWT_EXPIRES_IN="7d"

# مفتاح تشفير AES-256 لتشفير بيانات تيليجرام الخاصة بكل مستخدم في قاعدة البيانات (مطلوب - 16 حرفاً على الأقل)
ENCRYPTION_SECRET_KEY="telegram-cloud-aes-encryption-secret-key-32"

# الرابط الأساسي للسيرفر (يُستخدم في توليد روابط المشاركة العامة للملفات)
APP_BASE_URL="http://localhost:4000"

# رابط خادم Telegram API (محلي لرفع حتى 2GB أو سحابي)
TELEGRAM_API_BASE_URL="http://localhost:8081"

# الحد الأقصى للملفات (2GB)
MAX_FILE_SIZE_BYTES=2147483648
```

### 3. تشغيل الحاويات (PostgreSQL + Telegram Bot API)
```bash
docker-compose up -d
```

### 4. تطبيق تهجير قاعدة البيانات (Prisma Migrations)
```bash
npx prisma migrate dev --name init_multitenant
npx prisma generate
```

### 5. تشغيل الخادم
```bash
npm run dev
```
سيبدأ الخادم بالعمل على الرابط: `http://localhost:4000/api`.

---

## 📡 التوثيق الكامل لنقاط النهاية (API Endpoints Reference)

> **ملاحظة**: جميع المسارات المحمية تتطلب إرسال الترويسة التالية:
> `Authorization: Bearer <YOUR_JWT_TOKEN>`

---

### 1. المصادقة والمستخدمين (Authentication)

#### أ) تسجيل حساب جديد
- **الرابط**: `POST /api/auth/register`
- **جسم الطلب (Body)**:
```json
{
  "email": "user@example.com",
  "username": "ahmed",
  "password": "password123"
}
```
- **الاستجابة (201 Created)**:
```json
{
  "success": true,
  "message": "تم تسجيل الحساب بنجاح",
  "data": {
    "user": {
      "id": "uuid-here",
      "email": "user@example.com",
      "username": "ahmed",
      "isTelegramConfigured": false
    },
    "token": "eyJhbGciOiJIUzI1NiIsIn..."
  }
}
```

#### ب) تسجيل الدخول
- **الرابط**: `POST /api/auth/login`
- **جسم الطلب (Body)**:
```json
{
  "login": "user@example.com",
  "password": "password123"
}
```
- **الاستجابة (200 OK)**:
```json
{
  "success": true,
  "message": "تم تسجيل الدخول بنجاح",
  "data": {
    "user": {
      "id": "uuid-here",
      "email": "user@example.com",
      "username": "ahmed",
      "isTelegramConfigured": true
    },
    "token": "eyJhbGciOiJIUzI1NiIsIn..."
  }
}
```

#### ج) الملف الشخصي للمستخدم الحالي
- **الرابط**: `GET /api/auth/me`
- **الاستجابة (200 OK)**: يرجع بيانات المستخدم وعدد ملفاته ومجلداته.

---

### 2. إعدادات تيليجرام الخاصة بالمستخدم (User Telegram Settings)

#### أ) حفظ والتحقق من بيانات تيليجرام
- **الرابط**: `POST /api/settings/telegram`
- **الترويسة**: `Authorization: Bearer <TOKEN>`
- **جسم الطلب (Body)**:
```json
{
  "telegramApiId": "34179091",
  "telegramApiHash": "9279dee1e560da2fd90f771159f97a20",
  "telegramBotToken": "123456789:ABCdefGhIJKlmNoPQRsTUVwxyZ",
  "telegramChannelId": "-1001234567890"
}
```
- **الاستجابة (200 OK)**:
```json
{
  "success": true,
  "message": "تم التحقق من بيانات تيليجرام وتشفيرها وحفظها بنجاح",
  "data": {
    "bot": {
      "id": 123456789,
      "username": "my_user_bot",
      "firstName": "My Storage Bot"
    },
    "channelId": "-1001234567890"
  }
}
```

#### ب) استعراض حالة الإعدادات للمستخدم
- **الرابط**: `GET /api/settings/telegram`
- **الاستجابة (200 OK)**:
```json
{
  "success": true,
  "data": {
    "isConfigured": true,
    "maskedBotToken": "123456...wxyZ",
    "maskedChannelId": "-10012...",
    "maskedApiId": "341***"
  }
}
```

---

### 3. الملفات (Files API - معزولة لكل مستخدم)

#### أ) رفع ملف جديد
- **الرابط**: `POST /api/files/upload`
- **الترويسة**: `Authorization: Bearer <TOKEN>`
- **نوع المحتوى**: `multipart/form-data`
- **الحقول**:
  - `file`: الملف المراد رفعه (حتى 2GB).
  - `parentFolderId` (اختياري): معرّف المجلد الأب التابع لنفس المستخدم.
- **الاستجابة (201 Created)**:
```json
{
  "success": true,
  "message": "تم رفع الملف وحفظ بياناته بنجاح",
  "data": {
    "id": "c1f7b8d4-5e92-4f81-a6e3-82a17684df39",
    "name": "project_backup.zip",
    "size": 104857600,
    "mimeType": "application/zip",
    "telegramFileId": "BQACAgQAAxkBAAICCW...",
    "parentFolderId": null,
    "createdAt": "2026-09-15T20:00:00.000Z"
  }
}
```

#### ب) تنزيل ملف كـ Stream
- **الرابط**: `GET /api/files/:id/download`
- **الترويسة**: `Authorization: Bearer <TOKEN>`
- **الاستجابة**: دفق مباشر (Stream) للملف مع ترويسة التحميل `Content-Disposition` ودعم الأسماء العربية، ويسمح بتنزيل الملفات حتى 2GB.

#### ج) استعراض ملفات ومجلدات المستخدم مع البحث الشامل (PostgreSQL Full-Text Search)
- **الرابط**: `GET /api/files`
- **الترويسة**: `Authorization: Bearer <TOKEN>`
- **Query Params**:
  - `parentFolderId` (اختياري): الفلترة حسب المجلد الحالي (في وضع التصفح العادي).
  - `page` (افتراضياً 1) و `limit` (افتراضياً 20): دعم التصفح والـ Pagination.
  - `search` (اختياري): نص البحث.
- **آلية البحث المتقدمة (FTS Engine)**:
  - عند تمرير `search`: يتم البحث الشامل في جميع ملفات ومجلدات المستخدم عبر كل المجلدات باستخدام عمود `search_vector` المفهرس بـ **GIN Index**.
  - يدعم البحث الجزئي التلقائي (Prefix Matching مثل `proj:*`) وترتيب النتائج بالأكثر تطابقاً وفق خوارزمية **`ts_rank`**.
  - عند ترك `search` فارغاً: يعود النظام إلى وضع التصفح العادي السريع المفلتر بـ `parentFolderId` للحفاظ على أعلى أداء ممكن.
- **الاستجابة (200 OK)**: يرجع المجلدات والملفات المملوكة لهذا المستخدم مع بيانات التصفح `pagination` وتصنيف البحث.

#### د) حذف ملف
- **الرابط**: `DELETE /api/files/:id`
- **الترويسة**: `Authorization: Bearer <TOKEN>`
- **الاستجابة**: حذف الرسالة من قناة المستخدم في تيليجرام وحذف سجل الـ Metadata من قاعدة البيانات.

---

### 4. مشاركة الملفات عبر روابط عامة (OneDrive-style Share via Link)

#### أ) إنشاء رابط مشاركة جديد لملف
- **الرابط**: `POST /api/files/:id/share`
- **الترويسة**: `Authorization: Bearer <TOKEN>`
- **جسم الطلب (Body)**:
```json
{
  "expiresInHours": 24,
  "maxDownloads": 5
}
```
- **الاستجابة (201 Created)**:
```json
{
  "success": true,
  "message": "تم إنشاء رابط المشاركة بنجاح",
  "data": {
    "shareLink": {
      "id": "7b2d5a31-...",
      "fileId": "c1f7b8d4-...",
      "token": "a1f9e2...",
      "expiresAt": "2026-09-16T22:00:00.000Z",
      "createdByUserId": "...",
      "maxDownloads": 5,
      "downloadCount": 0,
      "isRevoked": false,
      "shareUrl": "https://domain.com/share/a1f9e2..."
    },
    "shareUrl": "https://domain.com/share/a1f9e2..."
  }
}
```

#### ب) تنزيل الملف عبر الرابط العام (Public Direct Download)
- **الرابط**: `GET /api/share/:token`
- **الصلاحية**: عام (Public، بدون تسجيل دخول أو JWT)
- **التحقق**:
  - يتأكد من وجود الرابط وصحته (404 Not Found).
  - يتأكد أن الرابط لم يُلغَ يدوياً (`isRevoked: true` -> 410 Gone).
  - يتأكد من عدم انتهاء الصلاحية الزمنية (`expiresAt` -> 410 Gone).
  - يتأكد من عدم تجاوز الحد الأقصى لمرات التنزيل (`downloadCount >= maxDownloads` -> 403 Forbidden).
  - يجلب بيانات تيليجرام لمالك الملف الأصلي ويقوم بتدفق (Stream) الملف للمتصفح/العميل فوراً، مع زيادة `downloadCount`.

#### ج) استعراض روابط المشاركة لملف معين
- **الرابط**: `GET /api/files/:id/shares`
- **الترويسة**: `Authorization: Bearer <TOKEN>`
- **الاستجابة (200 OK)**: مصفوفة بجميع الروابط المُنشأة للملف مع حالة كل رابط (نشط، ملغى، منتهي، عدد التنزيلات).

#### د) إلغاء رابط مشاركة يدوياً
- **الرابط**: `DELETE /api/shares/:shareId`
- **الترويسة**: `Authorization: Bearer <TOKEN>`
- **الاستجابة (200 OK)**: إلغاء صلاحية الرابط فوراً وتعطيله من أي استخدام لاحق.

#### هـ) مهمة مجدولة لتنظيف الروابط المنتهية (Hourly Cron Job)
- تعمل مهمة دورية باستخدام `node-cron` كل ساعة لتنظيف وحذف سجلات روابط المشاركة المنتهية منذ أكثر من 7 أيام من قاعدة البيانات تلقائياً.

---

### 5. المجلدات الوهمية (Virtual Folders API)

#### أ) إنشاء مجلد وهمي
- **الرابط**: `POST /api/folders`
- **جسم الطلب (Body)**:
```json
{
  "name": "مستندات العمل",
  "parentId": null
}
```

#### ب) جلب تفاصيل مجلد
- **الرابط**: `GET /api/folders/:id`

#### ج) حذف مجلد متداخل بالكامل ومحتوياته في تيليجرام
- **الرابط**: `DELETE /api/folders/:id`
- **الترويسة**: `Authorization: Bearer <TOKEN>`
- **آلية العمل**:
  - يجلب كافة الملفات التابعة للمجلد وجميع المجلدات الفرعية منه بشكل متداخل (Recursive).
  - يحذف رسالة كل ملف من قناة تيليجرام الخاصة بالمستخدم عبر البوت، مع تسجيل تحذير والاستمرار في حال تعذر حذف أي رسالة.
  - يحذف المجلد وسجلاته من قاعدة البيانات وتتكفل علاقة `onDelete: Cascade` بحذف السجلات الفرعية.

---

## 🗂️ هيكلية المشروع (Architecture)
```
backend/
├── docker-compose.yml          # حاويات PostgreSQL وسيرفر Telegram Bot API
├── package.json                # التبعيات (bcryptjs, jsonwebtoken, prisma, axios...)
├── tsconfig.json               # إعدادات TypeScript
├── .env.example                # نموذج متغيرات البيئة الآمن بدون بيانات خاصة
├── prisma/
│   └── schema.prisma           # المخطط: User, Folder, File مع العلاقات والتشفير
└── src/
    ├── config/
    │   └── env.ts              # التحقق الصارم من متغيرات البيئة
    ├── lib/
    │   └── prisma.ts           # عميل Prisma Client
    ├── errors/
    │   └── app-error.ts        # معالجة الأخطاء الاحترافية
    ├── utils/
    │   └── crypto.util.ts      # تشفير وفك تشفير البيانات بـ AES-256-GCM
    ├── types/
    │   └── express.d.ts        # توسيع أنواع Express (user, telegramConfig)
    ├── middlewares/
    │   ├── auth.middleware.ts  # التحقق من JWT واستخراج المستخدم
    │   ├── require-telegram.middleware.ts # فك تشفير بيانات تيليجرام لحظياً للطلب
    │   ├── upload.middleware.ts# إعدادات Multer
    │   └── error.middleware.ts # المعالج المركزي للأخطاء
    ├── services/
    │   ├── auth.service.ts     # تسجيل المستخدمين وتوليد JWT
    │   ├── settings.service.ts # التحقق وتشفير بيانات تيليجرام لكل مستخدم
    │   ├── telegram.service.ts # التفاعل المباشر مع Telegram API
    │   ├── file.service.ts     # عمليات الملفات المعزولة لكل مستخدم
    │   └── folder.service.ts   # إدارة المجلدات المعزولة
    ├── controllers/
    │   ├── auth.controller.ts
    │   ├── settings.controller.ts
    │   ├── file.controller.ts
    │   └── folder.controller.ts
    ├── routes/
    │   ├── auth.routes.ts
    │   ├── settings.routes.ts
    │   ├── file.routes.ts
    │   ├── folder.routes.ts
    │   └── index.ts
    └── app.ts
```
