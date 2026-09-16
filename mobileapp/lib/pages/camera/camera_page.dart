import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:mobileapp/widgets/app_ui.dart';

@RoutePage()
class CameraPage extends StatelessWidget {
  const CameraPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: AppEmptyState(
            icon: Icons.camera_alt_outlined,
            title: 'Camera',
            message: 'Camera capture is available from the upload workspace.',
          ),
        ),
      ),
    );
  }
}
