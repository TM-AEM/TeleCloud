# 🚀 دليل بناء ونشر التطبيق عبر GitHub Actions

تم تجهيز مستودع المشروع بملفات عمل آلية (**GitHub Actions Workflows**) تتيح لك بناء ملف التثبيت الخاص بالأندرويد (**APK & AAB**) تلقائياً وتنزيله مباشرة من GitHub دون الحاجة لتثبيت بيئة التطوير على جهازك.

---

## 1️⃣ رفع المشروع إلى مستودعك على GitHub

إذا كنت ترفع المشروع لأول مرة، اتبع الأوامر التالية في مجلد المشروع:

```bash
# 1. تهيئة المستودع وإضافة كافة الملفات
git init
git add .
git commit -m "Initial commit with GitHub Actions CI/CD"

# 2. تغيير اسم الفرع الرئيسي
git branch -M main

# 3. ربط المستودع برابط مستودعك على GitHub
git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO_NAME.git

# 4. رفع الأكواد
git push -u origin main
```

*(يمكنك أيضاً استخدام زر **Push to GitHub** المباشر من قائمة إعدادات AI Studio).*

---

## 2️⃣ كيفية بدء البناء وتنزيل ملف الـ APK

بمجرد رفع الكود، سيبدأ GitHub تلقائياً ببناء التطبيق:

1. افتح صفحة مستودعك على [GitHub.com](https://github.com).
2. اضغط على تبويب **Actions** في الشريط العلوي.
3. ستجد سير العمل باسم **`Build Android APK (Flutter)`** قيد التشغيل ⏳.
4. انتظر حتى يكتمل البناء وتظهر علامة الصح الخضراء ✅.
5. اضغط على العملية المكتملة، وانزل إلى قسم **Artifacts** في أسفل الصفحة:
   - ستجد ملف **`app-release-apk`** (جاهز للتثبيت المباشر على أي هاتف أندرويد).
   - ستجد ملف **`app-release-aab`** (الحزمة المخصصة للنشر على متجر Google Play).

---

## 3️⃣ تشغيل البناء يدوياً (Manual Trigger)

يمكنك طلب بناء APK جديد في أي وقت دون رفع كود جديد:
1. اذهب إلى تبويب **Actions**.
2. اختر من القائمة الجانبية: **`Build Android APK (Flutter)`**.
3. اضغط على زر **`Run workflow`** ثم **`Run workflow`**.

---

## 4️⃣ إنشاء إصدار رسمي تلقائي (Release with Tag)

إذا أردت إنشاء صفحة Release رسمية في GitHub مع روابط تحميل دائمة للـ APK:

```bash
git tag v1.0.0
git push origin v1.0.0
```

سيقوم سير العمل بإنشاء Release في GitHub وإرفاق ملفات `app-release.apk` و `app-release.aab` به تلقائياً.
