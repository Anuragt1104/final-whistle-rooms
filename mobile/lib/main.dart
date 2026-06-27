import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api/api_client.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  ));
  await ApiClient.instance.init();
  runApp(const FinalWhistleApp());
}

class FinalWhistleApp extends StatelessWidget {
  const FinalWhistleApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Final Whistle Rooms',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const HomeScreen(),
    );
  }
}
