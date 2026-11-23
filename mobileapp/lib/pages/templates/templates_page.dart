import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:mobileapp/widgets/app_ui.dart';

@RoutePage()
class TemplatesPage extends StatelessWidget {
  const TemplatesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Templates',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
        ),
      ),
      body: const Padding(
        padding: EdgeInsets.fromLTRB(14, 10, 14, 24),
        child: AppEmptyState(
          icon: Icons.dashboard_customize_outlined,
          title: 'Templates',
          message: 'Template tools will appear here when they are available.',
        ),
      ),
    );
  }
}
