import 'package:flutter/material.dart';
import 'package:rtc_link/main.dart';

class Splashscreen extends StatefulWidget {
  @override
  State<Splashscreen> createState() => _SplashscreenState();
}

class _SplashscreenState extends State<Splashscreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(seconds: 2), () {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => VideoCallScreen()));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xff008069),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.videocam_rounded, size: 100, color: Colors.white),
            SizedBox(height: 20),
            Text(
              "RTCLink",
              style: TextStyle(fontSize: 26, color: Colors.white, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text("Connect Anytime, Anywhere",
                style: TextStyle(fontSize: 13, color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}
