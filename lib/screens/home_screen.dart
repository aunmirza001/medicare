import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import 'dashboard_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          TextButton(
            onPressed: () async {
              await auth.signOut();
            },
            child: const Text('Logout'),
          ),
        ],
      ),
      body: const DashboardScreen(),
    );
  }
}
