// ticket_history_page.dart
// - No draw status banners (removed REGULAR/GOLDEN running/winners/etc.)
// - Owner-only reads. No writes.
// - Hides archived tickets.
// - Pull-to-refresh + "Clear cache & refresh" action.
// - Caches payment lookups; never infers winners.
// - Payment-status override works for both /payments/* and /golden_payments/*
// - NEW: Also reads users/{uid}/goldenTickets and merges with regular tickets
// - Golden tickets show a "Golden ticket" chip and otherwise render identically.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:animate_do/animate_do.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';

class TicketHistoryPage extends StatefulWidget {
  const TicketHistoryPage({super.key});
  @override
  State<TicketHistoryPage> createState() => _TicketHistoryPageState();
}

class _TicketHistoryPageState extends State<TicketHistoryPage> {
  final _fs = FirebaseFirestore.instance;

  // simple caches for /payments lookups
  final Map<String, List<String>> _numbersCache = {};
  final Map<String, List<String>> _saltsCache = {};
  final Map<String, bool> _confirmedCache = {};
  final Map<String, String> _drawIdCache = {};
  final Map<String, bool> _forNextCache = {};
  final Map<String, String> _statusCache = {}; // 'pending' | 'confirmed' | 'rejected' ...
  final Map<String, Object?> _errors = {};

  void _clearPaymentCache() {
    _numbersCache.clear();
    _saltsCache.clear();
    _confirmedCache.clear();
    _drawIdCache.clear();
    _forNextCache.clear();
    _statusCache.clear();
    _errors.clear();
  }

  Future<void> _refresh() async {
    _clearPaymentCache();
    setState(() {}); // streams will emit again
    await Future.delayed(const Duration(milliseconds: 250));
  }

  String _norm(Object? v) => (v?.toString() ?? '').trim().toLowerCase();

  Future<Map<String, dynamic>> _fetchPayment(String path) async {
    if (_numbersCache.containsKey(path)) {
      return {
        'numbers': _numbersCache[path] ?? <String>[],
        'salts': _saltsCache[path] ?? <String>[],
        'confirmed': _confirmedCache[path] ?? false,
        'drawId': _drawIdCache[path] ?? '',
        'forNextDraw': _forNextCache[path] ?? false,
        'status': _statusCache[path] ?? '',
      };
    }
    try {
      final snap = await _fs.doc(path).get();
      if (!snap.exists) {
        _numbersCache[path] = [];
        _saltsCache[path] = [];
        _confirmedCache[path] = false;
        _drawIdCache[path] = '';
        _forNextCache[path] = false;
        _statusCache[path] = '';
      } else {
        final d = snap.data() ?? <String, dynamic>{};

        final nums = <String>[];
        if (d['lotteryNumbers'] is List) {
          for (final e in (d['lotteryNumbers'] as List)) {
            if (e != null) nums.add(e.toString());
          }
        } else if (d['lotteryNumber'] != null) {
          nums.add(d['lotteryNumber'].toString());
        }

        final salts = <String>[];
        if (d['ticketSalts'] is List) {
          for (final e in (d['ticketSalts'] as List)) {
            if (e != null) salts.add(e.toString());
          }
        }

        final status = _norm(d['status']);
        final confirmed = d['confirmed'] == true || status == 'confirmed';

        _numbersCache[path] = nums;
        _saltsCache[path] = salts;
        _confirmedCache[path] = confirmed;
        _drawIdCache[path] = (d['drawId'] ?? '').toString();
        _forNextCache[path] = d['forNextDraw'] == true;
        _statusCache[path] = status;
      }
    } catch (e) {
      _errors[path] = e;
      _numbersCache[path] = [];
      _saltsCache[path] = [];
      _confirmedCache[path] = false;
      _drawIdCache[path] = '';
      _forNextCache[path] = false;
      _statusCache[path] = '';
    }
    return {
      'numbers': _numbersCache[path]!,
      'salts': _saltsCache[path]!,
      'confirmed': _confirmedCache[path]!,
      'drawId': _drawIdCache[path]!,
      'forNextDraw': _forNextCache[path]!,
      'status': _statusCache[path]!,
    };
  }

  String _fmtTs(Timestamp? ts) {
    if (ts == null) return 'Unknown';
    final d = ts.toDate();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  void _showImage(BuildContext c, String url) {
    showDialog(
      context: c,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: GestureDetector(
          onTap: () => Navigator.of(c).pop(),
          child: InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
        ),
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (!await canLaunchUrl(uri)) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // Heuristic to tag a ticket as Golden without breaking existing data
  bool _isGoldenTicket(Map<String, dynamic> t, {bool fromGoldenCollection = false}) {
    if (fromGoldenCollection) return true;
    final type = _norm(t['type']);
    final drawId = _norm(t['drawId']);
    if (t['isGolden'] == true) return true;
    if (type == 'golden') return true;
    if (drawId.contains('gold')) return true; // e.g., 'golden_2025_01_12'
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.black,
          elevation: 0,
          title: const Text('Ticket History', style: TextStyle(color: Colors.white)),
          leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
        ),
        body: const Center(child: Text('Please sign in to view your ticket history.')),

        // ==== BOTTOM NAV ADDED (not signed in) ====
       bottomNavigationBar: BottomNavigationBar(
  type: BottomNavigationBarType.fixed,              // 4 items, no shifting
  currentIndex: 1,                                  // 0=Home, 1=History (this page), 2=Profile, 3=Winners
  backgroundColor: Colors.black,
  selectedItemColor: Colors.white,
  unselectedItemColor: Colors.white70,
  onTap: (index) {
    if (index == 0) {
      Navigator.pushReplacementNamed(context, '/home'); // <-- use your home route
    } else if (index == 1) {
      // already on History
    } else if (index == 2) {
      Navigator.pushReplacementNamed(context, '/profile');
    } else if (index == 3) {
      Navigator.pushReplacementNamed(context, '/winner');
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

    // Regular + Golden tickets (two collections)
    final regTicketsStream = _fs
        .collection('users')
        .doc(user.uid)
        .collection('tickets')
        .orderBy('date', descending: true)
        .snapshots();

    final goldenTicketsStream = _fs
        .collection('users')
        .doc(user.uid)
        .collection('goldenTickets')
        .orderBy('date', descending: true)
        .snapshots();

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(65),
        child: AppBar(
          backgroundColor: Colors.black,
          elevation: 0,
          centerTitle: true,
          title: Text('Ticket History',
              style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
          leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
          actions: [
            IconButton(
              tooltip: 'Clear cache & refresh',
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _refresh,
            ),
          ],
        ),
      ),
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
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.06)),
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

          // No draw status banner. Just the combined list.
          Column(
            children: [
              const SizedBox(height: 90),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: regTicketsStream,
                    builder: (context, regSnap) {
                      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: goldenTicketsStream,
                        builder: (context, goldSnap) {
                          final regDocs = regSnap.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                          final goldDocs = goldSnap.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];

                          // If neither has data yet and one is still waiting, show spinner
                          if ((regSnap.connectionState == ConnectionState.waiting ||
                               goldSnap.connectionState == ConnectionState.waiting) &&
                              regDocs.isEmpty && goldDocs.isEmpty) {
                            return const Center(child: CircularProgressIndicator(color: Colors.white));
                          }

                          // Build combined list while hiding archived
                          final combined = <Map<String, dynamic>>[];

                          for (final d in regDocs) {
                            final data = d.data();
                            if (data['archived'] == true) continue;
                            combined.add({'doc': d, 'golden': false});
                          }
                          for (final d in goldDocs) {
                            final data = d.data();
                            if (data['archived'] == true) continue;
                            combined.add({'doc': d, 'golden': true});
                          }

                          if (combined.isEmpty) {
                            return const Center(
                              child: Text('No ticket history found.', style: TextStyle(color: Colors.white)),
                            );
                          }

                          // Sort by date desc, falling back safely
                          combined.sort((a, b) {
                            final da = a['doc'].data()['date'];
                            final db = b['doc'].data()['date'];
                            final ta = (da is Timestamp) ? da.toDate().millisecondsSinceEpoch : 0;
                            final tb = (db is Timestamp) ? db.toDate().millisecondsSinceEpoch : 0;
                            return tb.compareTo(ta);
                          });

                          return ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                            itemCount: combined.length,
                            itemBuilder: (context, i) {
                              final doc = combined[i]['doc'] as QueryDocumentSnapshot<Map<String, dynamic>>;
                              final fromGoldenCollection = combined[i]['golden'] as bool;
                              final t = doc.data();

                              final selectedAmounts = (t['selectedAmounts'] is List)
                                  ? (t['selectedAmounts'] as List).map((e) => 'Rs. ${e.toString()}').join(', ')
                                  : '-';
                              final totalAmount = t['totalAmount'] ?? t['amount'] ?? '-';
                              final ticketCount = t['ticketCount']?.toString() ?? '-';

                              final statusRawLocal = _norm(t['status'] ?? (t['confirmed'] == true ? 'confirmed' : 'pending'));
                              final isRejectedLocal = statusRawLocal == 'rejected';
                              final isConfirmedLocal = statusRawLocal == 'confirmed' || t['confirmed'] == true;
                              final isExpired = statusRawLocal == 'expired';

                              final receiptUrl = (t['receiptUrl'] as String?) ?? '';

                              final ticketNumsLocal = <String>[];
                              if (t['lotteryNumbers'] is List) {
                                for (final e in (t['lotteryNumbers'] as List)) {
                                  if (e != null) ticketNumsLocal.add(e.toString());
                                }
                              } else if (t['lotteryNumber'] != null) {
                                ticketNumsLocal.add(t['lotteryNumber'].toString());
                              }

                              final saltsLocal = <String>[];
                              if (t['ticketSalts'] is List) {
                                for (final e in (t['ticketSalts'] as List)) {
                                  if (e != null) saltsLocal.add(e.toString());
                                }
                              }

                              final forNextDrawLocal = t['forNextDraw'] == true;
                              final drawIdLocal = (t['drawId'] ?? '').toString();
                              final paymentRef = (t['paymentRef'] is String) ? t['paymentRef'] as String : '';

                              final isGolden = _isGoldenTicket(t, fromGoldenCollection: fromGoldenCollection);

                              Widget _chip({required IconData icon, required String label, Color? bg, Color? fg}) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(color: bg ?? Colors.grey.shade200, borderRadius: BorderRadius.circular(10)),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(icon, size: 14, color: fg ?? Colors.black87),
                                    const SizedBox(width: 6),
                                    Text(label, style: TextStyle(color: fg ?? Colors.black87, fontWeight: FontWeight.w600)),
                                  ]),
                                );
                              }

                              Widget card({
                                required bool finalConfirmed,
                                required bool finalRejected,
                                required List<String> numbers,
                                required List<String> salts,
                                required bool queuedNext,
                                required String drawIdText,
                                bool showRefError = false,
                              }) {
                                final badgeColors = finalRejected
                                    ? [Colors.red.shade400, Colors.redAccent]
                                    : (isExpired
                                        ? [Colors.red.shade400, Colors.redAccent]
                                        : (finalConfirmed
                                            ? [Colors.green.shade400, Colors.green]
                                            : [Colors.orangeAccent, Colors.deepOrange]));

                                final numbersToShow = finalRejected ? <String>[] : numbers;

                                // pair number+salt for copy when confirmed
                                final pairs = <Map<String, String>>[];
                                if (finalConfirmed && numbersToShow.isNotEmpty && salts.isNotEmpty) {
                                  final n = numbersToShow.length < salts.length ? numbersToShow.length : salts.length;
                                  for (int k = 0; k < n; k++) {
                                    pairs.add({'number': numbersToShow[k], 'salt': salts[k]});
                                  }
                                }

                                final effectiveLabel = finalRejected
                                    ? 'Rejected'
                                    : (finalConfirmed
                                        ? 'Confirmed'
                                        : (statusRawLocal.isNotEmpty ? statusRawLocal : 'Pending'));

                                return FadeInUp(
                                  delay: Duration(milliseconds: 60 * (i % 6)),
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(vertical: 10),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.96),
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(color: Colors.black.withOpacity(0.14), blurRadius: 26, offset: const Offset(0, 12))
                                      ],
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                                Text('Total: Rs. $totalAmount',
                                                    style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
                                                const SizedBox(height: 6),
                                                Text('Selected: $selectedAmounts',
                                                    style: GoogleFonts.poppins(fontSize: 14, color: Colors.black54)),
                                              ]),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: finalRejected
                                                    ? Colors.red.shade50
                                                    : (finalConfirmed ? Colors.green.shade50 : Colors.orange.shade50),
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Row(children: [
                                                Icon(
                                                  finalRejected
                                                      ? Icons.cancel
                                                      : (finalConfirmed ? Icons.check_circle : Icons.hourglass_top),
                                                  size: 16,
                                                  color: finalRejected
                                                      ? Colors.red.shade700
                                                      : (finalConfirmed ? Colors.green.shade700 : Colors.deepOrange),
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  effectiveLabel,
                                                  style: TextStyle(
                                                    color: finalRejected
                                                        ? Colors.red.shade700
                                                        : (finalConfirmed ? Colors.green.shade700 : Colors.deepOrange),
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ]),
                                            ),
                                          ],
                                        ),

                                        const SizedBox(height: 10),

                                        // chips
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            if (drawIdText.isNotEmpty)
                                              _chip(icon: Icons.tag, label: 'Draw ID: $drawIdText'),
                                            _chip(
                                              icon: queuedNext ? Icons.schedule : Icons.play_arrow,
                                              label: queuedNext ? 'Queued for NEXT draw' : 'This draw',
                                              bg: queuedNext ? Colors.blue.shade50 : Colors.green.shade50,
                                              fg: queuedNext ? Colors.blue.shade800 : Colors.green.shade800,
                                            ),
                                            if (salts.isNotEmpty)
                                              _chip(
                                                icon: Icons.verified_user,
                                                label: 'Verification salts: ${salts.length}',
                                                bg: Colors.teal.shade50,
                                                fg: Colors.teal.shade800,
                                              ),
                                            if (isGolden)
                                              _chip(
                                                icon: Icons.star,
                                                label: 'Golden ticket',
                                                bg: Colors.amber.shade50,
                                                fg: Colors.amber.shade800,
                                              ),
                                          ],
                                        ),

                                        const SizedBox(height: 12),

                                        // numbers (never if rejected)
                                        if (numbersToShow.isNotEmpty) ...[
                                          const Text('Lottery Numbers:',
                                              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                                          const SizedBox(height: 8),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 6,
                                            children: numbersToShow.map((n) {
                                              return Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                decoration: BoxDecoration(
                                                  color: Colors.grey.shade200,
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                                  SelectableText(n,
                                                      style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold)),
                                                  const SizedBox(width: 6),
                                                  GestureDetector(
                                                    onTap: () {
                                                      Clipboard.setData(ClipboardData(text: n));
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        const SnackBar(content: Text('Lottery number copied')),
                                                      );
                                                    },
                                                    child: const Icon(Icons.copy, size: 18),
                                                  ),
                                                ]),
                                              );
                                            }).toList(),
                                          ),
                                          const SizedBox(height: 12),
                                        ],

                                        // verification block
                                        if (pairs.isNotEmpty) ...[
                                          Row(children: [
                                            const Icon(Icons.lock_outline, size: 18, color: Colors.black54),
                                            const SizedBox(width: 6),
                                            const Text('Verification', style: TextStyle(fontWeight: FontWeight.bold)),
                                            const Spacer(),
                                            TextButton.icon(
                                              onPressed: () {
                                                Clipboard.setData(ClipboardData(text: jsonEncode({'pairs': pairs})));
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(content: Text('Verification data copied')),
                                                );
                                              },
                                              icon: const Icon(Icons.copy, size: 16),
                                              label: const Text('Copy data'),
                                            ),
                                          ]),
                                          const SizedBox(height: 6),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 6,
                                            children: pairs.map((p) {
                                              final s = p['salt'] ?? '';
                                              final masked = s.length > 12 ? '${s.substring(0, 6)}…${s.substring(s.length - 4)}' : s;
                                              return Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                decoration: BoxDecoration(
                                                  color: Colors.grey.shade100,
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text('${p['number']} • salt $masked',
                                                    style: const TextStyle(fontSize: 12, color: Colors.black87)),
                                              );
                                            }).toList(),
                                          ),
                                          const SizedBox(height: 12),
                                        ] else if (!finalConfirmed && salts.isNotEmpty) ...[
                                          Row(children: const [
                                            Icon(Icons.verified, size: 18, color: Colors.black54),
                                            SizedBox(width: 6),
                                            Text('Proof seeds secured (awaiting confirmation)',
                                                style: TextStyle(fontSize: 12, color: Colors.black54)),
                                          ]),
                                          const SizedBox(height: 12),
                                        ],

                                        if (showRefError && numbersToShow.isEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(bottom: 8.0),
                                            child: Row(children: const [
                                              Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                                              SizedBox(width: 8),
                                              Expanded(
                                                child: Text('Lottery numbers unavailable (support).',
                                                    style: TextStyle(color: Colors.black54)),
                                              ),
                                            ]),
                                          ),

                                        Text('Tickets Bought: $ticketCount', style: GoogleFonts.poppins(fontSize: 15)),
                                        const SizedBox(height: 6),
                                        Text('Date: ${_fmtTs(t['date'] is Timestamp ? t['date'] as Timestamp : null)}',
                                            style: GoogleFonts.poppins(fontSize: 14, color: Colors.black54)),

                                        const SizedBox(height: 12),

                                        if (receiptUrl.isNotEmpty)
                                          GestureDetector(
                                            onTap: () => _showImage(context, receiptUrl),
                                            onLongPress: () => _openUrl(receiptUrl),
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(12),
                                              child: Image.network(
                                                receiptUrl,
                                                height: 140,
                                                width: double.infinity,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) => Container(
                                                  height: 140,
                                                  color: Colors.grey.shade200,
                                                  child: const Center(child: Text('Could not load image')),
                                                ),
                                              ),
                                            ),
                                          ),

                                        const SizedBox(height: 12),

                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(colors: badgeColors),
                                              borderRadius: BorderRadius.circular(25),
                                              boxShadow: const [
                                                BoxShadow(color: Colors.black38, offset: Offset(0, 4), blurRadius: 6)
                                              ],
                                            ),
                                            child: Text(
                                              finalRejected
                                                  ? 'Rejected'
                                                  : (finalConfirmed
                                                      ? 'Confirmed'
                                                      : (statusRawLocal.isNotEmpty ? statusRawLocal : 'Pending')),
                                              style: GoogleFonts.poppins(
                                                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                            ),
                                          ),
                                        ),
                                      ]),
                                    ),
                                  ),
                                );
                              }

                              // If we have a payments ref and local is NOT already rejected,
                              // consult payments/golden_payments to override status ASAP.
                              if (paymentRef.isNotEmpty && !isRejectedLocal) {
                                return FutureBuilder<Map<String, dynamic>>(
                                  future: _fetchPayment(paymentRef),
                                  builder: (context, f) {
                                    if (f.connectionState == ConnectionState.waiting) {
                                      return Stack(children: [
                                        card(
                                          finalConfirmed: isConfirmedLocal,
                                          finalRejected: isRejectedLocal,
                                          numbers: ticketNumsLocal,
                                          salts: saltsLocal,
                                          queuedNext: forNextDrawLocal,
                                          drawIdText: drawIdLocal,
                                        ),
                                        const Positioned(
                                          right: 18,
                                          top: 18,
                                          child: SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          ),
                                        ),
                                      ]);
                                    }
                                    final data = f.data ??
                                        {
                                          'numbers': <String>[],
                                          'salts': <String>[],
                                          'confirmed': false,
                                          'drawId': '',
                                          'forNextDraw': false,
                                          'status': ''
                                        };
                                    final fetchedNums = (data['numbers'] as List).map((e) => e.toString()).toList();
                                    final fetchedSalts = (data['salts'] as List).map((e) => e.toString()).toList();
                                    final fetchedStatus = _norm(data['status']);
                                    final fetchedConfirmed = (fetchedStatus == 'confirmed') || (data['confirmed'] == true);
                                    final fetchedRejected = fetchedStatus == 'rejected';
                                    final fetchedDrawId = (data['drawId'] ?? '').toString();
                                    final fetchedForNext = data['forNextDraw'] == true;

                                    // Merge rules (source-of-truth: payments override)
                                    final finalRejected = fetchedRejected || isRejectedLocal;
                                    final finalConfirmed = (!finalRejected) && (isConfirmedLocal || fetchedConfirmed);

                                    // Numbers: if rejected => none; else prefer payments if it has them,
                                    // otherwise keep local.
                                    final finalNums = finalRejected
                                        ? <String>[]
                                        : (fetchedNums.isNotEmpty ? fetchedNums : ticketNumsLocal);

                                    // Salts: prefer local (already in user ticket) otherwise fetched.
                                    final finalSalts = saltsLocal.isNotEmpty ? saltsLocal : fetchedSalts;

                                    final drawIdText = drawIdLocal.isNotEmpty ? drawIdLocal : fetchedDrawId;
                                    final queuedNext = forNextDrawLocal || fetchedForNext;

                                    final showErr = _errors.containsKey(paymentRef) && _errors[paymentRef] != null;

                                    return card(
                                      finalConfirmed: finalConfirmed,
                                      finalRejected: finalRejected,
                                      numbers: finalNums,
                                      salts: finalSalts,
                                      queuedNext: queuedNext,
                                      drawIdText: drawIdText,
                                      showRefError: showErr,
                                    );
                                  },
                                );
                              }

                              // Otherwise render from ticket doc only
                              return card(
                                finalConfirmed: isConfirmedLocal,
                                finalRejected: isRejectedLocal,
                                numbers: ticketNumsLocal,
                                salts: saltsLocal,
                                queuedNext: forNextDrawLocal,
                                drawIdText: drawIdLocal,
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),

      // ==== BOTTOM NAV ADDED (signed in) ====
      bottomNavigationBar: BottomNavigationBar(
  type: BottomNavigationBarType.fixed,              // 4 items, no shifting
  currentIndex: 1,                                  // 0=Home, 1=History (this page), 2=Profile, 3=Winners
  backgroundColor: Colors.black,
  selectedItemColor: Colors.white,
  unselectedItemColor: Colors.white70,
  onTap: (index) {
    if (index == 0) {
      Navigator.pushReplacementNamed(context, '/home'); // <-- use your home route
    } else if (index == 1) {
      // already on History
    } else if (index == 2) {
      Navigator.pushReplacementNamed(context, '/profile');
    } else if (index == 3) {
      Navigator.pushReplacementNamed(context, '/winner');
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
}
