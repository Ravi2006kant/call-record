import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CallDetectionScreen extends StatefulWidget {
  const CallDetectionScreen({super.key});

  @override
  State<CallDetectionScreen> createState() =>
      _CallDetectionScreenState();
}

class _CallDetectionScreenState
    extends State<CallDetectionScreen> {

  static const MethodChannel callChannel =
      MethodChannel('call_detection');

  String callStatus = 'Waiting for call...';

  Future<void> startDetection() async {
    final result = await callChannel.invokeMethod(
      'startCallDetection',
    );

    setState(() {
      callStatus = result.toString();
    });
  }

  @override
  void initState() {
    super.initState();
    startDetection();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Call Detection'),
      ),
      body: Center(
        child: Text(
          callStatus,
          style: const TextStyle(
            fontSize: 22,
          ),
        ),
      ),
    );
  }
}