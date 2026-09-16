import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

/// ==============================================================================
/// [BackupWorker] - خدمة إدارة وتنفيذ النسخ الاحتياطي التلقائي للصور والفيديوهات
/// ==============================================================================
///
/// **قيود وإرشادات العمل على نظام أندرويد (Android WorkManager Constraints):**
///
/// 1. الحد الأدنى للتردد الدوري (Minimum Periodic Interval):
///    - نظام أندرويد عبر مكتبة WorkManager يفرض حداً أدنى صارماً قدره 15 دقيقة
///      (`PeriodicWorkRequest.MIN_PERIODIC_INTERVAL_MILLIS = 15 * 60 * 1000`).
///    - أي قيمة أقل من 15 دقيقة يتم تصعيدها إجبارياً من قبل نظام التشغيل إلى 15 دقيقة
///      لتجنب استنزاف بطارية الجهاز وموارده.
///
/// 2. عدم دقة التوقيت الدقيق (Inexact Scheduling & Doze Mode):
///    - نظام أندرويد لا يضمن تشغيل المهمة في اللحظة المحددة بالثانية.
///    - تقوم آلية Doze Mode و App Standby بتجميع مهام النظام وتنفيذها في نوافذ صيانة (Maintenance Windows)،
///      مما قد يؤدي لتأخير بدء المهمة عند سكون الجهاز أو انخفاض مستوى البطارية.
///
/// 3. خيار "فوري عند إضافة أي ملف جديد":
///    - لا يسمح نظام أندرويد في الخلفية بمراقبة مجلدات الوسائط عبر `ContentObserver` بشكل دائم
///      دون وجود Foreground Service مستمرة مع إشعار دائم، مما يستهلك طاقة البطارية ويعرض التطبيق
///      لإيقاف المعالجة من قبل النظام.
///    - **الحل العملي المطبق:** نسجل مهمة One-off Task تعمل فوراً أو بأقرب فرصة عند تفاعل المستخدم،
///      مع جدولة دورية بأقل فترة يسمح بها النظام (15 دقيقة)، مع عرض توضيح شفاف للمستخدم
///      في واجهة الإعدادات.
/// ==============================================================================

const String kBackupPeriodicTask = "com.cloudstorage.backup.periodic";
const String kBackupOneOffTask = "com.cloudstorage.backup.oneoff";

// مفاتيح SharedPreferences
const String kPrefBackupEnabled = "backup_enabled";
const String kPrefBackupFrequency = "backup_frequency"; // 'hourly', 'six_hours', 'daily', 'immediate'
const String kPrefBackupWifiOnly = "backup_wifi_only";
const String kPrefBackupDailyTime = "backup_daily_time"; // 'HH:mm'
const String kPrefBackupAlbums = "backup_selected_albums"; // List<String> of album IDs
const String kPrefLastSyncTimestamp = "backup_last_sync_timestamp";
const String kPrefUploadedFileHashes = "backup_uploaded_file_hashes"; // List<String>
const String kPrefTotalUploadedCount = "backup_total_uploaded_count";
const String kPrefLastSyncStatus = "backup_last_sync_status";
const String kPrefApiBaseUrl = "backup_api_base_url";
const String kPrefAuthToken = "backup_auth_token";

/// نقطة الدخول الثابتة المنفصلة لتنفيذ مهام الخلفية لـ WorkManager
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint("[BackupWorker] WorkManager task started: $task");
    WidgetsFlutterBinding.ensureInitialized();

    try {
      final worker = BackupWorker();
      final result = await worker.executeBackupProcess(isManual: false);
      debugPrint("[BackupWorker] Backup process finished with success: $result");
      return Future.value(result);
    } catch (e, stack) {
      debugPrint("[BackupWorker] Fatal error in callbackDispatcher: $e\n$stack");
      return Future.value(false);
    }
  });
}

class BackupWorker {
  static final BackupWorker _instance = BackupWorker._internal();
  factory BackupWorker() => _instance;
  BackupWorker._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isNotificationInitialized = false;

  /// تهيئة WorkManager ونظام الإشعارات المحلية
  static Future<void> initialize() async {
    WidgetsFlutterBinding.ensureInitialized();

    // 1. تهيئة WorkManager
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: kDebugMode,
    );

    // 2. تهيئة الإشعارات المحلية
    await BackupWorker().initNotifications();
  }

  /// تهيئة إشعارات النظام
  Future<void> initNotifications() async {
    if (_isNotificationInitialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _notificationsPlugin.initialize(initSettings);
    _isNotificationInitialized = true;
  }

  /// إرسال إشعار محلي للمستخدم بنتيجة النسخ الاحتياطي
  Future<void> showNotification({
    required String title,
    required String body,
    int id = 1001,
  }) async {
    await initNotifications();

    const androidDetails = AndroidNotificationDetails(
      'cloud_backup_channel',
      'النسخ الاحتياطي للصور والفيديوهات',
      channelDescription: 'إشعارات تقدم واكتمال النسخ الاحتياطي التلقائي',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const notificationDetails = NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      id,
      title,
      body,
      notificationDetails,
    );
  }

  /// جدولة أو إلغاء مهمة النسخ الاحتياطي بناءً على الإعدادات
  Future<void> scheduleBackupTask({
    required bool enabled,
    required String frequency,
    required bool wifiOnly,
    TimeOfDay? dailyTime,
  }) async {
    // إلغاء المهام السابقة أولاً لتجنب التكرار
    await Workmanager().cancelByUniqueName(kBackupPeriodicTask);
    await Workmanager().cancelByUniqueName(kBackupOneOffTask);

    if (!enabled) {
      debugPrint("[BackupWorker] Backup disabled. All background tasks cancelled.");
      return;
    }

    final networkType =
        wifiOnly ? NetworkType.unmetered : NetworkType.connected;

    final constraints = Constraints(
      networkType: networkType,
      requiresBatteryNotLow: true,
      requiresStorageNotLow: true,
    );

    Duration frequencyDuration;
    Duration? initialDelay;

    switch (frequency) {
      case 'hourly':
        frequencyDuration = const Duration(hours: 1);
        break;
      case 'six_hours':
        frequencyDuration = const Duration(hours: 6);
        break;
      case 'daily':
        frequencyDuration = const Duration(hours: 24);
        // حساب الوقت المتبقي حتى موعد التشغيل المحدد في اليوم
        if (dailyTime != null) {
          final now = DateTime.now();
          var target = DateTime(
            now.year,
            now.month,
            now.day,
            dailyTime.hour,
            dailyTime.minute,
          );
          if (target.isBefore(now)) {
            target = target.add(const Duration(days: 1));
          }
          initialDelay = target.difference(now);
        }
        break;
      case 'immediate':
      default:
        // الحد الأدنى الرسمي لـ PeriodicWorkRequest في أندرويد هو 15 دقيقة
        frequencyDuration = const Duration(minutes: 15);
        initialDelay = const Duration(seconds: 10);
        break;
    }

    debugPrint(
      "[BackupWorker] Scheduling periodic task: freq=${frequencyDuration.inMinutes}m, wifiOnly=$wifiOnly, delay=${initialDelay?.inMinutes ?? 0}m",
    );

    await Workmanager().registerPeriodicTask(
      kBackupPeriodicTask,
      kBackupPeriodicTask,
      frequency: frequencyDuration,
      initialDelay: initialDelay ?? Duration.zero,
      constraints: constraints,
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );

    // إذا كان الخيار "فوري"، نشغّل أيضاً One-off Task مبكرة لتبدأ المزامنة مباشرة
    if (frequency == 'immediate') {
      await Workmanager().registerOneOffTask(
        "${kBackupOneOffTask}_immediate",
        kBackupOneOffTask,
        initialDelay: const Duration(seconds: 5),
        constraints: constraints,
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );
    }
  }

  /// تنفيذ عملية النسخ الاحتياطي (تعمل في الخلفية أو يدوياً عبر زر التشغيل الآن)
  Future<bool> executeBackupProcess({
    bool isManual = false,
    Function(int current, int total)? onProgress,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final isEnabled = prefs.getBool(kPrefBackupEnabled) ?? false;
    if (!isEnabled && !isManual) {
      debugPrint("[BackupWorker] Backup is disabled. Aborting.");
      return true;
    }

    final selectedAlbumIds =
        prefs.getStringList(kPrefBackupAlbums) ?? <String>[];
    final lastSyncTimestamp =
        prefs.getInt(kPrefLastSyncTimestamp) ?? 0;
    final uploadedHashes =
        (prefs.getStringList(kPrefUploadedFileHashes) ?? <String>[]).toSet();
    final baseUrl =
        prefs.getString(kPrefApiBaseUrl) ?? 'http://10.0.2.2:5000';
    final token = prefs.getString(kPrefAuthToken) ?? '';

    // طلب أو التحقق من صلاحية الوصول للوسائط
    final permissionState = await PhotoManager.requestPermissionExtend();
    if (!permissionState.isAuth && !permissionState.hasAccess) {
      debugPrint("[BackupWorker] Permission not granted to access media.");
      await _recordSyncStatus(
        prefs,
        success: false,
        message: "لم يتم منح إذن الوصول للوسائط",
        uploadedDelta: 0,
      );
      return false;
    }

    // جلب جميع ألبومات ومجلدات الوسائط (Camera, Screenshots, WhatsApp, إلخ)
    final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      hasAll: true,
    );

    // تصفية الألبومات وفق اختيار المستخدم (إذا لم يحدد شيئاً، نتصفح المجلد الافتراضي الرئيسي)
    final targetAlbums = albums.where((album) {
      if (selectedAlbumIds.isEmpty) return album.isAll;
      return selectedAlbumIds.contains(album.id);
    }).toList();

    debugPrint(
      "[BackupWorker] Scanning ${targetAlbums.length} albums. Last sync: ${DateTime.fromMillisecondsSinceEpoch(lastSyncTimestamp)}",
    );

    final List<AssetEntity> newAssets = [];

    for (final album in targetAlbums) {
      final totalInAlbum = await album.assetCountAsync;
      if (totalInAlbum == 0) continue;

      // قراءة أول 100 عنصر تم إضافتها حديثاً
      final assets = await album.getAssetListRange(
        start: 0,
        end: totalInAlbum > 100 ? 100 : totalInAlbum,
      );

      for (final asset in assets) {
        final createMillis = asset.createDateTime.millisecondsSinceEpoch;
        final modifiedMillis = asset.modifiedDateTime.millisecondsSinceEpoch;
        final assetTime = modifiedMillis > 0 ? modifiedMillis : createMillis;

        // التحقق مما إذا كان الملف أحدث من آخر وقت مزامنة
        if (assetTime > lastSyncTimestamp || lastSyncTimestamp == 0) {
          newAssets.add(asset);
        }
      }
    }

    debugPrint("[BackupWorker] Found ${newAssets.length} candidate assets.");

    int successCount = 0;
    int failedCount = 0;
    int skippedCount = 0;

    for (int i = 0; i < newAssets.length; i++) {
      final asset = newAssets[i];
      onProgress?.call(i + 1, newAssets.length);

      try {
        final file = await asset.originFile;
        if (file == null || !await file.exists()) {
          skippedCount++;
          continue;
        }

        // إنشاء Hash للملف أو معرّف فريد يعتمد على المحتوى والحجم
        final fileKey = await _generateFileHash(file, asset.id);

        // إذا كان الملف قد رُفِع سابقاً بنجاح، نتخطاه
        if (uploadedHashes.contains(fileKey)) {
          skippedCount++;
          continue;
        }

        // محاولة رفع الملف عبر API
        final uploadOk = await _uploadFileToBackend(
          file: file,
          fileName: asset.title ?? file.path.split('/').last,
          mimeType: asset.mimeType ?? (asset.type == AssetType.video ? 'video/mp4' : 'image/jpeg'),
          baseUrl: baseUrl,
          token: token,
        );

        if (uploadOk) {
          // نسجله كـ "تم رفعه" فقط بعد نجاح العملية تماماً
          uploadedHashes.add(fileKey);
          successCount++;
        } else {
          // فشل الرفع: يظل في قائمة "لم يُرفع بعد" لإعادة المحاولة في الدورة القادمة
          failedCount++;
        }
      } catch (e) {
        debugPrint("[BackupWorker] Error uploading asset ${asset.id}: $e");
        failedCount++;
      }
    }

    // حفظ التحديثات في SharedPreferences
    final nowMillis = DateTime.now().millisecondsSinceEpoch;
    await prefs.setInt(kPrefLastSyncTimestamp, nowMillis);
    await prefs.setStringList(kPrefUploadedFileHashes, uploadedHashes.toList());

    final prevTotal = prefs.getInt(kPrefTotalUploadedCount) ?? 0;
    final newTotal = prevTotal + successCount;
    await prefs.setInt(kPrefTotalUploadedCount, newTotal);

    await _recordSyncStatus(
      prefs,
      success: failedCount == 0,
      message: "تم رفع $successCount بنجاح، وفشل $failedCount، وتخطي $skippedCount",
      uploadedDelta: successCount,
    );

    // إرسال إشعار محلي للمستخدم بالنتيجة
    if (successCount > 0 || failedCount > 0 || isManual) {
      final String notificationTitle = failedCount == 0
          ? 'اكتمل النسخ الاحتياطي بنجاح'
          : 'اكتمل النسخ الاحتياطي مع بعض الأخطاء';

      final String notificationBody = successCount > 0
          ? 'تم رفع $successCount ملف بنجاح${failedCount > 0 ? "، وفشل $failedCount ملف سيتم إعادة محاولتها لاحقاً." : "."}'
          : (failedCount > 0
              ? 'تعذر رفع $failedCount ملف. يرجى التحقق من اتصال الشبكة.'
              : 'لم توجد ملفات جديدة بحاجة للنسخ الاحتياطي.');

      await showNotification(
        title: notificationTitle,
        body: notificationBody,
      );
    }

    return failedCount == 0;
  }

  /// رفع الملف عبر Multipart POST /files/upload
  Future<bool> _uploadFileToBackend({
    required File file,
    required String fileName,
    required String mimeType,
    required String baseUrl,
    required String token,
  }) async {
    try {
      final uploadUri = Uri.parse('$baseUrl/api/files/upload');
      final request = http.MultipartRequest('POST', uploadUri);

      if (token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      final multipartFile = await http.MultipartFile.fromPath(
        'file',
        file.path,
        filename: fileName,
      );
      request.files.add(multipartFile);

      final response = await request.send().timeout(const Duration(seconds: 45));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return true;
      } else {
        debugPrint(
          "[BackupWorker] Upload API responded with status ${response.statusCode}",
        );
        // في حال تشغيل بيئة محلية دون سيرفر نشط، نعتبر المحاكاة ناجحة لتجربة الـ UI
        // لكن لو وجد خادم ورفض، يعود false لإعادة المحاولة
        return false;
      }
    } catch (e) {
      debugPrint("[BackupWorker] Network/Upload error: $e");
      // لو كان الجهاز غير متصل بالخادم المحلي حالياً (مثلاً في اختبار التطبيق بدون سيرفر خلفي)،
      // نتيح للمستخدم رؤية تجربة المزامنة إذا رغب:
      return false;
    }
  }

  /// توليد Hash فريد للملف
  Future<String> _generateFileHash(File file, String assetId) async {
    try {
      final length = await file.length();
      // للتسريع مع الملفات الكبيرة: دمج الحجم مع أول 4096 بايت واسم ومعرّف الملف
      final stream = file.openRead(0, 4096);
      final bytes = await stream.expand((chunk) => chunk).toList();
      final digest = md5.convert([...bytes, ...utf8.encode(assetId), ...utf8.encode(length.toString())]);
      return "${assetId}_$digest";
    } catch (_) {
      return "${assetId}_${file.path}";
    }
  }

  Future<void> _recordSyncStatus(
    SharedPreferences prefs, {
    required bool success,
    required String message,
    required int uploadedDelta,
  }) async {
    final statusMap = {
      'timestamp': DateTime.now().toIso8601String(),
      'success': success,
      'message': message,
      'uploadedDelta': uploadedDelta,
    };
    await prefs.setString(kPrefLastSyncStatus, jsonEncode(statusMap));
  }
}
