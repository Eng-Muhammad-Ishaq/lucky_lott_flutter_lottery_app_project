// home_page.dart
// Clean version:
// - Removed all old draw-status + countdown code
// - Two-side switch: "Lott" (original content) / "Golden Lott" (separate section)
// - Lott buy -> '/payment' (requires login)
// - Golden Lott buy -> '/goldpay' (requires login)
// - Golden participants counter: counters/golden_participants
// - Uses prize images from assets/prizes/*

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:animate_do/animate_do.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  // auth/ui
  int _adminTapCount = 0;
  bool _isLoggedIn = false;

  // switch state (false = Lott, true = Golden Lott)
  bool _showGolden = false;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  void _checkLoginStatus() {
    final user = FirebaseAuth.instance.currentUser;
    _isLoggedIn = user != null;
    if (mounted) setState(() {});
  }

  void _manualRefresh() => setState(() {});

  // ------------ admin login ------------
  void _handleAdminTap() {
    _adminTapCount++;
    if (_adminTapCount >= 10) {
      _adminTapCount = 0;
      _showAdminLoginDialog();
    }
  }

  void _showAdminLoginDialog() {
    final TextEditingController passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Admin Login"),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          decoration: const InputDecoration(labelText: "Enter Admin Password"),
        ),
        actions: [
          TextButton(
            child: const Text("Cancel"),
            onPressed: () => Navigator.of(context).pop(),
          ),
          ElevatedButton(
            child: const Text("Login"),
            onPressed: () {
              if (passwordController.text == "Professor111@") {
                Navigator.of(context).pop();
                Navigator.pushNamed(context, '/admin');
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Incorrect password")),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  // ------------ build ------------
  @override
  Widget build(BuildContext context) {
    final participantsStream =
        _fs.collection('counters').doc('participants').snapshots();

    return Scaffold(
      key: _scaffoldKey,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: GestureDetector(
          onTap: _handleAdminTap,
          child: const Text(
            'Lucky Lott',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: [
         
          IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          ),
        ],
      ),
      drawer: _buildDrawer(context),
      body: Stack(
        children: [
          // background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF3BB78F), Color(0xFF0BAB64)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
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

          // content
          SafeArea(
            child: RefreshIndicator(
              onRefresh: () async => _manualRefresh(),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                child: Column(
                  children: [
                    const SizedBox(height: 6),
                    FadeInDown(
                      child: const Center(
                        child: Text(
                          'Buy Now, Win Big!',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                blurRadius: 6,
                                color: Colors.black87,
                                offset: Offset(1, 2),
                              )
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Two-side rectangular switch
                    const SizedBox(height: 12),
                    _lottGoldenSwitch(),

                    // Content per tab
                    if (!_showGolden) ...[
                      // ----- LOTT (original content) -----
                      const SizedBox(height: 10),
                      FadeInUp(
                        delay: const Duration(milliseconds: 40),
                        child: StreamBuilder<
                            DocumentSnapshot<Map<String, dynamic>>>(
                          stream: participantsStream,
                          builder: (context, snap) {
                            final data = snap.data?.data();
                            final total = (data != null && data['total'] is int)
                                ? data['total'] as int
                                : 0;
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12.0),
                              child: _buildParticipantsCard(total),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buyCards(),
                    ] else ...[
                      // ----- GOLDEN LOTT -----
                      const SizedBox(height: 10),
                      _goldenTicketSection(),
                    ],

                    const SizedBox(height: 26),
                    FadeInUp(
                      delay: const Duration(milliseconds: 200),
                      child: const Text(
                        'Powered by Professor',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
     bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed, // <— add this
  currentIndex: 0, // Home is active on this page
  backgroundColor: const Color.fromARGB(255, 0, 0, 0),
  selectedItemColor: Colors.white,
  unselectedItemColor: Colors.white70,
  onTap: (index) {
    if (index == 0) {
      // already on Home
    } else if (index == 1) {
      Navigator.pushNamed(context, '/tickethistorypage');
    } else if (index == 2) {
      Navigator.pushNamed(context, '/profile');
    } else if (index == 3) {
      Navigator.pushNamed(context, '/winner');
    }
  },
  items: const [
    BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
    BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
    BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
    BottomNavigationBarItem(icon: Icon(Icons.emoji_events), label: 'Winners'),
  ],
),

    );
  }

  // ------------ Lott / Golden Lott switch ------------
  Widget _lottGoldenSwitch() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.96),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.14),
              blurRadius: 26,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: _switchSegment(
                label: 'Lott',
                icon: Icons.local_activity,
                active: !_showGolden,
                onTap: () => setState(() => _showGolden = false),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _switchSegment(
                label: 'Golden Lott',
                icon: Icons.star_rounded,
                active: _showGolden,
                onTap: () => setState(() => _showGolden = true),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _switchSegment({
    required String label,
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 50,
        decoration: BoxDecoration(
          color: active ? Colors.green.shade700 : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? Colors.green.shade700 : Colors.black12,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: active ? Colors.white : Colors.black87, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------ GOLDEN LOTT SECTION ------------
  Widget _goldenTicketSection() {
    return FadeInUp(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFE082), Color(0xFFFFC107), Color(0xFFFFB300)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(color: Colors.black38, blurRadius: 16, offset: Offset(0, 10)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // header row
            Row(
              children: [
                const Icon(Icons.star_rounded, color: Colors.black87, size: 26),
                const SizedBox(width: 8),
                const Text(
                  'Golden Lott Ticket',
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Rs. 300',
                    style: TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),
            const Divider(color: Colors.black26, height: 1),
            const SizedBox(height: 10),

            // Golden participants counter
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _fs.collection('counters').doc('golden_participants').snapshots(),
              builder: (context, snap) {
                final data = snap.data?.data();
                final total = (data != null && data['total'] is int) ? data['total'] as int : 0;
                return _goldenParticipants(total);
              },
            ),

            const SizedBox(height: 12),
            const Text(
              'Prizes in this Golden Draw',
              style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),

            // prize thumbnails (square)
            Row(
              children: [
                _goldenPrizeImageBox('assets/prizes/bike.png', label: 'Honda 70CC\n(~Rs. 100,000)'),
                const SizedBox(width: 10),
                _goldenPrizeImageBox('assets/prizes/iphone.png', label: 'iPhone 8 Plus (Non-PTA)\n(~Rs. 50,000)'),
                const SizedBox(width: 10),
                _goldenPrizeImageBox('assets/prizes/watch.png', label: 'Smart Watch\n(~Rs. 10,000)'),
              ],
            ),

            const SizedBox(height: 12),
            _goldenBullet('Grand Prize: Honda 70CC Bike (worth ~Rs. 100,000)'),
            const SizedBox(height: 6),
            _goldenBullet('2nd Prize: iPhone (Non-PTA) — ~Rs. 50,000'),
            const SizedBox(height: 6),
            _goldenBullet('3rd Prize: Smart Watch — ~Rs. 10,000 value'),
            const SizedBox(height: 6),
            _goldenBullet('Golden ticket is separate from other tickets.'),

            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _buyGolden,
                icon: const Icon(Icons.shopping_cart),
                label: const Text('Buy Golden Ticket'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black87,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 8,
                  shadowColor: Colors.black54,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _goldenParticipants(int total) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.groups, size: 18, color: Colors.black87),
          const SizedBox(width: 8),
          Text(
            'Golden Participants: $total',
            style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget _goldenBullet(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('• ', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w900)),
        Expanded(
          child: Text(text, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Widget _goldenPrizeImageBox(String assetPath, {required String label}) {
    return Expanded(
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 1,
              child: Image.asset(
                assetPath,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.white.withOpacity(0.4),
                  child: const Center(
                    child: Icon(Icons.image_not_supported_outlined, color: Colors.black54),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  void _buyGolden() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // NEW: separate page for golden payments (requires login)
      Navigator.pushNamed(
        context,
        '/goldpay',
        arguments: {
          'amount': 300,
          'ticketCount': 1,
          'product': 'Golden Lott Ticket',
        },
      );
    } else {
      // Not logged in -> show message then go to access/login
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🔔 Please log in to buy tickets'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      Navigator.pushNamed(context, '/access');
    }
  }

  // ------------ Original Lott pieces (unchanged) ------------
  Widget _buyCards() {
  return Column(
    children: [
      FadeInUp(
        child: _buildTicketCard(
          'Rs. 100',
          'Buy 1 Ticket',
          1,
          const Color(0xFF1F2937),
          amountValue: 100,
          ticketCountValue: 1,
        ),
      ),
      const SizedBox(height: 20),
      FadeInUp(
        delay: const Duration(milliseconds: 80),
        child: _buildTicketCard(
          'Rs. 200',
          'Buy 3 Tickets',
          2,
          const Color(0xFF1F2937),
          amountValue: 200,
          ticketCountValue: 3,
        ),
      ),
      const SizedBox(height: 20),
      FadeInUp(
        delay: const Duration(milliseconds: 140),
        child: _buildTicketCard(
          'Rs. 300',
          'Buy 5 Tickets',
          3,
          const Color(0xFF1F2937),
          amountValue: 300,
          ticketCountValue: 5,
        ),
      ),
    ],
  );
}


  Widget _buildTicketCard(
    String price,
    String detail,
    int stars,
    Color color, {
    required int amountValue,
    required int ticketCountValue,
  }) {
    final bool isDark =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.white70 : Colors.black54;
    const starColor = Colors.amber;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.98), color.withOpacity(0.82)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(
              stars,
              (index) => const Padding(
                padding: EdgeInsets.only(right: 4.0),
                child: Icon(Icons.star, color: starColor, size: 22),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            price,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: textColor,
              shadows: const [
                Shadow(color: Colors.black26, blurRadius: 2, offset: Offset(1, 1))
              ],
            ),
          ),
          Text(detail, style: TextStyle(color: subtitleColor)),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              onPressed: () {
                final user = FirebaseAuth.instance.currentUser;
                if (user != null) {
                  // Lott uses the existing payment page (requires login)
                  Navigator.pushNamed(
                    context,
                    '/payment',
                    arguments: {
                      'amount': amountValue,
                      'selectedAmounts': <int>[amountValue],
                      'ticketCount': ticketCountValue,
                    },
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('🔔 Please log in to buy tickets'),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 2),
                    ),
                  );
                  Navigator.pushNamed(context, '/access');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                elevation: 10,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
                shadowColor: Colors.black54,
              ),
              child: const Text(
                'Buy Now',
                style: TextStyle( 
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(blurRadius: 4, color: Colors.black87, offset: Offset(1, 2))
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantsCard(int total) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, 6))
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Participants',
                  style: TextStyle(
                      color: Colors.grey.shade800,
                      fontWeight: FontWeight.w700,
                      fontSize: 16)),
              const SizedBox(height: 6),
              Text('Total people participated',
                  style:
                      TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            ],
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
                color: Colors.green.shade700,
                borderRadius: BorderRadius.circular(30)),
            child: Text(total.toString(),
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18)),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: Colors.black),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Menu',
                    style: TextStyle(color: Colors.white, fontSize: 20)),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Ticket History'),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/tickethistorypage');
            },
          ),
          ListTile(
            leading: const Icon(Icons.verified_user),
            title: const Text('User Agreement'),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/agreement');
            },
          ),
          ListTile(
            leading: const Icon(Icons.payment),
            title: const Text('Confirm Payment'),
            onTap: () {
              Navigator.pop(context);
              // Harden: require login before opening payment
              final user = FirebaseAuth.instance.currentUser;
              if (user != null) {
                Navigator.pushNamed(context, '/payment');
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('🔔 Please log in to open payments'),
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 2),
                  ),
                );
                Navigator.pushNamed(context, '/access');
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.contact_mail),
            title: const Text('Contact Us'),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/contact');
            },
          ),
          ListTile(
            leading: Icon(_isLoggedIn ? Icons.logout : Icons.login),
            title: Text(_isLoggedIn ? 'Sign Out' : 'Sign In'),
            onTap: () async {
              Navigator.pop(context);
              if (_isLoggedIn) {
                await FirebaseAuth.instance.signOut();
                _checkLoginStatus();
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Signed out successfully")));
              } else {
                Navigator.pushNamed(context, '/access');
              }
            },
          ),
        ],
      ),
    );
  }
}
