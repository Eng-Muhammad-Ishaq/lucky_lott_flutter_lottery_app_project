// winner_page.dart — Regular ↔ Golden switch, countdown + confetti
// GOLDEN: shows prize NAME + IMAGE + PRICE (mirrors Home assets/labels), with BIGGER cards.
// REGULAR: keeps numeric award chips from config/awards.
//
// Golden prizes (must match Home):
//  1) Honda 70CC (≈ Rs. 100,000)      -> assets/prizes/bike.png
//  2) iPhone 10 Pro/XS Max (Non-PTA)  -> assets/prizes/iphone.png
//  3) Smart Watch (≈ Rs. 10,000)      -> assets/prizes/watch.png
//
// Firestore roots:
//   Regular: draws/latest, previous_winners, config/awards
//   Golden : golden_draws/latest, previous_winners_golden
//
// NOTE: No Firestore read for Golden prizes (we mirror Home’s hardcoded assets).

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:animate_do/animate_do.dart';
import 'package:flutter/services.dart';
import 'package:confetti/confetti.dart';

enum DrawType { regular, golden }

extension _NS on DrawType {
  String get drawsRoot =>
      (this == DrawType.golden) ? 'golden_draws' : 'draws';
  String get prevWinnersRoot =>
      (this == DrawType.golden) ? 'previous_winners_golden' : 'previous_winners';
  String get awardsDoc => 'awards'; // REGULAR numeric amounts only
  String get barLabel =>
      (this == DrawType.golden) ? 'G-Lott Result' : 'Lott Result';
}

class _Prize {
  final String name;
  final String priceText;
  final String asset;
  const _Prize(this.name, this.priceText, this.asset);
}

// Mirror of Home's Golden prize data (images + labels)
const List<_Prize> _goldenPrizesHome = <_Prize>[
  _Prize('Honda 70CC', '≈ Rs. 100,000', 'assets/prizes/bike.png'),
  _Prize('iPhone 8 Plus', '≈ Rs. 50,000-Non PTA', 'assets/prizes/iphone.png'),
  _Prize('Smart Watch', '≈ Rs. 10,000', 'assets/prizes/watch.png'),
];

class WinnerPage extends StatefulWidget {
  const WinnerPage({super.key});
  @override
  State<WinnerPage> createState() => _WinnerPageState();
}

class _WinnerPageState extends State<WinnerPage> {
  final _fs = FirebaseFirestore.instance;

  DrawType _type = DrawType.regular;

  // subs
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _drawSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _prevWinSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _awardsSub; // regular only

  Timer? _timer;

  // Regular awards (numeric)
  List<int> _awardValues = [0, 0, 0];

  // timers/flags
  Duration _drawRemaining = Duration.zero;
  Duration _winnersPhaseRemaining = Duration.zero;
  bool _isFinalizing = false;
  bool _isWinnersPhase = false;
  bool _lastKnownRunning = false;
  static const Duration _finalizingGrace = Duration(seconds: 3);

  // 3 winners
  List<Map<String, dynamic>?> _winners =
      List<Map<String, dynamic>?>.filled(3, null, growable: false);

  // previous winners
  List<Map<String, dynamic>> _previousWinners = [];

  // confetti
  late final ConfettiController _confetti;
bool _didPlayConfetti = false;

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(duration: const Duration(seconds: 3));
    _bindForType(_type);
  }

  @override
  void dispose() {
    _confetti.dispose();
    _timer?.cancel();
    _cancelSubs();
    super.dispose();
  }

  void _cancelSubs() {
    _drawSub?.cancel();
    _prevWinSub?.cancel();
    _awardsSub?.cancel();
  }

  void _bindForType(DrawType t) {
  _cancelSubs();
  setState(() {
    _winners =
        List<Map<String, dynamic>?>.filled(3, null, growable: false);
    _previousWinners = [];
    _drawRemaining = Duration.zero;
    _winnersPhaseRemaining = Duration.zero;
    _isFinalizing = false;
    _isWinnersPhase = false;

    // >>> Add these two lines <<<
    _didPlayConfetti = false; // re-arm confetti when switching modes
    _confetti.stop();         // make sure it starts clean
  });

  _listenDraw(t);
  _listenPreviousWinners(t);
  if (t == DrawType.regular) _listenRegularAwards(); // numeric only
}


  void _switchType(DrawType t) {
    if (_type == t) return;
    _type = t;
    _bindForType(t);
  }

  // ---------- helpers ----------
  String _norm(Object? v) => (v?.toString() ?? '').trim().toLowerCase();
  bool _isWinnerPhaseStatus(String s) {
    s = _norm(s);
    return s == 'winners_announced' || s == 'winner' || s == 'winners';
  }

  List<Map<String, dynamic>?> _normalizeThree(dynamic winnersField) {
    final byPos = <int, Map<String, dynamic>>{};
    if (winnersField is List) {
      for (final w in winnersField) {
        if (w is Map) {
          final p = int.tryParse('${w['position'] ?? ''}');
          if (p != null && p >= 1 && p <= 3 && !byPos.containsKey(p)) {
            byPos[p] = Map<String, dynamic>.from(w);
          }
        }
      }
    }
    return List<Map<String, dynamic>?>.generate(3, (i) => byPos[i + 1]);
  }

  void _tickCountdown({
    required DateTime target,
    required void Function(Duration) onTick,
    required VoidCallback onFinish,
  }) {
    _timer?.cancel();
    Duration d = target.difference(DateTime.now());
    if (d.isNegative) d = Duration.zero;
    onTick(d);

    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final left = target.difference(DateTime.now());
      if (left.inSeconds <= 0) {
        t.cancel();
        onFinish();
      } else {
        onTick(left);
      }
    });
  }

  String _fmtDur(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final days = d.inDays, hh = d.inHours % 24, mm = d.inMinutes % 60, ss = d.inSeconds % 60;
    if (days > 0) return '$days days ${two(hh)}:${two(mm)}:${two(ss)}';
    return '${two(hh)}:${two(mm)}:${two(ss)}';
  }

  Color _posBadge(int pos) {
    switch (pos) {
      case 1:
        return const Color(0xFFFFD700);
      case 2:
        return const Color(0xFFC0C0C0);
      case 3:
        return const Color(0xFFCD7F32);
      default:
        return Colors.grey;
    }
  }

  String _ordinal(int pos) =>
      (pos == 1) ? '1st' : (pos == 2) ? '2nd' : (pos == 3) ? '3rd' : '$pos';

  String _winnerName(Map<String, dynamic>? w) {
    if (w == null) return '';
    for (final k in const ['buyerName', 'userName', 'name', 'displayName']) {
      final v = w[k];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString();
    }
    return '';
  }

  dynamic _winnerNumber(Map<String, dynamic>? w) {
    if (w == null) return null;
    for (final k in const ['lotteryNumber', 'number', 'ticket', 'ticketNumber']) {
      if (w[k] != null) return w[k];
    }
    return null;
  }

  int? _toInt(Object? x) {
    if (x is num) return x.toInt();
    if (x is String) return int.tryParse(x);
    return null;
  }

  // ---------- subscriptions ----------
  void _listenRegularAwards() {
    _awardsSub = _fs
        .collection('config')
        .doc(_type.awardsDoc)
        .snapshots()
        .listen((snap) {
      var vals = [0, 0, 0];
      final data = snap.data();
      if (data != null) {
        final v = data['values'];
        if (v is List && v.length >= 3) {
          for (var i = 0; i < 3; i++) {
            final n = _toInt(v[i]);
            if (n != null) vals[i] = n;
          }
        } else {
          final first = _toInt(data['first'] ?? data['pos1'] ?? data['1']);
          final second = _toInt(data['second'] ?? data['pos2'] ?? data['2']);
          final third = _toInt(data['third'] ?? data['pos3'] ?? data['3']);
          vals = [first ?? 0, second ?? 0, third ?? 0];
        }
      }
      if (mounted) setState(() => _awardValues = vals);
    }, onError: (_) {});
  }

  void _listenDraw(DrawType t) {
    final drawRef = _fs.collection(t.drawsRoot).doc('latest');
    _drawSub = drawRef.snapshots().listen((snap) {
      if (!mounted) return;
      if (!snap.exists) {
        setState(() {
          _winners =
              List<Map<String, dynamic>?>.filled(3, null, growable: false);
          _isWinnersPhase = false;
          _isFinalizing = false;
          _drawRemaining = Duration.zero;
          _winnersPhaseRemaining = Duration.zero;
        });
        return;
      }

      final data = snap.data() ?? <String, dynamic>{};
      final normalized = _normalizeThree(data['winners']);
      final status = _norm(data['status']);
      _lastKnownRunning = (status == 'running');

      DateTime? end;
      if (data['endAt'] is Timestamp) {
        end = (data['endAt'] as Timestamp).toDate();
      } else if (data['drawDate'] is Timestamp) {
        end = (data['drawDate'] as Timestamp).toDate();
      }

      if (status == 'running') {
        if (end != null) {
          final now = DateTime.now();
          if (now.isAfter(end.add(_finalizingGrace))) {
            setState(() {
              _isFinalizing = true;
              _drawRemaining = Duration.zero;
            });
          } else {
            _tickCountdown(
              target: end,
              onTick: (d) => setState(() => _drawRemaining = d),
              onFinish: () {
                if (!mounted) return;
                if (_lastKnownRunning) {
                  setState(() {
                    _isFinalizing = true;
                    _drawRemaining = Duration.zero;
                  });
                }
              },
            );
          }
        } else {
          setState(() => _drawRemaining = Duration.zero);
        }
        setState(() {
          _isWinnersPhase = false;
          _winners = normalized;
        });
        return;
      }

      if (status == 'stop' || status == 'stopped' || status == 'finalizing') {
        setState(() {
          _isFinalizing = true;
          _isWinnersPhase = false;
          _drawRemaining = Duration.zero;
          _winners = normalized;
        });
        return;
      }

      if (_isWinnerPhaseStatus(status)) {
        DateTime? winnersEnd;
        if (data['winnersPhaseEnd'] is Timestamp) {
          winnersEnd = (data['winnersPhaseEnd'] as Timestamp).toDate();
        }
        if (winnersEnd != null && DateTime.now().isBefore(winnersEnd)) {
          _tickCountdown(
            target: winnersEnd,
            onTick: (d) => setState(() => _winnersPhaseRemaining = d),
            onFinish: () =>
                mounted ? setState(() => _winnersPhaseRemaining = Duration.zero) : null,
          );
        } else {
          setState(() => _winnersPhaseRemaining = Duration.zero);
        }

        setState(() {
          _isWinnersPhase = true;
          _isFinalizing = false;
          _drawRemaining = Duration.zero;
          _winners = normalized;
        });

        if (!_didPlayConfetti) {
          _didPlayConfetti = true;
          _confetti.play();
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) _confetti.stop();
          });
        }
        return;
      }

      setState(() {
        _isWinnersPhase = false;
        _isFinalizing = false;
        _drawRemaining = Duration.zero;
        _winnersPhaseRemaining = Duration.zero;
        _winners = normalized;
      });
    }, onError: (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Draw listener error: $e')),
      );
    });
  }

  void _listenPreviousWinners(DrawType t) {
    _prevWinSub = _fs
        .collection(t.prevWinnersRoot)
        .orderBy('position', descending: false)
        .snapshots()
        .listen((snap) {
      final list = <Map<String, dynamic>>[];
      try {
        for (final d in snap.docs) {
          list.add({'docId': d.id, ...d.data()});
        }
      } catch (_) {}
      if (mounted) setState(() => _previousWinners = list);
    }, onError: (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Previous winners error: $e')),
      );
    });
  }

  // ---------- actions ----------
  Future<void> _manualRefresh() async {
    try {
      final snap = await _fs.collection(_type.drawsRoot).doc('latest').get();
      if (!mounted) return;
      if (!snap.exists) {
        setState(() {
          _winners =
              List<Map<String, dynamic>?>.filled(3, null, growable: false);
          _isWinnersPhase = false;
          _isFinalizing = false;
        });
        return;
      }
      final data = snap.data() ?? {};
      setState(() {
        _winners = _normalizeThree(data['winners']);
        final status = _norm(data['status']);
        _isWinnersPhase = _isWinnerPhaseStatus(status);
        _isFinalizing =
            (status == 'stop' || status == 'stopped' || status == 'finalizing') ||
                _isFinalizing;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Refresh failed: $e')),
      );
    }
  }


  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final statusLabel =
        _isWinnersPhase ? 'Winners Announced' : (_isFinalizing ? 'Finalizing' : 'Draw');
    final hint = _isWinnersPhase
        ? 'Congratulations to the winners!'
        : (_isFinalizing ? 'Finalizing — announcing winners shortly.' : 'Draw Is Live');

    return Scaffold(
      extendBodyBehindAppBar: true,
  appBar: AppBar(
    backgroundColor: Colors.black,
    elevation: 0,
    centerTitle: true,
    title: const Text(
      'Winners',
      style: TextStyle(color: Colors.white),
    ),
    leading: IconButton(
      icon: const Icon(Icons.arrow_back, color: Colors.white),
      onPressed: () => Navigator.maybePop(context),
    ),
  ),
  // ...rest of your code


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

          SafeArea(
            child: RefreshIndicator(
              onRefresh: _manualRefresh,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                child: Column(
                  children: [
                    const SizedBox(height: 6),
                    Bounce(
                      infinite: true,
                      duration: const Duration(milliseconds: 1200),
                      from: 6,
                      child: CircleAvatar(
                        radius: 56,
                        backgroundColor: Colors.white.withOpacity(0.12),
                        child: const Icon(Icons.emoji_events,
                            size: 64, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 18),
                    FadeInUp(
                      duration: const Duration(milliseconds: 700),
                      child: Text(
                        statusLabel,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FadeInUp(
                      delay: const Duration(milliseconds: 150),
                      duration: const Duration(milliseconds: 700),
                      child: Text(
                        hint,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.92),
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Switch above the result bar
                    _typeSwitchPill(),
                    const SizedBox(height: 12),

                    // Result bar with countdown
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.96),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.14),
                              blurRadius: 26,
                              offset: const Offset(0, 12),
                            )
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(children: [
                              Icon(Icons.verified, color: Colors.green.shade700),
                              const SizedBox(width: 10),
                              Text('🎯 ${_type.barLabel}',
                                  style: const TextStyle(
                                      fontSize: 18, fontWeight: FontWeight.w600)),
                            ]),
                            if (_isFinalizing)
                              Row(children: const [
                                SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2)),
                                SizedBox(width: 8),
                                Text('Finalizing...'),
                              ])
                            else if (_isWinnersPhase)
                              (_winnersPhaseRemaining > Duration.zero)
                                  ? Text('Phase ends in ${_fmtDur(_winnersPhaseRemaining)}',
                                      style: const TextStyle(
                                          fontSize: 14, fontWeight: FontWeight.w500))
                                  : const Text('Winners Phase',
                                      style: TextStyle(
                                          fontSize: 14, fontWeight: FontWeight.w700))
                            else
                              Text(_fmtDur(_drawRemaining),
                                  style: const TextStyle(
                                      fontSize: 14, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ),

                    if (_isFinalizing) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(12)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white)),
                            SizedBox(width: 12),
                            Text('Finalizing winners — announcing shortly',
                                style: TextStyle(color: Colors.white)),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 26),

                    // Three winner cards
                    ..._renderWinners(_winners),

                    const SizedBox(height: 28),

                    // Previous winners
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6.0, vertical: 6.0),
                      child: Column(children: const [
                        Icon(Icons.history, color: Colors.white70),
                        SizedBox(height: 6),
                        Text('Previous Winners',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                        SizedBox(height: 6),
                        Divider(color: Colors.white24, thickness: 1),
                      ]),
                    ),
                    if (_previousWinners.isNotEmpty)
                      Column(
                        children: _previousWinners.map((w) {
                          final pos =
                              int.tryParse('${w['position'] ?? ''}') ?? 0;
                          final name = (w['userName'] ??
                                  w['name'] ??
                                  w['buyerName'] ??
                                  '')
                              .toString();
                          final number = (w['lotteryNumber'] ??
                                  w['number'] ??
                                  w['ticketNumber'] ??
                                  '')
                              .toString();
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: _previousWinnerCard(
                                position: pos, name: name, number: number),
                          );
                        }).toList(),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text('No previous winners yet.',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.9))),
                      ),

                    const SizedBox(height: 26),
                    FadeInUp(
                      delay: const Duration(milliseconds: 300),
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

          // Confetti overlay
          IgnorePointer(
            child: Align(
              alignment: Alignment.center,
              child: ConfettiWidget(
                confettiController: _confetti,
                blastDirectionality: BlastDirectionality.explosive,
                shouldLoop: false,
                emissionFrequency: 0.05,
                numberOfParticles: 30,
                gravity: 0.7,
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
  type: BottomNavigationBarType.fixed, // 4 items, no shifting
  currentIndex: 3, // 0=Home, 1=History, 2=Profile, 3=Winners (this page)
  backgroundColor: Colors.black,
  selectedItemColor: Colors.white,
  unselectedItemColor: Colors.white70,
  onTap: (index) {
    if (index == 0) {
      Navigator.pushReplacementNamed(context, '/home'); // use '/' if that's your Home route
    } else if (index == 1) {
      Navigator.pushReplacementNamed(context, '/tickethistorypage');
    } else if (index == 2) {
      Navigator.pushReplacementNamed(context, '/profile');
    } else if (index == 3) {
      // already on Winners
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

  // ---------- UI pieces ----------
  Widget _typeSwitchPill() {
    final onReg = _type == DrawType.regular;
    final onGold = _type == DrawType.golden;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.96),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.14),
              blurRadius: 20,
              offset: const Offset(0, 10),
            )
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => _switchType(DrawType.regular),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: onReg ? Colors.green.shade600 : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      'Lott Result',
                      style: TextStyle(
                        color: onReg ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: InkWell(
                onTap: () => _switchType(DrawType.golden),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: onGold ? Colors.amber.shade700 : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      'Golden Lott Result',
                      style: TextStyle(
                        color: onGold ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _renderWinners(List<Map<String, dynamic>?> winners) {
    return [
      _winnerCard(position: 1, data: winners[0], color: Colors.greenAccent.shade400),
      const SizedBox(height: 18),
      _winnerCard(position: 2, data: winners[1], color: Colors.blueAccent),
      const SizedBox(height: 18),
      _winnerCard(position: 3, data: winners[2], color: Colors.orangeAccent.shade200),
    ];
  }

Widget _winnerCard({
  required int position,
  required Map<String, dynamic>? data,
  required Color color,
}) {
  final Color badge = _posBadge(position);

  // Only Golden keeps the prize tile visible while data is null.
  final bool isGold = _type == DrawType.golden;
  final bool waiting = isGold && data == null;

  if (data == null && !isGold) {
    return _placeholderCard(position: position, color: color.withOpacity(0.95));
  }

  final number = (data != null) ? (_winnerNumber(data)?.toString() ?? '—') : '—';
  final computedName = (data != null) ? _winnerName(data) : '';
  final name = computedName.isEmpty ? ((data != null) ? 'Anonymous' : '—') : computedName;

  // Prize widget (Golden) OR award chip (Regular)
  final Widget rewardWidget =
      (_type == DrawType.golden) ? _goldenPrizeTile(position) : _awardChip(position);

  return Container(
    width: double.infinity,
    // Bigger height for GOLDEN cards so image + text breathe
    constraints: BoxConstraints(
      minHeight: (_type == DrawType.golden) ? 280 : 168, // keep your increased size
    ),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [color.withOpacity(0.96), color.withOpacity(0.82)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(18),
      boxShadow: const [
        BoxShadow(color: Colors.black26, blurRadius: 14, offset: Offset(0, 8))
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header: badge + Winner + reward (award chip or prize tile)
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: badge,
              child: Text(
                _ordinal(position),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Colors.black87,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Winner',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87)),
                  const SizedBox(height: 8),
                  rewardWidget, // image+name+price (Golden) OR numeric award (Regular)
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        // Full-width info tile
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))
            ],
          ),
          child: waiting
              // SINGLE, CENTERED LOADING (Golden while waiting)
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Center(
                    child: SizedBox(
                      height: 18,
                      child: _AnimatedLoadingDots(),
                    ),
                  ),
                )
              // NORMAL: Name + Ticket rows
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Icon(Icons.person_outline, size: 18, color: Colors.black54),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Ticket row
                    Row(
                      children: [
                        const Icon(Icons.confirmation_number_outlined,
                            size: 18, color: Colors.black54),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Ticket: $number',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.black87,
                                fontWeight: FontWeight.w600,
                                fontSize: 15),
                          ),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          onLongPress: () async {
                            await Clipboard.setData(ClipboardData(text: number));
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Ticket number copied')),
                            );
                          },
                          child: const Icon(Icons.copy, size: 18, color: Colors.black87),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ],
    ),
  );
}


  // Golden prize tile (BIG image + name + price) — mirrors Home
  Widget _goldenPrizeTile(int position) {
    final idx = position - 1;
    if (idx < 0 || idx >= _goldenPrizesHome.length) return const SizedBox.shrink();
    final p = _goldenPrizesHome[idx];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              // >>> Bigger image for Golden prize
              width: 72,
              height: 72,
              child: Image.asset(
                p.asset,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.image_not_supported_outlined, size: 32),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Prize name
              Text(
                p.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Colors.black87,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 4),
              // Prize price
              Text(
                p.priceText,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _placeholderCard({
    required int position,
    required Color color,
  }) {
    final rewardSkeleton = (_type == DrawType.golden)
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: const [
              SizedBox(
                width: 56,
                height: 56,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: Colors.black12),
                ),
              ),
              SizedBox(width: 10),
              SizedBox(
                width: 160,
                height: 12,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: Colors.black12),
                ),
              ),
            ]),
          )
        : _awardChip(position);

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(
        // >>> Bigger placeholder height to match Golden visual
        minHeight: (_type == DrawType.golden) ? 214 : 160,
      ),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withOpacity(0.85)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, 6))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: _posBadge(position),
                child: Text(
                  _ordinal(position),
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.black87),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Winner',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.black87)),
                    const SizedBox(height: 8),
                    rewardSkeleton,
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Loading tile
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))
              ],
            ),
            child: const SizedBox(height: 16, child: _AnimatedLoadingDots()),
          ),
        ],
      ),
    );
  }

  Widget _previousWinnerCard({
    required int position,
    required String name,
    required String number,
  }) {
    final badge = _posBadge(position);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 6))
        ],
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: badge,
          child: Text(_ordinal(position),
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.black87)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.confirmation_number_outlined,
                      size: 16, color: Colors.black54),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text('Number: $number',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.black54))),
                ]),
              ]),
        ),
      ]),
    );
  }

  String _awardTextFor(int position) {
    final idx = position - 1;
    if (idx < 0 || idx >= _awardValues.length) return '';
    final amt = _awardValues[idx];
    return (amt > 0) ? 'Award: Rs. $amt' : '';
  }

  // Only used in REGULAR mode
  Widget _awardChip(int position) {
    if (_type != DrawType.regular) return const SizedBox.shrink();
    final label = _awardTextFor(position);
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.monetization_on, size: 16, color: Colors.black87),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87)),
        ],
      ),
    );
  }
}

// Simple animated loading dots
class _AnimatedLoadingDots extends StatefulWidget {
  const _AnimatedLoadingDots();
  @override
  State<_AnimatedLoadingDots> createState() => _AnimatedLoadingDotsState();
}

class _AnimatedLoadingDotsState extends State<_AnimatedLoadingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  static const _cycle = Duration(milliseconds: 1000);
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _cycle)
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _dotOpacity(int i, double t) {
    final ph = (t + i * 0.18) % 1.0;
    final v = (ph < 0.5) ? (ph * 2) : (2 - ph * 2);
    return 0.25 + 0.75 * v;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        final t = _controller.value;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (i) {
            final double op = _dotOpacity(i, t).clamp(0.0, 1.0).toDouble();
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Opacity(
                opacity: op,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.black87,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
