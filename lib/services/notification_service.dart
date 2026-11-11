import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'api_service.dart';

// Handle background messages (must be top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  // Firebase is already initialized by the time this runs
  debugPrint('Background message: ${message.notification?.title}');
}

class NotificationService {
  static final _messaging = FirebaseMessaging.instance;

  static Future<void> init() async {
    // Request permission (iOS requires explicit request; Android 13+ too)
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('Notifications denied');
      return;
    }

    // Register background handler
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

    // Get FCM token and send to backend
    await _registerToken();

    // Handle token refresh
    _messaging.onTokenRefresh.listen((token) async {
      await _sendTokenToBackend(token);
    });

    // Foreground messages — show a simple debug print for now
    // (Android shows heads-up notifications automatically in background/terminated)
    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('Foreground message: ${message.notification?.title} — ${message.notification?.body}');
    });
  }

  static Future<void> _registerToken() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        await _sendTokenToBackend(token);
        debugPrint('FCM token registered');
      }
    } catch (e) {
      debugPrint('Failed to register FCM token: $e');
    }
  }

  static Future<void> _sendTokenToBackend(String token) async {
    try {
      await ApiService().registerDeviceToken(token);
    } catch (e) {
      debugPrint('Failed to send token to backend: $e');
    }
  }
}
