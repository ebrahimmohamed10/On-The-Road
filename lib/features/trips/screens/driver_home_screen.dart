import 'package:flutter/material.dart';

class DriverHomeScreen extends StatelessWidget {
  const DriverHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('لوحة السائق')),
      body: const Center(child: Text('الرئيسية — السائق — قيد الإنشاء')),
    );
  }
}

