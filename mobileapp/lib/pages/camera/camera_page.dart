import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:mobileapp/core/theme/app_theme.dart';
import 'package:mobileapp/widgets/app_ui.dart';

@RoutePage()
class CameraPage extends StatelessWidget {
  const CameraPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 82,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Camera'),
            SizedBox(height: 3),
            Text(
              'Capture workspace',
              style: TextStyle(
                fontSize: 11.5,
                color: AppColors.mutedForeground,
              ),
            ),
          ],
        ),
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 28),
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
