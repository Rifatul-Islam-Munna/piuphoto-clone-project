import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:mobileapp/core/theme/app_theme.dart';
import 'package:mobileapp/widgets/app_ui.dart';

@RoutePage()
class TemplatesPage extends StatelessWidget {
  const TemplatesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 82,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Templates'),
            SizedBox(height: 3),
            Text(
              'Reusable delivery layouts',
              style: TextStyle(
                fontSize: 11.5,
                color: AppColors.mutedForeground,
              ),
            ),
          ],
        ),
      ),
      body: const Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: AppEmptyState(
          icon: Icons.dashboard_customize_outlined,
          title: 'Templates',
          message: 'Template tools will appear here when they are available.',
        ),
      ),
    );
  }
}
