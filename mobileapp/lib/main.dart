import 'package:auto_route/auto_route.dart';
import 'package:cached_query/cached_query.dart';
import 'package:cached_storage/cached_storage.dart';
import 'package:cached_query_flutter/cached_query_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobileapp/core/di/locator.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/core/router/app_router.dart';
import 'package:mobileapp/core/router/auth_guard.dart';
import 'package:mobileapp/core/storage/active_event_storage.dart';
import 'package:mobileapp/core/storage/user_storage.dart';
import 'package:mobileapp/core/theme/app_theme.dart';
import 'package:mobileapp/core/upload/upload_queue_service.dart';
import 'package:mobileapp/core/upload/upload_queue_storage.dart';
import 'package:mobileapp/utilities/app_toast.dart';

late final AppRouter appRouter;

Future<void> setupDependencies() async {
  await dotenv.load(fileName: '.env');
  getIt.registerSingleton<FlutterSecureStorage>(const FlutterSecureStorage());
  final prefs = await SharedPreferences.getInstance();
  getIt.registerSingleton<SharedPreferences>(prefs);
  await UserStorage.init();
  await ActiveEventStorage.init();
  await UploadQueueStorage.init();
  DioHelper.init();
  UploadQueueService.start();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupDependencies();

  appRouter = AppRouter(authGuard: AuthGuard());

  DioHelper.setUnauthorizedHandler(() async {
    appRouter.replaceAll([const LoginRoute()]);
  });

  CachedQuery.instance.configFlutter(
    storage: await CachedStorage.ensureInitialized(),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Nikofly',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: AppToast.messengerKey,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      routerConfig: appRouter.config(),
    );
  }
}
