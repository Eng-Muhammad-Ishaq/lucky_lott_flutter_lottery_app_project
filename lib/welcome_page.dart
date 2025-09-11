// welcome_page.dart
// Added camera & gallery permission requests alongside notification permission.

import 'dart:async';
import 'package:flutter/material.dart';
// ignore: unused_import
import 'package:lottie/lottie.dart';
import 'package:lucky_lott/notification_service.dart';
import 'package:animate_do/animate_do.dart';
import 'package:permission_handler/permission_handler.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> with TickerProviderStateMixin {
  late Timer _timer;
  String _displayedText = "";
  final String _fullText = "Welcome to\nLucky Lott";
  int _charIndex = 0;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    // ✅ Initialize Firebase Cloud Messaging
    NotificationService.initialize(context);

    // ✅ Ask for camera & gallery permissions
    _requestMediaPermissions();

    _startTypingAnimation();
    _startAutoNavigate();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..forward();

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(_fadeController);
  }

  Future<void> _requestMediaPermissions() async {
    // Ask for camera permission
    var cameraStatus = await Permission.camera.status;
    if (!cameraStatus.isGranted) {
      await Permission.camera.request();
    }

    // Ask for gallery/photos permission
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      var photosStatus = await Permission.photos.status;
      if (!photosStatus.isGranted) {
        await Permission.photos.request();
      }
    } else {
      var storageStatus = await Permission.storage.status;
      if (!storageStatus.isGranted) {
        await Permission.storage.request();
      }
    }
  }

  void _startTypingAnimation() {
    Timer.periodic(const Duration(milliseconds: 90), (timer) {
      if (_charIndex < _fullText.length) {
        setState(() {
          _displayedText += _fullText[_charIndex];
          _charIndex++;
        });
      } else {
        timer.cancel();
      }
    });
  }

  void _startAutoNavigate() {
    _timer = Timer(const Duration(seconds: 7), _navigateToHome);
  }

  void _navigateToHome() {
    _timer.cancel();
    Navigator.pushReplacementNamed(context, '/home');
  }

  @override
  void dispose() {
    _timer.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF3BB78F), Color(0xFF0BAB64)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),

          // Decorative shapes
          Positioned(
            left: -60,
            top: -80,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.06),
              ),
            ),
          ),
          Positioned(
            right: -40,
            bottom: -80,
            child: Transform.rotate(
              angle: -0.2,
              child: Container(
                width: 300,
                height: 250,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(46),
                  color: Colors.white.withOpacity(0.04),
                ),
              ),
            ),
          ),

          // Content
          SafeArea(
            child: SizedBox(
              height: mq.size.height,
              width: double.infinity,
              child: Column(
                children: [
                  const SizedBox(height: 28),

                  // Skip button
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 18.0),
                      child: GestureDetector(
                        onTap: _navigateToHome,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(30),
                            color: Colors.black.withOpacity(0.6),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 6,
                              )
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Text(
                                "Skip",
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                              SizedBox(width: 6),
                              Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Center logo & text
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Bounce(
                            infinite: true,
                            duration: const Duration(milliseconds: 1200),
                            from: 6,
                            child: CircleAvatar(
                              radius: 56,
                              backgroundColor: Colors.white.withOpacity(0.12),
                              child: FadeTransition(
                                opacity: _fadeAnimation,
                                child: SizedBox(
                                  height: 80,
                                  width: 80,
                                  child: Image.asset('assets/logos.png', fit: BoxFit.contain),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          FadeInUp(
                            duration: const Duration(milliseconds: 700),
                            child: Text(
                              _displayedText,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                height: 1.4,
                                shadows: [
                                  Shadow(
                                    blurRadius: 10,
                                    color: Colors.black38,
                                    offset: Offset(2, 2),
                                  ),
                                ],
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Footer
                  Padding(
                    padding: const EdgeInsets.only(bottom: 18.0),
                    child: FadeInUp(
                      delay: const Duration(milliseconds: 300),
                      child: Text(
                        'Powered by Professor',
                        style: TextStyle(fontSize: 14, color: Colors.white70, fontStyle: FontStyle.italic),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
