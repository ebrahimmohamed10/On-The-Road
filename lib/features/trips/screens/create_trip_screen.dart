import 'package:flutter/material.dart';

class CreateTripScreen extends StatelessWidget {
  const CreateTripScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إنشاء رحلة')),
      body: const Center(child: Text('إنشاء رحلة — قيد الإنشاء')),
    );
  }
}

