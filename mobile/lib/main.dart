import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api/api_client.dart';
import 'state/local_store.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  ));
  await ApiClient.instance.init();
  final onboarded = await LocalStore.onboarded();
  runApp(FinalWhistleApp(onboarded: onboarded));
}

class FinalWhistleApp extends StatelessWidget {
  final bool onboarded;
  const FinalWhistleApp({super.key, required this.onboarded});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Final Whistle Rooms',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: onboarded ? const HomeScreen() : const OnboardingScreen(),
    );
  }
}
