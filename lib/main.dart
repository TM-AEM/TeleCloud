import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/backup/backup_worker.dart';
import 'core/services/auth_service.dart';
import 'file_browser_provider.dart';
import 'file_browser_screen.dart';
import 'auth_screen.dart';
import 'telegram_setup_screen.dart';

void main() async {
  // التأكد من تهيئة بيئة تشغيل Flutter
  WidgetsFlutterBinding.ensureInitialized();

  // تهيئة WorkManager ونظام الإشعارات المحلية قبل استدعاء runApp
  try {
    await BackupWorker.initialize();
  } catch (e) {
    debugPrint('[Main] WorkManager initialization error: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()..checkAuthStatus()),
        ChangeNotifierProvider(create: (_) => FileBrowserProvider()),
      ],
      child: MaterialApp(
        title: 'مدير الملفات السحابي',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
          useMaterial3: true,
          fontFamily: 'Roboto',
        ),
        home: const AppRootGate(),
      ),
    );
  }
}

/// موجه الشاشات الذكي حسب حالة الدخول وإعدادات تيليجرام
class AppRootGate extends StatelessWidget {
  const AppRootGate({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, auth, _) {
        // 1. شاشة تحميل أولية أثناء فحص التوكن المخزن
        if (auth.isCheckingInitialAuth) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'جارٍ التحقق من الجلسة السحابية...',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ],
              ),
            ),
          );
        }

        // 2. إذا لم يكن المستخدم مسجل الدخول (لا يوجد توكن صالح)
        if (!auth.isAuthenticated) {
          return const AuthScreen();
        }

        // 3. إذا كان مسجلاً ولكن لم يقم بربط إعدادات تيليجرام بعد
        if (!auth.isTelegramConfigured) {
          return const TelegramSetupScreen();
        }

        // 4. مسجل ومفعل تيليجرام بالكامل -> الشاشة الرئيسية
        return const FileBrowserScreen();
      },
    );
  }
}
