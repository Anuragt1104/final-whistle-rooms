import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:firebase_messaging/firebase_messaging.dart';

import 'api/api_client.dart';
import 'state/local_store.dart';
import 'state/push_service.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );
  // Register before runApp so killed-app data messages can wake an isolate.
  try {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (_) {}
  await ApiClient.instance.init();
  // Pre-warm (not awaited): refreshes the cached config/fixtures and wakes a
  // sleeping backend while the user is still on the splash/onboarding, so the
  // first tap decides live-vs-replay instantly.
  () async {
    try {
      await ApiClient.instance.config();
    } catch (_) {}
    try {
      await ApiClient.instance.fixtures();
    } catch (_) {}
  }();
  // FCM + local channel + foreground rooms poller (suppresses while in-room).
  PushService.instance.init();
  final onboarded = await LocalStore.onboarded();
  runApp(FinalWhistleApp(onboarded: onboarded));
}

class FinalWhistleApp extends StatelessWidget {
  final bool onboarded;
  const FinalWhistleApp({super.key, required this.onboarded});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Final Whistle',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: onboarded ? const HomeScreen() : const OnboardingScreen(),
    );
  }
}
