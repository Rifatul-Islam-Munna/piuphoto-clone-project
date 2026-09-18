import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:mobileapp/core/theme/app_theme.dart';
import 'package:mobileapp/widgets/app_ui.dart';

@RoutePage()
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 82,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('History'),
            SizedBox(height: 3),
            Text(
              'Recent delivery activity',
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
          icon: Icons.history_rounded,
          title: 'No history yet',
          message: 'Your recent photo delivery activity will appear here.',
        ),
      ),
    );
  }
}
