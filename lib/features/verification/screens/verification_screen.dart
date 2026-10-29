import 'package:flutter/material.dart';

class VerificationScreen extends StatelessWidget {
  const VerificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('توثيق الهوية')),
      body: const Center(child: Text('شاشة التوثيق — قيد الإنشاء')),
    );
  }
}

