import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'shell.dart';
import 'theme.dart';
import 'services/theme_service.dart';

List<CameraDescription> cameras = const [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize ThemeService
  final themeService = ThemeService();
  await themeService.init();

  try {
    cameras = await availableCameras();
  } catch (_) {
    cameras = const [];
  }
  
  runApp(ThemeScope(
    service: themeService,
    child: const SafeRepsApp(),
  ));
}

class SafeRepsApp extends StatelessWidget {
  const SafeRepsApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeService = ThemeScope.of(context);
    
    return ListenableBuilder(
      listenable: themeService,
      builder: (context, _) {
        return MaterialApp(
          title: 'SafeReps',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.fromFlavor(themeService.flavor),
          home: const MainShell(),
        );
      },
    );
  }
}
