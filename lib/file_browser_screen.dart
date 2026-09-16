import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'backup_settings_screen.dart';
import 'share_file_screen.dart';
import 'active_shares_screen.dart';
import 'core/permissions/permission_service.dart';
import 'core/services/auth_service.dart';
import 'file_browser_provider.dart';

/// =========================================================================================
/// [FileBrowserScreen] - واجهة استعراض الملفات ورفع الوسائط وتنزيلها
/// =========================================================================================
///
/// **مقارنة تفصيلية بين نهج التنزيل (Download Approaches Docstring):**
///
/// 1. النهج الأول: الكتابة المباشرة بطلب إذن (MANAGE_EXTERNAL_STORAGE):
///    - **الآلية:** يطلب التطبيق صلاحية All Files Access ويكتب الملفات مباشرة في
///      المسار التقليدي `/storage/emulated/0/Download/...`.
///    - **المشكلة الحاسمة:** جوجل بلاي يرفض فوراً التطبيقات التي تستخدم هذا الإذن ما لم يكن
///      النشاط الجوهري للتطبيق هو إدارة الملفات حصراً. استخدام هذا النهج لتطبيقات السحابة أو
///      تنزيل المستندات يؤدي لحظر التطبيق أو رفض التحديث.
///
/// 2. النهج الثاني: التنزيل في مساحة التطبيق ثم التصدير عبر MediaStore API (الموصى به رسمياً):
///    - **الآلية:**
///      أ) تنزيل الملف وحفظه فوراً في مجلد المستندات الخاص بالتطبيق (`getApplicationDocumentsDirectory`).
///      ب) استخدام `MediaStore API` (أو `media_store_plus`) لنقل الملف إلى مجلد التنزيلات العام للمستخدم.
///    - **المزايا:**
///      - لا يحتاج لأي أذونات في أندرويد 10 فما فوق (API 29+).
///      - متوافق تماماً مع قواعد الخصوصية ومعايير Scoped Storage لمتجر Google Play.
///      - يمنح المستخدم وصولاً كاملاً للملف المنزّل في مجلد Downloads وتطبيقات الطرف الثالث.
/// =========================================================================================

class FileBrowserScreen extends StatefulWidget {
  const FileBrowserScreen({super.key});

  @override
  State<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends State<FileBrowserScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  int _androidSdkVersion = 0;

  @override
  void initState() {
    super.initState();
    _loadAndroidInfo();
  }

  Future<void> _loadAndroidInfo() async {
    final sdk = await PermissionService.instance.getAndroidSdkVersion();
    if (mounted) {
      setState(() {
        _androidSdkVersion = sdk;
      });
    }
  }

  /// اختيار وسائط (صور أو فيديو) ورفعها مع التحقق الصارم من الأذونات أولاً
  Future<void> _pickAndUploadMedia() async {
    // 1. طلب إذن الوسائط المناسب حسب إصدار أندرويد
    final bool hasPermission =
        await PermissionService.instance.requestMediaPermission(context: context);

    // 2. إذا تم رفض الإذن، عرض رسالة واضحة والتوقف فوراً بدون فتح المعرض
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            content: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'تم رفض إذن الوصول للوسائط. لا يمكن اختيار ورفع الملفات بدون منح الإذن.',
                  ),
                ),
              ],
            ),
          ),
        );
      }
      return;
    }

    // 3. الإذن ممنوح: فتح منتقي الصور/الفيديوهات
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (pickedFile != null && mounted) {
        final file = File(pickedFile.path);
        await context.read<FileBrowserProvider>().uploadFile(file);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.green.shade700,
              behavior: SnackBarBehavior.floating,
              content: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('تم اختيار "${pickedFile.name}" بنجاح وتمت معالجة الرفع.'),
                  ),
                ],
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[FileBrowserScreen] Pick media error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء اختيار الملف: $e')),
        );
      }
    }
  }

  /// اختيار ملف عام مستندات/PDF وغيرها
  Future<void> _pickAnyFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.any,
      );

      if (result != null && result.files.single.path != null && mounted) {
        final file = File(result.files.single.path!);
        await context.read<FileBrowserProvider>().uploadFile(
              file,
              customName: result.files.single.name,
            );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.green.shade700,
              behavior: SnackBarBehavior.floating,
              content: Text('تم اختيار الملف: ${result.files.single.name}'),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[FileBrowserScreen] FilePicker error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FileBrowserProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'مستعرض التخزين السحابي',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_sync_rounded),
            tooltip: 'إعدادات النسخ الاحتياطي التلقائي',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const BackupSettingsScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.security_outlined),
            tooltip: 'فحص أذونات التخزين الشاملة',
            onPressed: () async {
              await PermissionService.instance.requestStoragePermission(
                context: context,
                reason:
                  'توضيح تجريبي: هذا فحص لطلب إذن إدارة الملفات الشاملة (MANAGE_EXTERNAL_STORAGE). يُرجى ملاحظة أن MediaStore API يغني عنه تماماً!',
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            tooltip: 'تسجيل الخروج',
            onPressed: () {
              showDialog(
                context: context,
                builder: (dialogCtx) => Directionality(
                  textDirection: TextDirection.rtl,
                  child: AlertDialog(
                    title: const Text('تسجيل الخروج'),
                    content: const Text('هل أنت متأكد من رغبتك في تسجيل الخروج من حسابك؟'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogCtx),
                        child: const Text('إلغاء'),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () {
                          Navigator.pop(dialogCtx);
                          context.read<AuthService>().logout();
                        },
                        child: const Text('تسجيل الخروج'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
            // بطاقة اختصار للنسخ الاحتياطي التلقائي
            InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BackupSettingsScreen(),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.indigo.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.backup_rounded, color: Colors.indigo.shade700, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'النسخ الاحتياطي التلقائي للصور والفيديوهات',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Colors.indigo.shade900,
                            ),
                          ),
                          Text(
                            'جدولة رفع وسائط الجهاز تلقائياً في الخلفية عبر WorkManager',
                            style: TextStyle(fontSize: 11, color: Colors.indigo.shade700),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios, size: 14, color: Colors.indigo.shade700),
                  ],
                ),
              ),
            ),
            // بطاقة توضيحية لنظام الأذونات النشط
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.verified_user_rounded, color: Colors.blue.shade700, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _androidSdkVersion >= 33
                              ? 'أندرويد 13+ (API $_androidSdkVersion): أذونات الوسائط المخصصة مفعلة'
                              : 'أندرويد (API $_androidSdkVersion): Scoped Storage و MediaStore API نشط',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.blue.shade900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'التنزيل يتم عبر مساحة التطبيق المعزولة ثم MediaStore API لضمان قبول متجر Google Play.',
                          style: TextStyle(fontSize: 11, color: Colors.blue.shade800),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // شريط حالة التنزيل إن وجد
            if (provider.isDownloading)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          provider.statusMessage ?? 'جارٍ التنزيل...',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber.shade900,
                          ),
                        ),
                        Text(
                          '${(provider.downloadProgress * 100).toInt()}%',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: provider.downloadProgress,
                      backgroundColor: Colors.amber.shade100,
                      color: Colors.amber.shade700,
                    ),
                  ],
                ),
              ),

            // قائمة الملفات
            Expanded(
              child: provider.files.isEmpty
                  ? const Center(
                      child: Text('لا توجد ملفات حالياً. اضغط على الزر أدناه للرفع.'),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      itemCount: provider.files.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, index) {
                        final file = provider.files[index];
                        return _buildFileTile(file, provider);
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: Directionality(
        textDirection: TextDirection.rtl,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FloatingActionButton.extended(
              heroTag: 'pick_doc',
              onPressed: _pickAnyFile,
              icon: const Icon(Icons.attach_file),
              label: const Text('رفع مستند'),
              backgroundColor: Colors.indigo.shade600,
              foregroundColor: Colors.white,
            ),
            const SizedBox(width: 12),
            FloatingActionButton.extended(
              heroTag: 'pick_media',
              onPressed: _pickAndUploadMedia,
              icon: const Icon(Icons.add_photo_alternate),
              label: const Text('رفع وسائط'),
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileTile(CloudFileItem file, FileBrowserProvider provider) {
    IconData iconData = Icons.insert_drive_file;
    Color iconColor = Colors.grey.shade700;

    if (file.mimeType.startsWith('image/')) {
      iconData = Icons.image;
      iconColor = Colors.purple;
    } else if (file.mimeType.startsWith('video/')) {
      iconData = Icons.video_collection;
      iconColor = Colors.deepOrange;
    } else if (file.mimeType.contains('pdf')) {
      iconData = Icons.picture_as_pdf;
      iconColor = Colors.red.shade700;
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      onTap: () => _showFileOptions(context, file, provider),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(iconData, color: iconColor),
      ),
      title: Text(
        file.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Text(
        '${file.readableSize} • ${file.mimeType}',
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.share_outlined, color: Colors.indigo),
            tooltip: 'مشاركة عبر رابط',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ShareFileScreen(
                    fileId: file.id,
                    fileName: file.name,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.download_rounded, color: Colors.blueAccent),
            tooltip: 'تنزيل لمجلد التنزيلات (Downloads)',
            onPressed: provider.isDownloading
                ? null
                : () async {
                    final ok = await provider.downloadFileToDownloads(
                      fileItem: file,
                      context: context,
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          behavior: SnackBarBehavior.floating,
                          backgroundColor: ok ? Colors.green.shade700 : Colors.red.shade700,
                          content: Text(provider.statusMessage ?? 'اكتملت العملية.'),
                        ),
                      );
                    }
                  },
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.grey),
            tooltip: 'خيارات إضافية',
            onPressed: () => _showFileOptions(context, file, provider),
          ),
        ],
      ),
    );
  }

  /// فتح قائمة خيارات الملف (file_options bottom sheet) مع خيار "مشاركة عبر رابط" زي OneDrive
  void _showFileOptions(BuildContext context, CloudFileItem file, FileBrowserProvider provider) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // رأس القائمة
                  ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.indigo,
                      child: Icon(Icons.insert_drive_file, color: Colors.white),
                    ),
                    title: Text(
                      file.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text('${file.readableSize} • ${file.mimeType}'),
                  ),
                  const Divider(),

                  // 1. ميزة المشاركة عبر رابط (Share via Link)
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.link_rounded, color: Colors.indigo),
                    ),
                    title: const Text('مشاركة عبر رابط (OneDrive style)'),
                    subtitle: const Text('إنشاء رابط عام محدد الصلاحية قابل للمشاركة والنسخ'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ShareFileScreen(
                            fileId: file.id,
                            fileName: file.name,
                          ),
                        ),
                      );
                    },
                  ),

                  // 2. إدارة الروابط النشطة
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.list_alt_rounded, color: Colors.teal),
                    ),
                    title: const Text('إدارة روابط المشاركة النشطة'),
                    subtitle: const Text('استعراض الروابط الحالية وإلغاؤها يدوياً'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ActiveSharesScreen(
                            fileId: file.id,
                            fileName: file.name,
                          ),
                        ),
                      );
                    },
                  ),

                  // 3. تنزيل الملف
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.download_rounded, color: Colors.blueAccent),
                    ),
                    title: const Text('تنزيل الملف للجهاز'),
                    subtitle: const Text('حفظ في مجلد التنزيلات عبر MediaStore API'),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final ok = await provider.downloadFileToDownloads(
                        fileItem: file,
                        context: context,
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: ok ? Colors.green.shade700 : Colors.red.shade700,
                            content: Text(provider.statusMessage ?? 'اكتملت العملية.'),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

