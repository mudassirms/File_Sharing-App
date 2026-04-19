import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_options.dart' show DefaultFirebaseOptions;
import 'shared/theme/app_theme.dart';
import 'core/router/router_provider.dart';
import 'core/services/notification_service.dart';
import 'core/services/identity_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('[FCM-BG] message: ${message.data}');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Supabase
  await Supabase.initialize(
    url: 'https://ecdnxmoyhgbodmvjcmul.supabase.co',
    anonKey: 'sb_publishable_Ft4DN-DCN71UnqwTO9x_Kw_RwkZv0EQ',
  );

  // Background FCM handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  FirebaseFirestore.instance.settings = const Settings(
  persistenceEnabled: true,
  cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
);

  runApp(
    const ProviderScope(
      child: NeoSapienApp(),
    ),
  );
}

class NeoSapienApp extends ConsumerStatefulWidget {
  const NeoSapienApp({super.key});

  @override
  ConsumerState<NeoSapienApp> createState() => _NeoSapienAppState();
}

class _NeoSapienAppState extends ConsumerState<NeoSapienApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await ref.read(notificationServiceProvider).init();
    await ref.read(identityServiceProvider).provisionIdentity();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      ref.read(identityServiceProvider).provisionIdentity();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'NeoSapien Share',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: router,
    );
  }
}