import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'shell.dart';
import 'theme.dart';

List<CameraDescription> cameras = const [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } catch (_) {
    cameras = const [];
  }
  runApp(const SafeRepsApp());
}

class SafeRepsApp extends StatelessWidget {
  const SafeRepsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SafeReps',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const MainShell(),
    );
  }
}
