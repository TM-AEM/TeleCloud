import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/backup/backup_worker.dart';
import 'core/permissions/permission_service.dart';

class AlbumInfo {
  final String id;
  final String name;
  final int count;
  final bool isAll;

  AlbumInfo({
    required this.id,
    required this.name,
    required this.count,
    this.isAll = false,
  });
}

class BackupSettingsScreen extends StatefulWidget {
  const BackupSettingsScreen({super.key});

  @override
  State<BackupSettingsScreen> createState() => _BackupSettingsScreenState();
}

class _BackupSettingsScreenState extends State<BackupSettingsScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isManualBackingUp = false;
  String? _manualProgressMessage;

  // إعدادات النسخ الاحتياطي
  bool _isBackupEnabled = false;
  String _frequency = 'hourly'; // 'immediate', 'hourly', 'six_hours', 'daily'
  TimeOfDay _dailyTime = const TimeOfDay(hour: 2, minute: 0);
  bool _isWifiOnly = true;
  final Set<String> _selectedAlbumIds = {};

  // قائمة ألبومات الجهاز المكتشفة
  List<AlbumInfo> _availableAlbums = [];

  // إحصائيات وحالة المزامنة
  DateTime? _lastSyncDate;
  int _totalUploadedCount = 0;
  String? _lastSyncStatusMessage;
  bool _lastSyncSuccess = true;

  // إعدادات الخادم
  late TextEditingController _serverUrlController;

  @override
  void initState() {
    super.initState();
    _serverUrlController = TextEditingController(text: 'http://10.0.2.2:5000');
    _loadAllSettings();
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    super.dispose();
  }

  /// تحميل كافة الإعدادات وسجل المزامنة من SharedPreferences
  Future<void> _loadAllSettings() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();

    _isBackupEnabled = prefs.getBool(kPrefBackupEnabled) ?? false;
    _frequency = prefs.getString(kPrefBackupFrequency) ?? 'hourly';
    _isWifiOnly = prefs.getBool(kPrefBackupWifiOnly) ?? true;

    final savedTime = prefs.getString(kPrefBackupDailyTime);
    if (savedTime != null && savedTime.contains(':')) {
      final parts = savedTime.split(':');
      _dailyTime = TimeOfDay(
        hour: int.tryParse(parts[0]) ?? 2,
        minute: int.tryParse(parts[1]) ?? 0,
      );
    }

    final savedAlbums = prefs.getStringList(kPrefBackupAlbums) ?? [];
    _selectedAlbumIds.clear();
    _selectedAlbumIds.addAll(savedAlbums);

    final lastSyncMillis = prefs.getInt(kPrefLastSyncTimestamp);
    if (lastSyncMillis != null && lastSyncMillis > 0) {
      _lastSyncDate = DateTime.fromMillisecondsSinceEpoch(lastSyncMillis);
    }

    _totalUploadedCount = prefs.getInt(kPrefTotalUploadedCount) ?? 0;

    final lastStatusStr = prefs.getString(kPrefLastSyncStatus);
    if (lastStatusStr != null) {
      try {
        final decoded = jsonDecode(lastStatusStr);
        _lastSyncSuccess = decoded['success'] ?? true;
        _lastSyncStatusMessage = decoded['message'];
      } catch (_) {}
    }

    _serverUrlController.text =
        prefs.getString(kPrefApiBaseUrl) ?? 'http://10.0.2.2:5000';

    // تحميل ألبومات الجهاز عبر photo_manager
    await _fetchDeviceAlbums();

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  /// فحص الأذونات وجلب مجلدات الوسائط عبر photo_manager
  Future<void> _fetchDeviceAlbums() async {
    try {
      final permissionGranted =
          await PermissionService.instance.requestMediaPermission(context: context);

      if (!permissionGranted) {
        debugPrint("[BackupSettingsScreen] Media permission denied.");
        return;
      }

      final PermissionState ps = await PhotoManager.requestPermissionExtend();
      if (!ps.isAuth && !ps.hasAccess) {
        return;
      }

      final List<AssetPathEntity> list = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        hasAll: true,
      );

      final List<AlbumInfo> loaded = [];
      for (final album in list) {
        final count = await album.assetCountAsync;
        loaded.add(
          AlbumInfo(
            id: album.id,
            name: album.name,
            count: count,
            isAll: album.isAll,
          ),
        );
      }

      _availableAlbums = loaded;

      // إذا لم يحدد المستخدم أي ألبوم سابقاً، نحدد ألبوم "الكاميرا / الكل" افتراضياً
      if (_selectedAlbumIds.isEmpty && _availableAlbums.isNotEmpty) {
        _selectedAlbumIds.add(_availableAlbums.first.id);
      }
    } catch (e) {
      debugPrint("[BackupSettingsScreen] Error fetching albums: $e");
    }
  }

  /// حفظ الإعدادات وتسجيل/إلغاء مهمة WorkManager
  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);

    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setBool(kPrefBackupEnabled, _isBackupEnabled);
      await prefs.setString(kPrefBackupFrequency, _frequency);
      await prefs.setBool(kPrefBackupWifiOnly, _isWifiOnly);
      await prefs.setString(
        kPrefBackupDailyTime,
        '${_dailyTime.hour.toString().padLeft(2, '0')}:${_dailyTime.minute.toString().padLeft(2, '0')}',
      );
      await prefs.setStringList(kPrefBackupAlbums, _selectedAlbumIds.toList());
      await prefs.setString(kPrefApiBaseUrl, _serverUrlController.text.trim());

      // تسجيل أو إلغاء مهمة WorkManager وفق الحالة المختارة
      await BackupWorker().scheduleBackupTask(
        enabled: _isBackupEnabled,
        frequency: _frequency,
        wifiOnly: _isWifiOnly,
        dailyTime: _dailyTime,
      );

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
                  child: Text(
                    _isBackupEnabled
                        ? 'تم حفظ الإعدادات وتفعيل جدولة النسخ الاحتياطي بنجاح!'
                        : 'تم حفظ الإعدادات وإلغاء جدولة النسخ الاحتياطي.',
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('حدث خطأ أثناء حفظ الإعدادات: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  /// تشغيل النسخ الاحتياطي اليدوي فوراً بدون انتظار الجدولة
  Future<void> _runManualBackupNow() async {
    setState(() {
      _isManualBackingUp = true;
      _manualProgressMessage = 'جارٍ فحص المجلدات والملفات الجديدة...';
    });

    try {
      final success = await BackupWorker().executeBackupProcess(
        isManual: true,
        onProgress: (current, total) {
          if (mounted) {
            setState(() {
              _manualProgressMessage = 'جارٍ رفع الملف $current من $total...';
            });
          }
        },
      );

      await _loadAllSettings();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor:
                success ? Colors.green.shade700 : Colors.orange.shade800,
            behavior: SnackBarBehavior.floating,
            content: Text(
              success
                  ? 'اكتمل النسخ الاحتياطي بنجاح!'
                  : 'انتهت العملية مع تعذر رفع بعض الملفات (تم إرسال إشعار بالتفاصيل).',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('خطأ أثناء تشغيل النسخ الاحتياطي: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isManualBackingUp = false;
          _manualProgressMessage = null;
        });
      }
    }
  }

  /// اختيار وقت التشغيل اليومي عبر TimePicker
  Future<void> _pickDailyTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _dailyTime,
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _dailyTime = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'إعدادات النسخ الاحتياطي التلقائي',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          centerTitle: true,
          elevation: 1,
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. بطاقة عرض حالة النسخ الاحتياطي الحالية وزر التشغيل الفوري
                    _buildStatusCard(),

                    const SizedBox(height: 16),

                    // 2. مفتاح التفعيل الرئيسي
                    _buildMainSwitchCard(),

                    const SizedBox(height: 16),

                    // 3. اختيار المجلدات المصدر
                    _buildSourceFoldersCard(),

                    const SizedBox(height: 16),

                    // 4. اختيار تردد وجدولة النسخ الاحتياطي
                    _buildFrequencyCard(),

                    const SizedBox(height: 16),

                    // 5. شروط الشبكة والواي فاي
                    _buildNetworkConstraintsCard(),

                    const SizedBox(height: 16),

                    // 6. إعدادات الخادم والتوكن (للاتصال بـ POST /files/upload)
                    _buildServerConfigCard(),

                    const SizedBox(height: 24),

                    // 7. زر حفظ الإعدادات
                    ElevatedButton.icon(
                      onPressed: _isSaving ? null : _saveSettings,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_rounded),
                      label: Text(
                        _isSaving ? 'جارٍ الحفظ والجدولة...' : 'حفظ الإعدادات وتطبيق الجدولة',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
      ),
    );
  }

  /// بطاقة حالة آخر نسخة احتياطية
  Widget _buildStatusCard() {
    final dateFormat = DateFormat('yyyy/MM/dd - hh:mm a');
    final formattedDate = _lastSyncDate != null
        ? dateFormat.format(_lastSyncDate!)
        : 'لم تتم أي مزامنة بعد';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.blue.shade200, width: 1.2),
      ),
      color: Colors.blue.shade50.withOpacity(0.5),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.cloud_sync_rounded,
                  color: Colors.blue.shade800,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Text(
                  'حالة النسخ الاحتياطي',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade900,
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'آخر مزامنة ناجحة:',
                  style: TextStyle(fontSize: 13, color: Colors.black87),
                ),
                Text(
                  formattedDate,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'إجمالي الملفات المرفوعة:',
                  style: TextStyle(fontSize: 13, color: Colors.black87),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$_totalUploadedCount ملف',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade900,
                    ),
                  ),
                ),
              ],
            ),
            if (_lastSyncStatusMessage != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    _lastSyncSuccess ? Icons.check_circle : Icons.info,
                    size: 14,
                    color: _lastSyncSuccess ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _lastSyncStatusMessage!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            // زر تشغيل النسخ الاحتياطي يدوياً الآن
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isManualBackingUp ? null : _runManualBackupNow,
                icon: _isManualBackingUp
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded),
                label: Text(
                  _isManualBackingUp
                      ? (_manualProgressMessage ?? 'جارٍ المزامنة الآن...')
                      : 'تشغيل النسخ الاحتياطي الآن يدويًا',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blue.shade900,
                  side: BorderSide(color: Colors.blue.shade400),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// كرت تفعيل/تعطيل الميزة ككل
  Widget _buildMainSwitchCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        title: const Text(
          'تفعيل النسخ الاحتياطي التلقائي',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        subtitle: const Text(
          'رفع الصور والفيديوهات الجديدة تلقائياً إلى السحابة في الخلفية.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        value: _isBackupEnabled,
        activeColor: Theme.of(context).primaryColor,
        onChanged: (val) {
          setState(() => _isBackupEnabled = val);
        },
      ),
    );
  }

  /// كرت اختيار المجلدات المصدر
  Widget _buildSourceFoldersCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.folder_copy_outlined, color: Colors.indigo),
                const SizedBox(width: 8),
                const Text(
                  'المجلدات المراد نسخها',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _fetchDeviceAlbums,
                  child: const Text('تحديث المجلدات', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const Text(
              'اختر المجلدات التي ترغب في مراقبة ملفاتها ونسخها تلقائياً:',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            if (_availableAlbums.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Column(
                    children: [
                      const Icon(Icons.perm_media_outlined,
                          size: 36, color: Colors.grey),
                      const SizedBox(height: 8),
                      const Text(
                        'لم يتم العثور على مجلدات أو لم يتم منح الصلاحية بعد.',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                      TextButton(
                        onPressed: _fetchDeviceAlbums,
                        child: const Text('منح الإذن والبحث مجدداً'),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _availableAlbums.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, index) {
                  final album = _availableAlbums[index];
                  final isSelected = _selectedAlbumIds.contains(album.id);

                  return CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      album.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text('${album.count} عنصر'),
                    secondary: Icon(
                      album.isAll
                          ? Icons.photo_library_rounded
                          : (album.name.toLowerCase().contains('camera')
                              ? Icons.camera_alt_outlined
                              : (album.name.toLowerCase().contains('whatsapp')
                                  ? Icons.chat_outlined
                                  : Icons.folder_outlined)),
                      color: isSelected
                          ? Theme.of(context).primaryColor
                          : Colors.grey.shade600,
                    ),
                    value: isSelected,
                    onChanged: (bool? checked) {
                      setState(() {
                        if (checked == true) {
                          _selectedAlbumIds.add(album.id);
                        } else {
                          _selectedAlbumIds.remove(album.id);
                        }
                      });
                    },
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  /// كرت اختيار التوقيت والتردد ومعالجة قيود WorkManager
  Widget _buildFrequencyCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.schedule_rounded, color: Colors.deepPurple),
                SizedBox(width: 8),
                Text(
                  'توقيت وتشغيل النسخ الاحتياطي',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'حدد معدل تكرار مهمة الفحص والرفع في الخلفية:',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),

            RadioListTile<String>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('كل ساعة'),
              value: 'hourly',
              groupValue: _frequency,
              onChanged: (val) => setState(() => _frequency = val!),
            ),
            RadioListTile<String>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('كل 6 ساعات'),
              value: 'six_hours',
              groupValue: _frequency,
              onChanged: (val) => setState(() => _frequency = val!),
            ),
            RadioListTile<String>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Row(
                children: [
                  const Text('مرة يوميًا في وقت محدد'),
                  const Spacer(),
                  if (_frequency == 'daily')
                    ActionChip(
                      avatar: const Icon(Icons.access_time, size: 16),
                      label: Text(_dailyTime.format(context)),
                      onPressed: _pickDailyTime,
                    ),
                ],
              ),
              value: 'daily',
              groupValue: _frequency,
              onChanged: (val) => setState(() => _frequency = val!),
            ),
            RadioListTile<String>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('فوري عند إضافة أي ملف جديد (أسرع استجابة)'),
              value: 'immediate',
              groupValue: _frequency,
              onChanged: (val) => setState(() => _frequency = val!),
            ),

            // تنبيه شفاف بخصوص قيود أندرويد وWorkManager
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      color: Colors.amber.shade900, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ملاحظة هامة لنظام أندرويد: يفرض نظام WorkManager حداً أدنى 15 دقيقة للمهام الدورية وتوفير البطارية (Doze Mode). عند اختيار "فوري"، يتم إطلاق مهمة سريعة في أقرب نافذة تشغيل يتيحها النظام.',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        color: Colors.amber.shade950,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// كرت شروط الشبكة والواي فاي
  Widget _buildNetworkConstraintsCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        secondary: Icon(
          _isWifiOnly ? Icons.wifi_rounded : Icons.wifi_tethering_rounded,
          color: _isWifiOnly ? Colors.teal : Colors.blueGrey,
        ),
        title: const Text(
          'الرفع على الواي فاي فقط (Wi-Fi Only)',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: const Text(
          'توفير استهلاك باقة بيانات الهاتف وعدم رفع الملفات إلا عند الاتصال بشبكة غير مقيدة (Unmetered).',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        value: _isWifiOnly,
        onChanged: (val) => setState(() => _isWifiOnly = val),
      ),
    );
  }

  /// كرت إعدادات الخادم لـ POST /files/upload
  Widget _buildServerConfigCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: ExpansionTile(
        leading: const Icon(Icons.dns_rounded, color: Colors.blueGrey),
        title: const Text(
          'إعدادات عنوان الخادم (API Endpoint)',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: const Text(
          'تخصيص عنوان خادم المزامنة والرفع',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
        childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          TextField(
            controller: _serverUrlController,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
              labelText: 'عنوان الخادم الأساسي (Base URL)',
              hintText: 'http://10.0.2.2:5000 أو https://api.example.com',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'يتم استدعاء مسار POST /api/files/upload مع توثيق JWT الموثق تلقائياً من تسجيل الدخول.',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
