import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:mobileapp/widgets/app_ui.dart';

@RoutePage()
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'History',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
        ),
      ),
      body: const Padding(
        padding: EdgeInsets.fromLTRB(14, 10, 14, 24),
        child: AppEmptyState(
          icon: Icons.history_rounded,
          title: 'No history yet',
          message: 'Your recent photo delivery activity will appear here.',
        ),
      ),
    );
  }
}
