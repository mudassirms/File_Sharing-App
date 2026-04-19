// lib/core/services/notification_service.dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NotificationService {
  final FirebaseMessaging _fcm;
  final FlutterLocalNotificationsPlugin _localNotifications;

  /// ✅ Named parameters (consistent with your architecture)
  NotificationService({
    required FirebaseMessaging fcm,
    required FlutterLocalNotificationsPlugin localNotifications,
  })  : _fcm = fcm,
        _localNotifications = localNotifications;

  /// Initialize notifications
  Future<void> init() async {
    // 🔐 Request permission
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    // 🔧 Local notifications init
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _localNotifications.initialize(
      const InitializationSettings(
        android: androidInit,
        iOS: iosInit,
      ),
      onDidReceiveNotificationResponse: (response) {
        // 🔥 Handle notification tap (optional navigation hook)
        final transferId = response.payload;
        if (transferId != null) {
          // TODO: Navigate to transfer screen
        }
      },
    );

    // 📢 Android notification channel
    const channel = AndroidNotificationChannel(
      'transfers',
      'File Transfers',
      description: 'Incoming file transfer notifications',
      importance: Importance.high,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // 📩 Foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // 📲 App opened from notification (background)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);
  }

  /// Handle foreground notification
  void _handleForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'transfers',
          'File Transfers',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: message.data['transferId'],
    );
  }

  /// Handle notification click (when app is opened)
  void _handleMessageTap(RemoteMessage message) {
    final transferId = message.data['transferId'];
    if (transferId != null) {
      // TODO: Navigate to transfer details screen
    }
  }

  /// Get FCM token
  Future<String?> getToken() => _fcm.getToken();

  /// Listen for token refresh (VERY IMPORTANT for production)
  void listenTokenRefresh() {
    _fcm.onTokenRefresh.listen((newToken) {
      // TODO: Send updated token to Firestore
    });
  }
}

/// Background handler (must be top-level)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // No UI here — just background processing if needed
}

// ─── Provider ─────────────────────────────────────────────

final firebaseMessagingProvider = Provider<FirebaseMessaging>((ref) {
  return FirebaseMessaging.instance;
});

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService(
    fcm: ref.read(firebaseMessagingProvider),
    localNotifications: FlutterLocalNotificationsPlugin(),
  );
});
