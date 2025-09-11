// Flutter core packages
import 'dart:async';
import 'package:flutter/material.dart';
import 'notification_service.dart';

// Firebase Core
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

// Google Fonts package to use custom fonts
import 'package:google_fonts/google_fonts.dart';

// 🧭 Page imports
import 'welcome_page.dart';
import 'access_page.dart';
import 'home_page.dart';
import 'agreement_page.dart';
import 'admin_panel.dart';
import 'payment_confirmation_page.dart';
import 'winner_page.dart';
import 'ticket_history_page.dart';
import 'profile_page.dart';
import 'contact_page.dart';
import 'goldpay.dart'; // <-- NEW: Golden Lott payment page

/// ✅ Main entry point of the app
void main() {
  runZonedGuarded(() async {
    // Required for Firebase and async bindings
    WidgetsFlutterBinding.ensureInitialized();

    // ✅ Initialize Firebase with options from firebase_options.dart
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // 🎯 Launch the app
    runApp(const LuckyLottApp());
  }, (error, stackTrace) {
    // 🔥 Catch any uncaught Firebase errors
    // ignore: avoid_print
    print('🔥 Uncaught Firebase error: $error');
  });
}

/// 🧩 Root widget for the entire application
class LuckyLottApp extends StatelessWidget {
  const LuckyLottApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        // 🔔 Initialize FCM and Local Notifications
        NotificationService.initialize(context);

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Lucky Lott',
          theme: ThemeData(
            textTheme: GoogleFonts.poppinsTextTheme(),
            scaffoldBackgroundColor: const Color(0xFFF5F5F5),
          ),
          initialRoute: '/welcome',
          routes: {
            '/welcome': (context) => const WelcomePage(),
            '/access': (context) => const AccessPage(),
            '/home': (context) => const HomePage(),
            '/agreement': (context) => const AgreementPage(),
            '/admin': (context) => const AdminPanel(),
            '/payment': (context) => const PaymentConfirmationPage(), // Lott (regular)
            '/goldpay': (context) => const GoldPayPage(),            // <-- NEW: Golden Lott
            '/winner': (context) => const WinnerPage(),
            '/tickethistorypage': (context) => const TicketHistoryPage(),
            '/profile': (context) => const ProfilePage(),
            '/contact': (context) => const ContactPage(),
          },
        );
      },
    );
  }
}
