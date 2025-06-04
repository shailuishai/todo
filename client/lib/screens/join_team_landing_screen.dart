// lib/screens/join_team_landing_screen.dart
import 'package:flutter/material.dart';

class JoinTeamLandingScreen extends StatelessWidget {
  const JoinTeamLandingScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            CircularProgressIndicator(),
            SizedBox(height: 24),
            Text(
              'Присоединяемся к команде...',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            SizedBox(height: 12),
            Text(
              'Пожалуйста, подождите немного.',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}