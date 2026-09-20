import 'package:flutter/material.dart';
import 'package:record/calldetection.dart';
import 'package:record/home_screen.dart';

class Myapp extends StatelessWidget {
  const Myapp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "record",
      debugShowCheckedModeBanner: false,
home: CallDetectionScreen(),
    );
  }
}