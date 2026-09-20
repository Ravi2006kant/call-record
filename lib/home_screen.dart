import 'package:flutter/material.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String callStatus = 'waiting for call ..';
  @override
  Widget build(BuildContext context) {
    return Scaffold(body:Center(child: Text(callStatus,style: TextStyle(fontSize: 22),),) );
  }
}