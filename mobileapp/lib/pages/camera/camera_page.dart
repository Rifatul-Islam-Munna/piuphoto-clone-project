import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:mobileapp/widgets/app_ui.dart';

@RoutePage()
class CameraPage extends StatelessWidget {
  const CameraPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Camera',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
        ),
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, 10, 14, 24),
          child: AppEmptyState(
            icon: Icons.camera_alt_outlined,
            title: 'Camera capture',
            message:
                'Camera capture is available from the upload workspace, where shots can be delivered directly to the active event.',
          ),
        ),
      ),
    );
  }
}
