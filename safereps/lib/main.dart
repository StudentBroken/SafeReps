import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'pose_camera_page.dart';

List<CameraDescription> cameras = const [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } on CameraException {
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: PoseCameraPage(cameras: cameras),
    );
  }
}
