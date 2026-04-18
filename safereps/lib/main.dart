import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'models/goals_model.dart';
import 'services/ble_service.dart';
import 'services/theme_service.dart';
import 'shell.dart';
import 'theme.dart';

List<CameraDescription> cameras = const [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize ThemeService
  final themeService = ThemeService();
  await themeService.init();

  // Query cameras
  try {
    cameras = await availableCameras();
  } catch (_) {
    cameras = const [];
  }

  // Initialize BLE and Goals services
  final bleService = BleService();
  final goalsModel = GoalsModel();
  await goalsModel.load();

  runApp(
    ThemeScope(
      service: themeService,
      child: GoalsScope(
        model: goalsModel,
        child: BleScope(
          ble: bleService,
          child: const SafeRepsApp(),
        ),
      ),
    ),
  );
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
