import 'dart:io';
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// ==============================================================================
/// دليل التعامل مع أذونات التخزين والوسائط على أندرويد (Permissions Architecture)
/// ==============================================================================
///
/// **مقارنة بين النهجين للتعامل مع مجلد التنزيلات (Downloads) والوسائط:**
///
/// 1. النهج الأول: استخدام إذن إدارة الملفات الشاملة (MANAGE_EXTERNAL_STORAGE)
///    - **كيف يعمل:** يمنح التطبيق صلاحية All Files Access للوصول والقراءة والكتابة
///      المباشرة في أي مسار عبر كود نظام الملفات التقليدي `File('/storage/emulated/0/Download/file.txt')`.
///    - **المميزات:** سهل تقنياً ولا يتطلب كتابة كود مخصص لـ MediaStore أو SAF.
///    - **العيوب وسياسة متجر جوجل (Google Play Policy):**
///      ترفض شركة Google بشكل قاطع قبول التطبيقات التي تطلب هذا الإذن إلا إذا كان
///      النشاط الأساسي للتطبيق (Core App Functionality) يندرج تحت فئات محددة جداً:
///      (File Manager، Document Backup، Antivirus). تطبيقات التخزين السحابي أو التنزيل
///      العادية تتعرض للرفض الفوري أو الإزالة من المتجر إذا استخدمت هذا الإذن!
///
/// 2. النهج الثاني: استخدام مساحة التطبيق الخاصة ثم النسخ عبر MediaStore API أو SAF
///    - **كيف يعمل:**
///      أ) يحفظ التطبيق الملف أولاً في مساحته الخاصة غير المحمية بأذونات:
///         `getApplicationDocumentsDirectory()` أو `getExternalStorageDirectory()`.
///      ب) ثم ينسخ الملف إلى مجلد Downloads العام عبر MediaStore API (باستخدام ContentResolver
///         أو حزمة مثل media_store_plus) أو عبر Storage Access Framework (SAF).
///    - **المميزات:**
///      - لا يحتاج لأي أذونات runtime إطلاقاً على أندرويد 10 فما فوق (API 29+).
///      - متوافق تماماً بنسبة 100% مع سياسات متجر Google Play ويجتاز المراجعة بسلاسة.
///      - يمنع تعريض أمان جهاز المستخدم للخطر ويحترم معيار Scoped Storage الحديث.
///
/// **تدرج أذونات الوسائط حسب إصدار أندرويد:**
/// - **Android 13+ (API 33+):** تم تقسيم صلاحية Storage إلى أذونات محددة:
///   `READ_MEDIA_IMAGES` (الصور)، `READ_MEDIA_VIDEO` (الفيديوهات)، `READ_MEDIA_AUDIO` (الصوتيات).
/// - **Android 10 - 12 (API 29 - 32):** إذن `READ_EXTERNAL_STORAGE` فقط للقراءة إذا لزم الأمر،
///   بينما الكتابة في المجلدات العامة للملفات الخاصة بالتطبيق لا تحتاج أذونات عبر MediaStore.
/// - **Android 9 فما دون (API <= 28):** يحتاج إذن `READ_EXTERNAL_STORAGE` و `WRITE_EXTERNAL_STORAGE`.
/// ==============================================================================

class PermissionService {
  PermissionService._();
  static final PermissionService instance = PermissionService._();

  final DeviceInfoPlugin _deviceInfoPlugin = DeviceInfoPlugin();

  /// إرجاع رقم إصدار أندرويد (SDK_INT) الحالي
  Future<int> getAndroidSdkVersion() async {
    if (!Platform.isAndroid) return 0;
    try {
      final androidInfo = await _deviceInfoPlugin.androidInfo;
      return androidInfo.version.sdkInt;
    } catch (e) {
      debugPrint('[PermissionService] Error getting Android SDK version: $e');
      return 0;
    }
  }

  /// طلب إذن الوصول للوسائط (Media Permission) متوافق مع كافة الإصدارات:
  /// - على Android 13+ (API 33+): يطلب Permission.photos و Permission.videos
  /// - على الإصدارات الأقدم (< 33): يطلب Permission.storage
  Future<bool> requestMediaPermission({BuildContext? context}) async {
    if (!Platform.isAndroid) return true;

    final sdkInt = await getAndroidSdkVersion();

    if (sdkInt >= 33) {
      // أندرويد 13 فأعلى: نطلب صور وفيديوهات منفصلة
      final photosGranted = await checkAndRequestPermission(
        Permission.photos,
        context: context,
        rationaleMessage:
            'يحتاج التطبيق لإذن الوصول إلى الصور لتتمكن من اختيارها ورفعها.',
      );

      final videosGranted = await checkAndRequestPermission(
        Permission.videos,
        context: context,
        rationaleMessage:
            'يحتاج التطبيق لإذن الوصول إلى الفيديو لتتمكن من اختياره ورفعه.',
      );

      return photosGranted || videosGranted;
    } else {
      // أندرويد 12 فما دون: نطلب إذن التخزين الشامل
      return await checkAndRequestPermission(
        Permission.storage,
        context: context,
        rationaleMessage:
            'يحتاج التطبيق لإذن الوصول إلى وحدة التخزين لاختيار الملفات والوسائط ورفعها.',
      );
    }
  }

  /// طلب إذن التخزين الشامل (MANAGE_EXTERNAL_STORAGE)
  /// يُستخدم فقط إذا كان التطبيق يحتاج للكتابة المباشرة في مجلد Download العام دون MediaStore
  /// وينبه المستخدم أولاً عبر Dialog بأنه سيتم تحويله إلى صفحة إعدادات النظام للموافقة
  Future<bool> requestStoragePermission({
    required BuildContext context,
    String? reason,
  }) async {
    if (!Platform.isAndroid) return true;

    final sdkInt = await getAndroidSdkVersion();

    // في أندرويد 10 فما دون، يكفي إذن WRITE_EXTERNAL_STORAGE
    if (sdkInt < 30) {
      return await checkAndRequestPermission(
        Permission.storage,
        context: context,
        rationaleMessage:
            reason ?? 'يحتاج التطبيق لصلاحية التخزين لحفظ الملفات في مجلد التنزيلات.',
      );
    }

    // في أندرويد 11+ (API 30+)، الوصول المباشر يحتاج MANAGE_EXTERNAL_STORAGE
    final currentStatus = await Permission.manageExternalStorage.status;
    if (currentStatus.isGranted) {
      return true;
    }

    // عرض توضيح للمستخدم قبل توجيهه للإعدادات
    final bool? userAgreed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.folder_special, color: Colors.orange),
            SizedBox(width: 8),
            Text('صلاحية إدارة الملفات'),
          ],
        ),
        content: Text(
          reason ??
              'للكتابة المباشرة في مجلد التنزيلات العام بدون وسيط، يتطلب نظام أندرويد تفعيل صلاحية "الوصول إلى جميع الملفات".\n\n'
              'سيتم نقلك الآن إلى إعدادات النظام لتفعيل هذا الإذن للتطبيق يدويًا.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('الانتقال للإعدادات'),
          ),
        ],
      ),
    );

    if (userAgreed != true) return false;

    // طلب الإذن (والذي يفتح صفحة إعدادات النظام تلقائياً لهذا الإذن في أندرويد 11+)
    final result = await Permission.manageExternalStorage.request();
    if (result.isGranted) {
      return true;
    }

    // لو لم يتم منحه، نقوم بفتح الإعدادات مباشرة
    await openAppSettings();
    // إعادة التحقق بعد العودة
    return await Permission.manageExternalStorage.isGranted;
  }

  /// دالة عامة لفحص وطلب أي إذن:
  /// 1. تتحقق من الحالة الحالية أولاً (Granted, Denied, PermanentlyDenied).
  /// 2. تطلب الإذن إذا كان مرفوضاً مؤقتاً.
  /// 3. تعرض Dialog مخصص وتفتح إعدادات النظام إذا كان مرفوضاً نهائياً (PermanentlyDenied).
  Future<bool> checkAndRequestPermission(
    Permission permission, {
    BuildContext? context,
    String? rationaleMessage,
  }) async {
    final status = await permission.status;

    // أ) الإذن ممنوح بالفعل
    if (status.isGranted || status.isLimited) {
      return true;
    }

    // ب) الإذن مرفوض نهائياً (Permanently Denied) - لا يمكن إظهار نافذة النظام المنبثقة
    if (status.isPermanentlyDenied || status.isRestricted) {
      if (context != null && context.mounted) {
        await _showPermanentlyDeniedDialog(
          context,
          permission: permission,
          rationaleMessage: rationaleMessage,
        );
      }
      return false;
    }

    // ج) الإذن مرفوض أو لم يُطلب بعد - نطلب الإذن من النظام
    final requestResult = await permission.request();

    if (requestResult.isGranted || requestResult.isLimited) {
      return true;
    }

    // د) إذا تم رفضه نهائياً بعد المحاولة الجديدة
    if (requestResult.isPermanentlyDenied) {
      if (context != null && context.mounted) {
        await _showPermanentlyDeniedDialog(
          context,
          permission: permission,
          rationaleMessage: rationaleMessage,
        );
      }
    }

    return false;
  }

  /// عرض Dialog تنبيهي عند رفض الإذن بشكل نهائي مع زر لفتح إعدادات التطبيق
  Future<void> _showPermanentlyDeniedDialog(
    BuildContext context, {
    required Permission permission,
    String? rationaleMessage,
  }) async {
    final permissionName = _getReadablePermissionName(permission);

    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 28),
            SizedBox(width: 8),
            Text('الإذن مطلوب للمتابعة'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              rationaleMessage ??
                  'تم تعطيل إذن ($permissionName) بشكل دائم. لتتمكن من استخدام هذه الميزة، يرجى تفعيل الإذن يدويًا من إعدادات التطبيق.',
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 12),
            const Text(
              'الخطوات:\n1. اضغط "فتح الإعدادات" أدناه.\n2. اختر "الأذونات" (Permissions).\n3. قم بتفعيل الإذن المطلوب.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.settings, size: 18),
            label: const Text('فتح الإعدادات'),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await openAppSettings();
            },
          ),
        ],
      ),
    );
  }

  /// تحويل كائن الإذن إلى اسم مقروء ومفهوم للمستخدم
  String _getReadablePermissionName(Permission permission) {
    if (permission == Permission.photos) return 'الصور';
    if (permission == Permission.videos) return 'مقاطع الفيديو';
    if (permission == Permission.audio) return 'الملفات الصوتية';
    if (permission == Permission.storage) return 'وحدة التخزين';
    if (permission == Permission.manageExternalStorage) return 'إدارة كافة الملفات';
    return permission.toString();
  }
}
