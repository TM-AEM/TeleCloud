import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/services/auth_service.dart';

class TelegramSetupScreen extends StatefulWidget {
  const TelegramSetupScreen({super.key});

  @override
  State<TelegramSetupScreen> createState() => _TelegramSetupScreenState();
}

class _TelegramSetupScreenState extends State<TelegramSetupScreen> {
  final _formKey = GlobalKey<FormState>();

  final _apiIdController = TextEditingController();
  final _apiHashController = TextEditingController();
  final _botTokenController = TextEditingController();
  final _channelIdController = TextEditingController();

  bool _obscureBotToken = true;
  bool _obscureApiHash = true;

  @override
  void dispose() {
    _apiIdController.dispose();
    _apiHashController.dispose();
    _botTokenController.dispose();
    _channelIdController.dispose();
    super.dispose();
  }

  void _showHelpBottomSheet({
    required String title,
    required String description,
    required List<String> steps,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(Icons.help_outline_rounded, color: Colors.indigo, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade800,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'الخطوات:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                ...steps.map((step) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.arrow_left, size: 18, color: Colors.indigo),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              step,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.grey.shade800,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo.shade50,
                      foregroundColor: Colors.indigo.shade800,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('فهمت ذلك'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final authService = context.read<AuthService>();

    final success = await authService.configureTelegram(
      apiId: _apiIdController.text,
      apiHash: _apiHashController.text,
      botToken: _botTokenController.text,
      channelId: _channelIdController.text,
    );

    if (!success && mounted) {
      final error = authService.errorMessage ?? 'تعذر حفظ بيانات تيليجرام';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text(error)),
            ],
          ),
        ),
      );
    } else if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          content: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.white),
              SizedBox(width: 8),
              Text('تم ربط حساب تيليجرام وتفعيله بنجاح!'),
            ],
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authService = context.watch<AuthService>();

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('ربط حساب وقناة تيليجرام'),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            tooltip: 'تسجيل الخروج',
            onPressed: () => authService.logout(),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // بطاقة توضيحية
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.telegram, size: 28, color: Colors.blue.shade700),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'التخزين السحابي الخاص بك',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.blue.shade900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'تطبيقنا يستخدم خوادم وقنوات تيليجرام الخاصة بك لتخزين ملفاتك بأمان ومجاناً. يرجى إدخال بيانات الربط للبدء.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue.shade900,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 1. حقل Bot Token
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  '1. رمز توكن البوت (Bot Token):',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.help_outline, color: Colors.indigo, size: 20),
                                tooltip: 'كيف أحصل على Bot Token؟',
                                onPressed: () {
                                  _showHelpBottomSheet(
                                    title: 'كيفية إنشاء بوت تيليجرام والحصول على التوكن',
                                    description:
                                        'توكن البوت يسمح للتطبيق برفع وتنزيل الملفات من قناتك الخاصة.',
                                    steps: [
                                      'افتح تطبيق تيليجرام وابحث عن بوت @BotFather.',
                                      'أرسل الأمر /newbot واتبع التعليمات لاختيار اسم للبوت واسم مستخدم ينتهي بـ bot.',
                                      'سيرسل لك BotFather رسالة تحتوي على التوكن الطويل (مثل: 123456:ABC-DEF...). انسخه والصقه هنا.',
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                          TextFormField(
                            controller: _botTokenController,
                            obscureText: _obscureBotToken,
                            textDirection: TextDirection.ltr,
                            decoration: InputDecoration(
                              hintText: '123456789:AAHk...',
                              suffixIcon: IconButton(
                                icon: Icon(_obscureBotToken ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                onPressed: () => setState(() => _obscureBotToken = !_obscureBotToken),
                              ),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              isDense: true,
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) return 'يرجى إدخال Bot Token';
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // 2. حقل Channel ID
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  '2. معرّف القناة (Channel ID):',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.help_outline, color: Colors.indigo, size: 20),
                                tooltip: 'كيف أحصل على Channel ID؟',
                                onPressed: () {
                                  _showHelpBottomSheet(
                                    title: 'كيفية إنشاء قناة خاصة والحصول على معرّفها',
                                    description:
                                        'القناة الخاصة هي المكان الذي ستُخزن فيه ملفاتك وصورك.',
                                    steps: [
                                      'أنشئ قناة جديدة في تيليجرام (New Channel) واجعلها خاصة (Private).',
                                      'أضف البوت الذي أنشأته مشرفاً (Admin) في القناة مع كامل الصلاحيات.',
                                      'للحصول على معرّف القناة: أرسل أي رسالة في القناة ثم حوّلها إلى بوت @userinfobot أو @JsonDumpBot للحصول على الـ ID (يبدأ غالباً بـ -100).',
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                          TextFormField(
                            controller: _channelIdController,
                            textDirection: TextDirection.ltr,
                            decoration: InputDecoration(
                              hintText: '-1001234567890',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              isDense: true,
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) return 'يرجى إدخال Channel ID';
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // 3. حقل API ID
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  '3. معرّف التطبيق (API ID):',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.help_outline, color: Colors.indigo, size: 20),
                                tooltip: 'كيف أحصل على API ID؟',
                                onPressed: () {
                                  _showHelpBottomSheet(
                                    title: 'كيفية الحصول على API ID و API Hash',
                                    description:
                                        'مطلوبة للتعامل مع Telegram Client API للرفع فائق السرعة والأحجام الكبيرة.',
                                    steps: [
                                      'توجه إلى موقع https://my.telegram.org وسجل الدخول برقم هاتفك.',
                                      'اضغط على "API development tools".',
                                      'أنشئ تطبيقاً جديداً بإدخال أي اسم وتطبيق وهمي.',
                                      'ستظهر لك صفحة تحتوي على api_id (أرقام) و api_hash (أحرف وأرقام).',
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                          TextFormField(
                            controller: _apiIdController,
                            keyboardType: TextInputType.number,
                            textDirection: TextDirection.ltr,
                            decoration: InputDecoration(
                              hintText: '12345678',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              isDense: true,
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) return 'يرجى إدخال API ID';
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // 4. حقل API Hash
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  '4. رمز التجزئة (API Hash):',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.help_outline, color: Colors.indigo, size: 20),
                                tooltip: 'كيف أحصل على API Hash؟',
                                onPressed: () {
                                  _showHelpBottomSheet(
                                    title: 'الحصول على API Hash',
                                    description:
                                        'رمز التجزئة المقترن بـ API ID من بوابة مطوري تيليجرام my.telegram.org.',
                                    steps: [
                                      'من نفس صفحة API development tools في my.telegram.org.',
                                      'انسخ القيمة الموجودة أمام "App api_hash".',
                                      'الصقها هنا في هذا الحقل.',
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                          TextFormField(
                            controller: _apiHashController,
                            obscureText: _obscureApiHash,
                            textDirection: TextDirection.ltr,
                            decoration: InputDecoration(
                              hintText: '0123456789abcdef0123456789abcdef',
                              suffixIcon: IconButton(
                                icon: Icon(_obscureApiHash ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                onPressed: () => setState(() => _obscureApiHash = !_obscureApiHash),
                              ),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              isDense: true,
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) return 'يرجى إدخال API Hash';
                              return null;
                            },
                          ),

                          const SizedBox(height: 24),

                          // زر الحفظ والتفعيل
                          ElevatedButton(
                            onPressed: authService.isLoading ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo.shade600,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                            ),
                            child: authService.isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'حفظ والتحقق من الاتصال',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
