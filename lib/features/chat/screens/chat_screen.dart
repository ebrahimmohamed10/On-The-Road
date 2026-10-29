import 'package:flutter/material.dart';

class ChatScreen extends StatelessWidget {
  final String bookingId;
  const ChatScreen({super.key, required this.bookingId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المحادثة')),
      body: Center(child: Text('محادثة الحجز: $bookingId — قيد الإنشاء')),
    );
  }
}

