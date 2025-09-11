// admin_panel.dart — Regular + Golden Lott (full page)
// - Golden draw uses its own namespace: golden_draws/latest/... (+ counters/golden_participants, winner_payouts_golden, previous_winners_golden)
// - Golden confirm allocates exactly ONE unique number (prefixed "G..."), updates ticket history, entries, and golden lott_packets
// - Golden draw duration: 10 minutes up to 30 days; manual stop button
// - Winners toggle on Dashboard switches Regular/Golden preview
// - New tabs: G-Pending, G-Confirmed, G-Rejected, Golden Lott
// - Regular flow left intact; internal updates so golden flows point to golden_payments + counters/golden_participants

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:animate_do/animate_do.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// ===================== GOLDEN SUPPORT =====================
enum DrawType { regular, golden }

extension _NS on DrawType {
  String get drawsRoot => (this == DrawType.golden) ? 'golden_draws' : 'draws';
  // NOTE: we keep countersRoot for regular only; golden uses counters/golden_participants explicitly below.
  String get winnerPayouts => (this == DrawType.golden) ? 'winner_payouts_golden' : 'winner_payouts';
  String get previousWinners => (this == DrawType.golden) ? 'previous_winners_golden' : 'previous_winners';
}

class AdminPanel extends StatefulWidget {
  const AdminPanel({super.key});
  @override
  State<AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends State<AdminPanel> with TickerProviderStateMixin {
  final _fs = FirebaseFirestore.instance;
  final _rng = Random.secure();

  String _normStatus(Object? v) => (v?.toString() ?? '').trim().toLowerCase();

  // state
  String? _processingPaymentId;
  bool _isSoftDeleting = false;


  // regular draw state
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _drawSub;
  bool _isDrawRunning = false;
  bool? _adminWriteOK;

  // golden draw state
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _goldDrawSub;
  bool _isGoldenRunning = false;

  // dashboard winners toggle
  bool _winnersPreviewGolden = false;

  @override
  void initState() {
    super.initState();
    _ensureAdminClaims();
    _checkAdminWrite();
    _subscribeToDrawStatus();
    _subscribeToGoldenDrawStatus(); // GOLDEN
  }

  @override
  void dispose() {
    _drawSub?.cancel();
    _goldDrawSub?.cancel();
    super.dispose();
  }

  Future<void> _ensureAdminClaims() async {
    try { await FirebaseAuth.instance.currentUser?.getIdToken(true); } catch (_) {}
  }

  Future<void> _checkAdminWrite() async {
    try {
      await _fs.collection('draws').doc('latest')
          .collection('audit').doc('__claim_probe')
          .set({'t': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      if (mounted) setState(() => _adminWriteOK = true);
    } catch (_) {
      if (mounted) setState(() => _adminWriteOK = false);
    }
  }

  // ------------ helpers
  String generateLotteryNumber([int suffixOffset = 0]) {
    final now = DateTime.now().millisecondsSinceEpoch + suffixOffset;
    final s = now.toString();
    return 'L${s.substring(s.length - 6)}';
  }

  // Golden: single, more collision-safe id
  String generateGoldenLotteryNumber() {
    final ms = DateTime.now().millisecondsSinceEpoch;
    final rand = _rng.nextInt(900) + 100; // 100–999
    final s = ms.toString();
    return 'G${s.substring(s.length - 7)}$rand';
  }

  int _calcTicketCountFromPayment(Map<String, dynamic> p) {
    final tc = p['ticketCount'];
    if (tc is int && tc > 0) return tc;
    if (tc is String) { final v = int.tryParse(tc); if (v != null && v > 0) return v; }

    if (p['selectedAmounts'] is List) {
      try {
        int total = 0;
        for (final a in (p['selectedAmounts'] as List)) {
          final v = (a is num) ? a.toInt() : int.tryParse(a.toString()) ?? 0;
          if (v == 100) total += 1;
          else if (v == 200) total += 3;
          else if (v == 300) total += 5;
          else total += 1;
        }
        if (total > 0) return total;
      } catch (_) {}
    }
    return 1;
  }

  String _prettyErr(Object e) {
    final txt = e.toString().toLowerCase();
    if (e is TimeoutException || txt.contains('timeout')) return 'Network timed out. Please try again.';
    if (txt.contains('missing or insufficient permissions') || txt.contains('permission')) return 'Permission denied. Check admin claims / rules.';
    if (txt.contains('aborted') || txt.contains('failed_precondition')) return 'Another admin wrote at the same time.';
    return e.toString();
  }

  // ===================== TYPE-AWARE (REGULAR/GOLDEN) UTILS =====================
  DocumentReference<Map<String, dynamic>> _drawRef(DrawType t) =>
      _fs.collection(t.drawsRoot).doc('latest');

  CollectionReference<Map<String, dynamic>> _entriesColl(DrawType t) =>
      _drawRef(t).collection('entries');

  CollectionReference<Map<String, dynamic>> _packetsColl(DrawType t) =>
      _drawRef(t).collection('lott_packets');

  // PARTICIPANTS counters:
  // - Regular: counters/participants
  // - Golden:  counters/golden_participants   (matches HomePage stream)
  DocumentReference<Map<String, dynamic>> _participantsCounter(DrawType t) {
    if (t == DrawType.golden) {
      return _fs.collection('counters').doc('golden_participants');
    }
    return _fs.collection('counters').doc('participants');
  }

  CollectionReference<Map<String, dynamic>> _winnerPayoutsColl(DrawType t) =>
      _fs.collection(t.winnerPayouts);

  CollectionReference<Map<String, dynamic>> _previousWinnersColl(DrawType t) =>
      _fs.collection(t.previousWinners);

  // ENTRIES
  Future<void> _addEntriesForPaymentIn({
    required DrawType type,
    required DocumentReference<Map<String, dynamic>> paymentRef,
    required Map<String, dynamic> paymentData,
    required List<String> numbers,
  }) async {
    if (numbers.isEmpty) return;
    final entries = _entriesColl(type);
    final batch = _fs.batch();
    final userId = (paymentData['userId'] ?? '').toString();
    final ticketPath = (paymentData['userTicketPath'] ?? '').toString();
    final name = (paymentData['buyerName'] ?? paymentData['name'] ?? '').toString();
    final email = (paymentData['buyerEmail'] ?? '').toString();
    final phone = (paymentData['buyerPhone'] ?? '').toString();

    for (int i = 0; i < numbers.length; i++) {
      final n = numbers[i];
      final docId = '${paymentRef.id}_$i';
      batch.set(entries.doc(docId), {
        'lotteryNumber': n,
        'paymentRef': paymentRef.path,
        'userTicketPath': ticketPath,
        'userId': userId,
        'buyerName': name,
        'buyerEmail': email,
        'buyerPhone': phone,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  Future<void> _deleteEntriesForPaymentIn(DrawType type, DocumentReference<Map<String, dynamic>> paymentRef) async {
    final entries = _entriesColl(type);
    final qs = await entries.where('paymentRef', isEqualTo: paymentRef.path).get();
    if (qs.docs.isEmpty) return;
    const chunk = 400;
    for (int i = 0; i < qs.docs.length; i += chunk) {
      final slice = qs.docs.sublist(i, (i + chunk > qs.docs.length) ? qs.docs.length : i + chunk);
      final b = _fs.batch();
      for (final d in slice) { b.delete(d.reference); }
      await b.commit();
    }
  }

  Future<void> _deleteAllEntriesIn(DrawType type) async {
    final entries = _entriesColl(type);
    while (true) {
      final page = await entries.limit(400).get();
      if (page.docs.isEmpty) break;
      final b = _fs.batch();
      for (final d in page.docs) { b.delete(d.reference); }
      await b.commit();
    }
  }

  // PACKETS
  Future<void> _mergeIntoLottPacketIn({
    required DrawType type,
    required String userId,
    required String buyerName,
    required String accountNumber,
    required List<String> numbers,
    required String paymentRefPath,
  }) async {
    if (numbers.isEmpty) return;
    final ref = _packetsColl(type).doc(userId);
    await _fs.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final existing = (snap.exists ? (snap.data()?['numbers'] as List?)?.map((e)=>e.toString()).toList() : <String>[]) ?? <String>[];
      final merged = {...existing, ...numbers}.toList();
      tx.set(ref, {
        'userId': userId,
        'buyerName': buyerName,
        'accountNumber': accountNumber,
        'numbers': merged,
        'count': merged.length,
        'paymentRefs': FieldValue.arrayUnion([paymentRefPath]),
        'updatedAt': FieldValue.serverTimestamp(),
        if (!snap.exists) 'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<void> _removeFromLottPacketIn({
    required DrawType type,
    required String userId,
    required List<String> numbers,
    required String paymentRefPath,
  }) async {
    if (numbers.isEmpty) return;
    final ref = _packetsColl(type).doc(userId);
    await _fs.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final data = snap.data() ?? {};
      final existing = (data['numbers'] as List?)?.map((e)=>e.toString()).toList() ?? <String>[];
      final toKeep = existing.where((n) => !numbers.contains(n)).toList();
      if (toKeep.isEmpty) {
        tx.delete(ref);
      } else {
        tx.update(ref, {
          'numbers': toKeep,
          'count': toKeep.length,
          'paymentRefs': FieldValue.arrayRemove([paymentRefPath]),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  Future<void> _deleteAllLottPacketsIn(DrawType type) async {
    final packets = _packetsColl(type);
    while (true) {
      final page = await packets.limit(400).get();
      if (page.docs.isEmpty) break;
      final b = _fs.batch();
      for (final d in page.docs) { b.delete(d.reference); }
      await b.commit();
    }
  }

  // CLEANUP / START / STOP
  Future<void> _cleanupBeforeStartNewDrawIn(DrawType type) async {
    await _participantsCounter(type).set({'total': 0}, SetOptions(merge: true));
    await _deleteAllEntriesIn(type);
    await _deleteAllLottPacketsIn(type);
  }

  Future<void> _startDrawIn(DrawType type, Duration duration) async {
    final adminUid = FirebaseAuth.instance.currentUser?.uid;
    final ref = _drawRef(type);
    await _cleanupBeforeStartNewDrawIn(type);
    final end = DateTime.now().add(duration);
    await ref.set({
      'status': 'running',
      'startAt': FieldValue.serverTimestamp(),
      'drawDate': Timestamp.fromDate(end),
      'endAt': Timestamp.fromDate(end),
      'durationSeconds': duration.inSeconds,
      'startedBy': adminUid ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
      'winners': [],
      'winnerCount': 0,
    }, SetOptions(merge: true));
  }

  Future<void> _stopDrawIn(DrawType type) async {
    final ref = _drawRef(type);
    await ref.set({
      'status': 'stopped',
      'endAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ===================== EXISTING (REGULAR) ENTRIES/PACKETS =====================
  Future<void> _addEntriesForPayment({
    required DocumentReference<Map<String, dynamic>> paymentRef,
    required Map<String, dynamic> paymentData,
    required List<String> numbers,
  }) async {
    await _addEntriesForPaymentIn(
      type: DrawType.regular,
      paymentRef: paymentRef,
      paymentData: paymentData,
      numbers: numbers,
    );
  }

  Future<void> _deleteEntriesForPayment(DocumentReference<Map<String, dynamic>> paymentRef) async {
    await _deleteEntriesForPaymentIn(DrawType.regular, paymentRef);
  }


  Future<void> _mergeIntoLottPacket({
    required String userId,
    required String buyerName,
    required String accountNumber,
    required List<String> numbers,
    required String paymentRefPath,
  }) async {
    await _mergeIntoLottPacketIn(
      type: DrawType.regular,
      userId: userId,
      buyerName: buyerName,
      accountNumber: accountNumber,
      numbers: numbers,
      paymentRefPath: paymentRefPath,
    );
  }

  Future<void> _removeFromLottPacket({
    required String userId,
    required List<String> numbers,
    required String paymentRefPath,
  }) async {
    await _removeFromLottPacketIn(
      type: DrawType.regular,
      userId: userId,
      numbers: numbers,
      paymentRefPath: paymentRefPath,
    );
  }


  // ===================== DRAW STATUS LISTENERS =====================
  void _subscribeToDrawStatus() {
    final drawRef = _fs.collection('draws').doc('latest');
    _drawSub = drawRef.snapshots().listen((snap) {
      if (!mounted) return;
      if (!snap.exists) { setState(() => _isDrawRunning = false); return; }
      final data = snap.data() ?? {};
      final status = _normStatus(data['status']);
      setState(() => _isDrawRunning = (status == 'running'));
    }, onError: (e) => debugPrint('Draw status listener error: $e'));
  }

  void _subscribeToGoldenDrawStatus() {
    final ref = _drawRef(DrawType.golden);
    _goldDrawSub = ref.snapshots().listen((snap) {
      if (!mounted) return;
      if (!snap.exists) { setState(() => _isGoldenRunning = false); return; }
      final data = snap.data() ?? {};
      final status = _normStatus(data['status']);
      setState(() => _isGoldenRunning = (status == 'running'));
    }, onError: (e) => debugPrint('Golden draw status listener error: $e'));
  }

  // ===================== REGULAR CONFIRM / UNDO / REJECT =====================
  Future<void> confirmPaymentWithBatch(
    DocumentReference<Map<String, dynamic>> paymentRef,
    Map<String, dynamic> paymentData,
  ) async {
    if (!_isDrawRunning) { throw Exception('Draw is not running.'); }
    if (paymentData['confirmed'] == true) { throw Exception('This payment is already confirmed.'); }

    final adminUid = FirebaseAuth.instance.currentUser?.uid;
    final counterRef = _fs.collection('counters').doc('participants');

    final int ticketCount = _calcTicketCountFromPayment(paymentData);
    final List<String> numbers = List<String>.generate(ticketCount, (i) => generateLotteryNumber(i));

    final batch = _fs.batch();

    batch.update(paymentRef, {
      'confirmed': true,
      'status': 'confirmed',
      'lotteryNumbers': numbers,
      if (numbers.isNotEmpty) 'lotteryNumber': numbers.first,
      'confirmed_at': FieldValue.serverTimestamp(),
      if (adminUid != null) 'confirmed_by': adminUid,
      'archived': false,
      'forNextDraw': false,
      'isGolden': false,
      'drawType': 'regular',
    });

    batch.set(counterRef, {'total': FieldValue.increment(ticketCount)}, SetOptions(merge: true));
    await batch.commit();

    // Update user ticket (best-effort)
    final path = (paymentData['userTicketPath'] as String?)?.trim();
    if (path != null && path.isNotEmpty) {
      try {
        await _fs.doc(path).update({
          'status': 'confirmed',
          'confirmed_at': FieldValue.serverTimestamp(),
          'lotteryNumbers': numbers,
          if (numbers.isNotEmpty) 'lotteryNumber': numbers.first,
          'archived': false,
          'drawType': 'regular',
          'isGolden': false,
        });
      } catch (e) { debugPrint('ticket update (confirm) skipped: $e'); }
    }

    // write entries (one per number)
    await _addEntriesForPayment(paymentRef: paymentRef, paymentData: paymentData, numbers: numbers);

    // merge into lott packet (includes accountNumber for admin use later)
    await _mergeIntoLottPacket(
      userId: (paymentData['userId'] ?? '').toString(),
      buyerName: (paymentData['buyerName'] ?? paymentData['name'] ?? '').toString(),
      accountNumber: (paymentData['accountNumber'] ?? '').toString(),
      numbers: numbers,
      paymentRefPath: paymentRef.path,
    );
  }

  Future<void> undoConfirmationWithBatch(
    DocumentReference<Map<String, dynamic>> paymentRef,
    Map<String, dynamic> paymentData,
  ) async {
    if (paymentData['confirmed'] != true) return;

    final adminUid = FirebaseAuth.instance.currentUser?.uid;
    final counterRef = _fs.collection('counters').doc('participants');
    final int ticketCount = _calcTicketCountFromPayment(paymentData);

    final List<String> numbers = ((paymentData['lotteryNumbers'] as List?)?.map((e)=>e.toString()).toList() ?? <String>[]);

    final batch = _fs.batch();

    batch.update(paymentRef, {
      'confirmed': false,
      'status': 'pending',
      'unconfirmed_at': FieldValue.serverTimestamp(),
      if (adminUid != null) 'unconfirmed_by': adminUid,
      'lotteryNumber': FieldValue.delete(),
      'lotteryNumbers': FieldValue.delete(),
      'confirmed_at': FieldValue.delete(),
      'confirmed_by': FieldValue.delete(),
      'archived': false,
      'isGolden': false,
      'drawType': 'regular',
    });

    batch.set(counterRef, {'total': FieldValue.increment(-ticketCount)}, SetOptions(merge: true));
    await batch.commit();

    final path = (paymentData['userTicketPath'] as String?)?.trim();
    if (path != null && path.isNotEmpty) {
      try {
        await _fs.doc(path).update({
          'status': 'pending',
          'confirmed_at': FieldValue.delete(),
          'lotteryNumbers': FieldValue.delete(),
          'lotteryNumber': FieldValue.delete(),
          'archived': false,
          'drawType': 'regular',
          'isGolden': false,
        });
      } catch (e) { debugPrint('ticket update (undo) skipped: $e'); }
    }

    await _deleteEntriesForPayment(paymentRef);

    await _removeFromLottPacket(
      userId: (paymentData['userId'] ?? '').toString(),
      numbers: numbers,
      paymentRefPath: paymentRef.path,
    );
  }

  Future<void> _rejectPayment(
    DocumentReference<Map<String, dynamic>> paymentRef,
    Map<String, dynamic> paymentData,
  ) async {
    if (_normStatus(paymentData['status']) == 'rejected') return;
    final adminUid = FirebaseAuth.instance.currentUser?.uid;

    await paymentRef.update({
      'status': 'rejected',
      'confirmed': false,
      'rejected_at': FieldValue.serverTimestamp(),
      if (adminUid != null) 'rejected_by': adminUid,
      'archived': false,
    });

    final path = (paymentData['userTicketPath'] as String?)?.trim();
    if (path != null && path.isNotEmpty) {
      try {
        final isGolden = paymentData['isGolden'] == true || path.contains('/goldenTickets/');
        await _fs.doc(path).update({
          'status': 'rejected',
          'archived': false,
          'isGolden': isGolden,
          'drawType': isGolden ? 'golden' : 'regular',
        });
      } catch (e) { debugPrint('ticket update (reject) skipped: $e'); }
    }
  }

  // ===================== GOLDEN CONFIRM / UNDO =====================
  Future<void> confirmGoldenPaymentWithBatch(
    DocumentReference<Map<String, dynamic>> paymentRef,
    Map<String, dynamic> paymentData,
  ) async {
    if (!_isGoldenRunning) { throw Exception('Golden draw is not running.'); }
    if (paymentData['confirmed'] == true) { throw Exception('This payment is already confirmed.'); }

    final adminUid = FirebaseAuth.instance.currentUser?.uid;
    final counterRef = _participantsCounter(DrawType.golden);

    // exactly ONE unique number for Golden
    final String number = generateGoldenLotteryNumber();
    final List<String> numbers = [number];

    final batch = _fs.batch();

    batch.update(paymentRef, {
      'confirmed': true,
      'status': 'confirmed',
      'isGolden': true,
      'drawType': 'golden',
      'lotteryNumbers': numbers,
      'lotteryNumber': number,
      'confirmed_at': FieldValue.serverTimestamp(),
      if (adminUid != null) 'confirmed_by': adminUid,
      'archived': false,
      'forNextDraw': false,
    });

    // increment by 1 per payment
    batch.set(counterRef, {'total': FieldValue.increment(1)}, SetOptions(merge: true));
    await batch.commit();

    // ticket history (best-effort)
    final path = (paymentData['userTicketPath'] as String?)?.trim();
    if (path != null && path.isNotEmpty) {
      try {
        await _fs.doc(path).set({
          'status': 'confirmed',
          'confirmed_at': FieldValue.serverTimestamp(),
          'lotteryNumbers': numbers,
          'lotteryNumber': number,
          'archived': false,
          'drawType': 'golden',
          'isGolden': true,
        }, SetOptions(merge: true));
      } catch (e) { debugPrint('ticket update (golden confirm) skipped: $e'); }
    }

    await _addEntriesForPaymentIn(
      type: DrawType.golden,
      paymentRef: paymentRef,
      paymentData: paymentData,
      numbers: numbers,
    );

    await _mergeIntoLottPacketIn(
      type: DrawType.golden,
      userId: (paymentData['userId'] ?? '').toString(),
      buyerName: (paymentData['buyerName'] ?? paymentData['name'] ?? '').toString(),
      accountNumber: (paymentData['accountNumber'] ?? '').toString(),
      numbers: numbers,
      paymentRefPath: paymentRef.path,
    );
  }

  Future<void> undoGoldenConfirmationWithBatch(
    DocumentReference<Map<String, dynamic>> paymentRef,
    Map<String, dynamic> paymentData,
  ) async {
    if (paymentData['confirmed'] != true) return;

    final adminUid = FirebaseAuth.instance.currentUser?.uid;
    final counterRef = _participantsCounter(DrawType.golden);
    final List<String> numbers = ((paymentData['lotteryNumbers'] as List?)?.map((e)=>e.toString()).toList() ?? <String>[]);

    final batch = _fs.batch();

    batch.update(paymentRef, {
      'confirmed': false,
      'status': 'pending',
      'unconfirmed_at': FieldValue.serverTimestamp(),
      if (adminUid != null) 'unconfirmed_by': adminUid,
      'lotteryNumber': FieldValue.delete(),
      'lotteryNumbers': FieldValue.delete(),
      'confirmed_at': FieldValue.delete(),
      'confirmed_by': FieldValue.delete(),
      'archived': false,
      'isGolden': true,
      'drawType': 'golden',
    });

    batch.set(counterRef, {'total': FieldValue.increment(-1)}, SetOptions(merge: true));
    await batch.commit();

    final path = (paymentData['userTicketPath'] as String?)?.trim();
    if (path != null && path.isNotEmpty) {
      try {
        await _fs.doc(path).set({
          'status': 'pending',
          'confirmed_at': FieldValue.delete(),
          'lotteryNumbers': FieldValue.delete(),
          'lotteryNumber': FieldValue.delete(),
          'archived': false,
          'drawType': 'golden',
          'isGolden': true,
        }, SetOptions(merge: true));
      } catch (e) { debugPrint('ticket update (golden undo) skipped: $e'); }
    }

    await _deleteEntriesForPaymentIn(DrawType.golden, paymentRef);

    await _removeFromLottPacketIn(
      type: DrawType.golden,
      userId: (paymentData['userId'] ?? '').toString(),
      numbers: numbers,
      paymentRefPath: paymentRef.path,
    );
  }

  // ===================== START/STOP DIALOGS (REGULAR & GOLDEN) =====================
  Future<void> _startDrawWithDialog() async {
    Duration selected = const Duration(days: 1);
    int daysSelected = 1;
    bool useHour = false;
    int hoursSelected = 1;

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (context, setStateDialog) {
        return AlertDialog(
          title: const Text('Start Draw - Choose duration'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<bool>(
                value: false, groupValue: useHour, onChanged: (v) => setStateDialog(() => useHour = v ?? false),
                title: const Text('Days (1 - 7)'),
              ),
              if (!useHour)
                Wrap(
                  spacing: 6,
                  children: List.generate(7, (i) {
                    final d = i + 1;
                    return ChoiceChip(
                      label: Text('$d day${d>1?'s':''}'),
                      selected: daysSelected == d,
                      onSelected: (sel) => setStateDialog(() => daysSelected = d),
                    );
                  }),
                ),
              const SizedBox(height: 12),
              RadioListTile<bool>(
                value: true, groupValue: useHour, onChanged: (v) => setStateDialog(() => useHour = v ?? true),
                title: const Text('Hours (10m/30m/1h or 1–6h)'),
              ),
              if (useHour)
                Wrap(
                  spacing: 6,
                  children: [
                    ChoiceChip(label: const Text('10 min'), selected: hoursSelected == -10, onSelected: (s)=>setStateDialog(()=>hoursSelected=-10)),
                    ChoiceChip(label: const Text('30 min'), selected: hoursSelected == -30, onSelected: (s)=>setStateDialog(()=>hoursSelected=-30)),
                    ChoiceChip(label: const Text('1 hr'),   selected: hoursSelected == 1,   onSelected: (s)=>setStateDialog(()=>hoursSelected=1)),
                    ...List.generate(5, (i){
                      final h=i+2;
                      return ChoiceChip(label: Text('$h hr${h>1?'s':''}'), selected: hoursSelected==h, onSelected: (s)=>setStateDialog(()=>hoursSelected=h));
                    }),
                  ],
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: ()=>Navigator.of(c).pop(false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: (){
                if (useHour) {
                  if (hoursSelected == -10) selected = const Duration(minutes: 10);
                  else if (hoursSelected == -30) selected = const Duration(minutes: 30);
                  else selected = Duration(hours: hoursSelected);
                } else {
                  selected = Duration(days: daysSelected);
                }
                Navigator.of(c).pop(true);
              },
              child: const Text('Start Draw'),
            ),
          ],
        );
      }),
    );

    if (ok == true) {
      try {
        await _startDrawIn(DrawType.regular, selected);
        if (mounted) setState(() => _isDrawRunning = true);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Draw started.')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Start draw failed: ${_prettyErr(e)}')));
      }
    }
  }

  Future<void> _startGoldenDrawWithDialog() async {
    // 10 minutes → 30 days
    Duration selected = const Duration(minutes: 10);
    int mode = 0; // 0=minutes/hours, 1=days
    int mSelection = 10; // minutes/hours selector
    int dSelection = 1;

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (context, setStateDialog) {
        return AlertDialog(
          title: const Text('Start Golden Draw — Duration'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<int>(value: 0, groupValue: mode, onChanged: (v)=>setStateDialog(()=>mode=0), title: const Text('Minutes / Hours')),
              if (mode==0)
                Wrap(spacing: 6, children: [
                  ChoiceChip(label: const Text('10 min'), selected: mSelection==10, onSelected: (_)=>setStateDialog(()=>mSelection=10)),
                  ChoiceChip(label: const Text('30 min'), selected: mSelection==30, onSelected: (_)=>setStateDialog(()=>mSelection=30)),
                  ChoiceChip(label: const Text('1 hr'), selected: mSelection==60, onSelected: (_)=>setStateDialog(()=>mSelection=60)),
                  ChoiceChip(label: const Text('6 hr'), selected: mSelection==360, onSelected: (_)=>setStateDialog(()=>mSelection=360)),
                  ChoiceChip(label: const Text('12 hr'), selected: mSelection==720, onSelected: (_)=>setStateDialog(()=>mSelection=720)),
                ]),
              const SizedBox(height: 12),
              RadioListTile<int>(value: 1, groupValue: mode, onChanged: (v)=>setStateDialog(()=>mode=1), title: const Text('Days')),
              if (mode==1)
                Wrap(spacing: 6, children: [
                  ChoiceChip(label: const Text('1 day'), selected: dSelection==1, onSelected: (_)=>setStateDialog(()=>dSelection=1)),
                  ChoiceChip(label: const Text('3 days'), selected: dSelection==3, onSelected: (_)=>setStateDialog(()=>dSelection=3)),
                  ChoiceChip(label: const Text('7 days'), selected: dSelection==7, onSelected: (_)=>setStateDialog(()=>dSelection=7)),
                  ChoiceChip(label: const Text('15 days'), selected: dSelection==15, onSelected: (_)=>setStateDialog(()=>dSelection=15)),
                  ChoiceChip(label: const Text('30 days'), selected: dSelection==30, onSelected: (_)=>setStateDialog(()=>dSelection=30)),
                ]),
            ],
          ),
          actions: [
            TextButton(onPressed: ()=>Navigator.of(c).pop(false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: (){
                selected = (mode==0)
                  ? Duration(minutes: mSelection)
                  : Duration(days: dSelection);
                Navigator.of(c).pop(true);
              },
              child: const Text('Start Golden Draw'),
            ),
          ],
        );
      }),
    );

    if (ok == true) {
      try {
        await _startDrawIn(DrawType.golden, selected);
        if (mounted) setState(() => _isGoldenRunning = true);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Golden draw started.')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Start golden failed: ${_prettyErr(e)}')));
      }
    }
  }

  // ------------ UI helpers
  void _showFullImage(BuildContext context, String imageUrl) {
    if (kIsWeb) { _openUrl(imageUrl); return; }
    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: InteractiveViewer(child: Image.network(imageUrl, fit: BoxFit.contain)),
        ),
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid URL'))); return; }
    try {
      if (kIsWeb) {
        final ok = await launchUrl(uri);
        if (!ok && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open link')));
        return;
      }
      if (!await canLaunchUrl(uri)) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not launch URL'))); return; }
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Error launching url: $e');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error launching URL')));
    }
  }

  Widget _statusChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _dashboardHeader() {
    final drawStream = _fs.collection('draws').doc('latest').snapshots();
    final counterStream = _fs.collection('counters').doc('participants').snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: drawStream,
      builder: (context, drawSnap) {
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: counterStream,
          builder: (context, counterSnap) {
            final drawData = drawSnap.data?.data() ?? <String, dynamic>{};
            final status = _normStatus(drawData['status']);
            final startAt = (drawData['startAt'] is Timestamp) ? (drawData['startAt'] as Timestamp).toDate() : null;
            final winnerCount = (drawData['winnerCount'] ?? 0);

            int participantsTotal = 0;
            if (counterSnap.data?.data() != null) {
              final t = counterSnap.data!.data()!['total'];
              participantsTotal = (t is int) ? t : (t is num ? t.toInt() : 0);
            }

            return Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.75),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('Draw: ${status.toUpperCase()}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      if (_adminWriteOK == null) const Text('• Admin: …', style: TextStyle(color: Colors.white70))
                      else if (_adminWriteOK == true) _statusChip('Admin OK', Colors.green.shade700)
                      else _statusChip('Admin LOCKED', Colors.red.shade700),
                      if (status == 'winners_announced') _statusChip('Winners: $winnerCount', Colors.purple.shade700),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 16, runSpacing: 8,
                    children: [
                      Text('Participants: $participantsTotal', style: TextStyle(color: Colors.white.withOpacity(0.9))),
                      if (startAt != null)
                        Text('Started: ${startAt.toLocal().toString().split('.').first}', style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _startDrawWithDialog,
                        icon: const Icon(Icons.play_arrow, color: Colors.white, size: 18),
                        label: const Text('Start Draw'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700),
                      ),
                      ElevatedButton.icon(
  onPressed: _isDrawRunning ? () async {
    try {
      await _stopDrawIn(DrawType.regular);
      if (mounted) setState(() => _isDrawRunning = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Draw stopped.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Stop draw failed: ${_prettyErr(e)}')),
        );
      }
    }
  } : null,
  icon: const Icon(Icons.stop, color: Colors.white, size: 18),
  label: const Text('Stop Draw'),
  style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
),

                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ---- ONE-CLICK DELETE: delete old confirmed & rejected payments + tickets (and any archived)
  
Future<bool?> _askSoftDeleteRegularDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Soft delete (Regular)'),
      content: const Text(
        'This will:\n'
        '• Mark ALL Regular entries as soft-deleted (kept for audit)\n'
        '• Clear numbers in ALL Regular lott_packets (with a one-time backup)\n'
        '• Reset Regular participants counter to 0\n\n'
        'Run only when the Regular draw is STOPPED.'
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Soft delete')),
      ],
    ),
  );
}

Future<void> _softDeleteOldLuckyNumbersRegular() async {
  if (_isDrawRunning) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Stop the Regular draw first.')),
    );
    return;
  }

  final ok = await _askSoftDeleteRegularDialog(context);
  if (ok != true) return;

  setState(() => _isSoftDeleting = true);
  try {
    final adminUid = FirebaseAuth.instance.currentUser?.uid;

    // 1) Mark ALL Regular entries as soft-deleted (paged)
    final entries = _entriesColl(DrawType.regular);
    while (true) {
      final page = await entries.limit(400).get();
      if (page.docs.isEmpty) break;
      final b = _fs.batch();
      for (final d in page.docs) {
        b.set(d.reference, {
          'softDeleted': true,
          'softDeletedAt': FieldValue.serverTimestamp(),
          if (adminUid != null) 'softDeletedBy': adminUid,
        }, SetOptions(merge: true));
      }
      await b.commit();
    }

    // 2) Clear numbers in ALL Regular lott_packets (keep a one-time backup)
    final packets = _packetsColl(DrawType.regular);
    while (true) {
      final page = await packets.limit(200).get();
      if (page.docs.isEmpty) break;

      final b = _fs.batch();
      for (final doc in page.docs) {
        final data = doc.data();
        final existing = (data['numbers'] as List?)?.map((e) => e.toString()).toList() ?? <String>[];
        final hasBackup = data.containsKey('numbersBackup');

        b.set(doc.reference, {
          'numbers': <String>[],
          'count': 0,
          'softCleared': true,
          'softClearedAt': FieldValue.serverTimestamp(),
          if (adminUid != null) 'softClearedBy': adminUid,
          if (!hasBackup && existing.isNotEmpty) 'numbersBackup': existing,
        }, SetOptions(merge: true));
      }
      await b.commit();
    }

    // 3) Reset Regular participants counter
    await _participantsCounter(DrawType.regular).set({'total': 0}, SetOptions(merge: true));

    // 4) Breadcrumb on the draw doc
    await _drawRef(DrawType.regular).set({
      'softClearedAt': FieldValue.serverTimestamp(),
      if (adminUid != null) 'softClearedBy': adminUid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Soft delete complete (Regular).')),
      );
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Soft delete failed: ${_prettyErr(e)}')),
      );
    }
  } finally {
    if (mounted) setState(() => _isSoftDeleting = false);
  }
}
Future<bool?> _askSoftDeleteGoldenDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Soft delete (Golden)'),
      content: const Text(
        'This will:\n'
        '• Mark ALL Golden entries as soft-deleted (kept for audit)\n'
        '• Clear numbers in ALL Golden lott_packets (with a one-time backup)\n'
        '• Reset Golden participants counter to 0\n\n'
        'Run only when the GOLDEN draw is STOPPED.'
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Soft delete')),
      ],
    ),
  );
}

Future<void> _softDeleteOldLuckyNumbersGolden() async {
  if (_isGoldenRunning) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Stop the Golden draw first.')),
    );
    return;
  }

  final ok = await _askSoftDeleteGoldenDialog(context);
  if (ok != true) return;

  setState(() => _isSoftDeleting = true);
  try {
    final adminUid = FirebaseAuth.instance.currentUser?.uid;

    // 1) Mark ALL Golden entries as soft-deleted (paged)
    final entries = _entriesColl(DrawType.golden);
    while (true) {
      final page = await entries.limit(400).get();
      if (page.docs.isEmpty) break;
      final b = _fs.batch();
      for (final d in page.docs) {
        b.set(d.reference, {
          'softDeleted': true,
          'softDeletedAt': FieldValue.serverTimestamp(),
          if (adminUid != null) 'softDeletedBy': adminUid,
        }, SetOptions(merge: true));
      }
      await b.commit();
    }

    // 2) Clear numbers in ALL Golden lott_packets (keep a one-time backup)
    final packets = _packetsColl(DrawType.golden);
    while (true) {
      final page = await packets.limit(200).get();
      if (page.docs.isEmpty) break;

      final b = _fs.batch();
      for (final doc in page.docs) {
        final data = doc.data();
        final existing = (data['numbers'] as List?)?.map((e) => e.toString()).toList() ?? <String>[];
        final hasBackup = data.containsKey('numbersBackup');

        b.set(doc.reference, {
          'numbers': <String>[],
          'count': 0,
          'softCleared': true,
          'softClearedAt': FieldValue.serverTimestamp(),
          if (adminUid != null) 'softClearedBy': adminUid,
          if (!hasBackup && existing.isNotEmpty) 'numbersBackup': existing,
        }, SetOptions(merge: true));
      }
      await b.commit();
    }

    // 3) Reset Golden participants counter
    await _participantsCounter(DrawType.golden).set({'total': 0}, SetOptions(merge: true));

    // 4) Breadcrumb on the GOLDEN draw doc
    await _drawRef(DrawType.golden).set({
      'softClearedAt': FieldValue.serverTimestamp(),
      if (adminUid != null) 'softClearedBy': adminUid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Soft delete complete (Golden).')),
      );
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Soft delete failed: ${_prettyErr(e)}')),
      );
    }
  } finally {
    if (mounted) setState(() => _isSoftDeleting = false);
  }
}


  

  // ---- Winners preview (Regular ⟷ Golden)
  Widget _winnersPreviewCard() {
    final type = _winnersPreviewGolden ? DrawType.golden : DrawType.regular;
    final drawRef = _drawRef(type);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 14, offset: Offset(0, 8))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          children: [
            Expanded(child: Text('${_winnersPreviewGolden ? 'Golden' : 'Regular'} Winners (Admin view)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
            Switch.adaptive(
              value: _winnersPreviewGolden,
              onChanged: (v)=>setState(()=>_winnersPreviewGolden=v),
              activeColor: Colors.amber.shade700,
            ),
            Text(_winnersPreviewGolden ? 'Golden' : 'Regular'),
          ],
        ),
        const SizedBox(height: 12),
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: drawRef.snapshots(),
          builder: (context, snap) {
            final data = snap.data?.data() ?? {};
            final winners = (data['winners'] is List)
                ? List<Map<String, dynamic>>.from((data['winners'] as List).map((e) => Map<String, dynamic>.from(e)))
                : <Map<String, dynamic>>[];

            Map<String, dynamic>? getWinner(int position) {
              try { return winners.firstWhere((w) => (w['position'] ?? 0) == position); } catch (_) { return null; }
            }

            Widget slot(int pos, Map<String, dynamic>? w) {
              final c = [Colors.amber.shade400, Colors.grey.shade400, const Color(0xFFCD7F32)][pos-1];
              final number = w?['lotteryNumber']?.toString() ?? '—';
              final name = (w?['buyerName']?.toString() ?? '').isEmpty ? 'Anonymous' : w!['buyerName'].toString();
              final userId = (w?['userId'] ?? '').toString();

              Widget accountRow(Widget child) => Padding(
                padding: const EdgeInsets.only(top: 6.0),
                child: Row(children: [
                  const Icon(Icons.account_balance, size: 16, color: Colors.black54),
                  const SizedBox(width: 6),
                  Expanded(child: child),
                ]),
              );

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [c.withOpacity(0.95), c.withOpacity(0.75)]),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 6))],
                ),
                child: Row(
                  children: [
                    CircleAvatar(radius: 24, backgroundColor: c, child: Text('#$pos', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87))),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('Ticket: $number', style: const TextStyle(color: Colors.black87)),
                        if (userId.isNotEmpty)
                          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                            stream: _packetsColl(type).doc(userId).snapshots(),
                            builder: (context, pktSnap) {
                              final acc = pktSnap.data?.data()?['accountNumber']?.toString() ?? '';
                              return accountRow(Text(
                                'Account: ${acc.isEmpty ? '—' : acc}',
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black87),
                              ));
                            },
                          )
                        else
                          accountRow(const Text('Account: —', style: TextStyle(color: Colors.black87))),
                      ]),
                    ),
                  ],
                ),
              );
            }

            return Column(children: [
              slot(1, getWinner(1)),
              const SizedBox(height: 10),
              slot(2, getWinner(2)),
              const SizedBox(height: 10),
              slot(3, getWinner(3)),
            ]);
          },
        ),
      ]),
    );
  }

  // ---- Payment card (now accepts injected actions)
  Widget _paymentCard({
    required String docId,
    required Map<String, dynamic> data,
    required bool isConfirmed,
    Future<void> Function()? onConfirm, // if null => regular
    Future<void> Function()? onUndo,    // if null => regular
    Future<void> Function()? onReject,  // if null => regular
    bool? confirmEnabledOverride,       // if null => uses _isDrawRunning (regular)
  }) {
    final name = data['name'] ?? data['buyerName'] ?? '-';
    final buyerEmail = (data['buyerEmail'] ?? data['email'] ?? '').toString();
    final buyerPhone = (data['buyerPhone'] ?? data['phone'] ?? '').toString();
    final account = data['accountNumber'] ?? data['account'] ?? '-';
    final method = data['method'] ?? data['paymentMethod'] ?? '-';

    String selectedAmountsText = '-';
    try {
      final sel = data['selectedAmounts'];
      if (sel is List) { selectedAmountsText = sel.map((e) => 'Rs. ${e.toString()}').join(', '); }
    } catch (_) { selectedAmountsText = '-'; }

    String amountString = '-';
    if (data['totalAmount'] != null)      amountString = data['totalAmount'].toString();
    else if (data['amount'] != null)      amountString = data['amount'].toString();

    final ticketCount = (data['ticketCount'] != null) ? data['ticketCount'].toString() : '-';
    final receiptUrl = (data['receiptUrl'] ?? '').toString();
    final userTicketPath = (data['userTicketPath'] ?? '').toString();

    final bool confirmEnabled = confirmEnabledOverride ?? _isDrawRunning;

    return FadeInUp(
      duration: const Duration(milliseconds: 350),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.96),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.14), blurRadius: 26, offset: const Offset(0, 12))],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(
              children: [
                Icon(Icons.person_outline, color: Colors.green.shade700),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name.toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade900, fontSize: 16)),
                    if (buyerEmail.isNotEmpty) Text(buyerEmail, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                  ]),
                ),
                if (isConfirmed)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      Icon(Icons.check_circle, size: 16, color: Colors.green.shade700),
                      const SizedBox(width: 6),
                      Text('Confirmed', style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.w700)),
                    ]),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Account: $account', style: TextStyle(color: Colors.grey.shade800)),
            const SizedBox(height: 4),
            Text('Method: $method', style: TextStyle(color: Colors.grey.shade800)),
            const SizedBox(height: 4),
            Text('Selected: $selectedAmountsText', style: TextStyle(color: Colors.grey.shade800)),
            const SizedBox(height: 4),
            Text('Total: Rs. $amountString', style: TextStyle(color: Colors.grey.shade800)),
            const SizedBox(height: 4),
            Text('Tickets: $ticketCount', style: TextStyle(color: Colors.grey.shade800)),
            const SizedBox(height: 8),
            if (buyerPhone.isNotEmpty) Text('Phone: $buyerPhone', style: TextStyle(color: Colors.grey.shade800)),
            if (userTicketPath.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Row(children: [
                  Expanded(child: Text('Ticket path: $userTicketPath', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade700, fontSize: 12))),
                  IconButton(
                    tooltip: 'Copy ticket path',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: userTicketPath));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ticket path copied')));
                    },
                    icon: const Icon(Icons.copy, size: 18),
                  ),
                ]),
              ),
            const SizedBox(height: 10),
            if (receiptUrl.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GestureDetector(
                    onTap: () => _showFullImage(context, receiptUrl),
                    onLongPress: () => _openUrl(receiptUrl),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        receiptUrl,
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(height: 160, color: Colors.grey.shade200, child: const Center(child: Text('Could not load image'))),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton.icon(onPressed: () => _openUrl(receiptUrl), icon: const Icon(Icons.open_in_new, size: 18), label: const Text('Open receipt')),
                  ]),
                ],
              )
            else
              Container(height: 140, decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)), child: const Center(child: Text('No receipt image'))),
            const SizedBox(height: 12),

            // Actions
            if (isConfirmed)
              (_processingPaymentId == docId)
                  ? _busyBar('Processing undo...', Colors.red.shade700)
                  : SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          final ok = await _askAdminUndo(context, name.toString(), amountString, ticketCount.toString());
                          if (ok != true) return;
                          setState(() => _processingPaymentId = docId);
                          try {
                            if (onUndo != null) {
                              await onUndo();
                            } else {
                              await undoConfirmationWithBatch(_fs.collection('payments').doc(docId), data);
                            }
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Confirmation undone (entries & packet updated)')));
                            }
                          } catch (e) {
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${_prettyErr(e)}')));
                          } finally { if (mounted) setState(() => _processingPaymentId = null); }
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        child: const Text('Undo Confirmation', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    )
            else
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: (_processingPaymentId == docId)
                        ? _busyBar('Processing...', Colors.green.shade700)
                        : ElevatedButton(
                            onPressed: (!confirmEnabled) ? null : () async {
                              final ok = await _askAdminConfirm(context, name.toString(), amountString, ticketCount.toString());
                              if (ok != true) return;
                              setState(() => _processingPaymentId = docId);
                              try {
                                if (onConfirm != null) {
                                  await onConfirm();
                                } else {
                                  await confirmPaymentWithBatch(_fs.collection('payments').doc(docId), data);
                                }
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment confirmed (numbers + entries + packet)')));
                                }
                              } catch (e) {
                                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${_prettyErr(e)}')));
                              } finally { if (mounted) setState(() => _processingPaymentId = null); }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: (!confirmEnabled) ? Colors.grey : Colors.green.shade700,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text((!confirmEnabled) ? 'Confirm (only when RUNNING)' : 'Confirm & Generate Lucky Numbers',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final ok = await _askAdminReject(context, name.toString(), amountString, ticketCount.toString());
                        if (ok != true) return;
                        setState(() => _processingPaymentId = docId);
                        try {
                          if (onReject != null) {
                            await onReject();
                          } else {
                            await _rejectPayment(_fs.collection('payments').doc(docId), data);
                          }
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment rejected')));
                          }
                        } catch (e) {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${_prettyErr(e)}')));
                        } finally { if (mounted) setState(() => _processingPaymentId = null); }
                      },
                      icon: const Icon(Icons.block),
                      label: const Text('Reject'),
                    ),
                  ),
                ],
              ),
          ]),
        ),
      ),
    );
  }

  Widget _busyBar(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
          SizedBox(width: 12),
          Text('Please wait...', style: TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  Future<bool?> _askAdminConfirm(BuildContext context, String name, String amount, String tickets) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm payment'),
        content: Text('Confirm payment for\n$name\nAmount: $amount\nTickets: $tickets'),
        actions: [
          TextButton(onPressed: ()=>Navigator.of(context).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: ()=>Navigator.of(context).pop(true), style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700), child: const Text('Confirm')),
        ],
      ),
    );
  }

  Future<bool?> _askAdminUndo(BuildContext context, String name, String amount, String tickets) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Undo confirmation'),
        content: Text('Undo confirmation for\n$name\nAmount: $amount\nTickets: $tickets\n\nThis will update the participants counter. Continue?'),
        actions: [
          TextButton(onPressed: ()=>Navigator.of(context).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: ()=>Navigator.of(context).pop(true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700), child: const Text('Undo')),
        ],
      ),
    );
  }

  Future<bool?> _askAdminReject(BuildContext context, String name, String amount, String tickets) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject payment'),
        content: Text('Reject payment for\n$name\nAmount: $amount\nTickets: $tickets'),
        actions: [
          TextButton(onPressed: ()=>Navigator.of(context).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: ()=>Navigator.of(context).pop(true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700), child: const Text('Reject')),
        ],
      ),
    );
  }

  // ---- Lott Tab (regular)
  Future<void> _pickWinner(int position) async {
    if (_isDrawRunning) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Wait until draw ends to pick winners.')));
      return;
    }
    final drawRef = _fs.collection('draws').doc('latest');

    try {
      final drawSnap = await drawRef.get();
      final draw = drawSnap.data() ?? {};
      final winners = (draw['winners'] is List)
          ? List<Map<String, dynamic>>.from((draw['winners'] as List).map((e)=>Map<String,dynamic>.from(e)))
          : <Map<String, dynamic>>[];

      if (winners.any((w) => (w['position'] ?? 0) == position)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Winner #$position already set.')));
        return;
      }

      final alreadyUserIds = winners.map((w) => (w['userId'] ?? '').toString()).where((s)=>s.isNotEmpty).toSet();

      final packetsSnap = await drawRef.collection('lott_packets').get();
      final packets = packetsSnap.docs
          .where((d) => (d.data()['count'] ?? 0) > 0)
          .where((d) => !alreadyUserIds.contains((d.data()['userId'] ?? '').toString()))
          .toList();

      if (packets.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No eligible packets to pick from.')));
        return;
      }

      final idx = _rng.nextInt(packets.length);
      final pkt = packets[idx].data();
      final userId = (pkt['userId'] ?? '').toString();
      final buyerName = (pkt['buyerName'] ?? '').toString();
      final accountNumber = (pkt['accountNumber'] ?? '').toString();
      final numbers = (pkt['numbers'] as List?)?.map((e)=>e.toString()).toList() ?? <String>[];
      if (numbers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Picked packet had no numbers. Try again.')));
        return;
      }

      final chosenNumber = numbers[_rng.nextInt(numbers.length)];

      final nextWinners = List<Map<String, dynamic>>.from(winners);
      nextWinners.removeWhere((w) => (w['position'] ?? 0) == position);
      nextWinners.add({
        'position': position,
        'buyerName': buyerName,
        'lotteryNumber': chosenNumber,
        'userId': userId,
      });

      await drawRef.set({
        'winners': nextWinners,
        'winnerCount': nextWinners.length,
        'status': 'winners_announced',
        'winnersPhaseStart': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _fs.collection('winner_payouts').add({
        'drawRef': drawRef.path,
        'position': position,
        'buyerName': buyerName,
        'userId': userId,
        'accountNumber': accountNumber,
        'lotteryNumber': chosenNumber,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _fs.collection('previous_winners').add({
        'position': position,
        'name': buyerName,
        'userName': buyerName,
        'lotteryNumber': chosenNumber,
        'userId': userId,
        'createdAt': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Winner #$position selected: $buyerName')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Pick failed: ${_prettyErr(e)}')));
    }
  }

  Widget _lottTab() {
    final packetsQuery = _fs.collection('draws').doc('latest').collection('lott_packets').orderBy('createdAt', descending: false);

    return Column(
      children: [
        // Toolbar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.96),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.10), blurRadius: 12, offset: const Offset(0, 6))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Lott — Random Winner Picker', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  _isDrawRunning
                      ? 'Draw is RUNNING. Picking is disabled until the timer ends.'
                      : 'Select winners below. First press = 1st, second = 2nd, third = 3rd.',
                  style: TextStyle(color: _isDrawRunning ? Colors.red.shade700 : Colors.black54),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _isDrawRunning ? null : () => _pickWinner(1),
                      icon: const Icon(Icons.emoji_events),
                      label: const Text('Pick Winner #1'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700),
                    ),
                    ElevatedButton.icon(
                      onPressed: _isDrawRunning ? null : () => _pickWinner(2),
                      icon: const Icon(Icons.emoji_events_outlined),
                      label: const Text('Pick Winner #2'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700),
                    ),
                    ElevatedButton.icon(
                      onPressed: _isDrawRunning ? null : () => _pickWinner(3),
                      icon: const Icon(Icons.military_tech),
                      label: const Text('Pick Winner #3'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
const Divider(height: 1),
const SizedBox(height: 8),

// Soft delete (Regular) button in Lott toolbar
ElevatedButton.icon(
  onPressed: (_isSoftDeleting || _isDrawRunning)
      ? null
      : _softDeleteOldLuckyNumbersRegular,
  icon: _isSoftDeleting
      ? const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        )
      : const Icon(Icons.cleaning_services, color: Colors.white),
  label: Text(_isSoftDeleting
      ? 'Working…'
      : 'Soft delete old lucky numbers (Regular)'),
  style: ElevatedButton.styleFrom(
    backgroundColor: Colors.indigo.shade700,
    padding: const EdgeInsets.symmetric(vertical: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ),
),

              ],
            ),
          ),
        ),

        // Packets list
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: packetsQuery.snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: Colors.white));
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Center(child: Text('No packets yet — confirm some payments.', style: TextStyle(color: Colors.white)));
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final d = docs[i].data();
                  final name = (d['buyerName'] ?? '').toString();
                  final count = (d['count'] ?? 0) as int;
                  return _packetRow(name: name, count: count);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ---- GOLDEN Lott Tab
  Future<void> _pickGoldenWinner(int position) async {
    if (_isGoldenRunning) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stop Golden draw first to pick winners.')));
      return;
    }
    final drawRef = _drawRef(DrawType.golden);

    try {
      final drawSnap = await drawRef.get();
      final draw = drawSnap.data() ?? {};
      final winners = (draw['winners'] is List)
          ? List<Map<String, dynamic>>.from((draw['winners'] as List).map((e)=>Map<String,dynamic>.from(e)))
          : <Map<String, dynamic>>[];

      if (winners.any((w) => (w['position'] ?? 0) == position)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Golden winner #$position already set.')));
        return;
      }

      final alreadyUserIds = winners.map((w) => (w['userId'] ?? '').toString()).where((s)=>s.isNotEmpty).toSet();

      final packetsSnap = await _packetsColl(DrawType.golden).get();
      final packets = packetsSnap.docs
          .where((d) => (d.data()['count'] ?? 0) > 0)
          .where((d) => !alreadyUserIds.contains((d.data()['userId'] ?? '').toString()))
          .toList();

      if (packets.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No eligible Golden packets to pick from.')));
        return;
      }

      final idx = _rng.nextInt(packets.length);
      final pkt = packets[idx].data();
      final userId = (pkt['userId'] ?? '').toString();
      final buyerName = (pkt['buyerName'] ?? '').toString();
      final accountNumber = (pkt['accountNumber'] ?? '').toString();
      final numbers = (pkt['numbers'] as List?)?.map((e)=>e.toString()).toList() ?? <String>[];
      if (numbers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Picked Golden packet had no numbers. Try again.')));
        return;
      }

      final chosenNumber = numbers[_rng.nextInt(numbers.length)];

      final nextWinners = List<Map<String, dynamic>>.from(winners)
        ..removeWhere((w) => (w['position'] ?? 0) == position)
        ..add({
          'position': position,
          'buyerName': buyerName,
          'lotteryNumber': chosenNumber,
          'userId': userId,
        });

      await drawRef.set({
        'winners': nextWinners,
        'winnerCount': nextWinners.length,
        'status': 'winners_announced',
        'winnersPhaseStart': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _winnerPayoutsColl(DrawType.golden).add({
        'drawRef': drawRef.path,
        'position': position,
        'buyerName': buyerName,
        'userId': userId,
        'accountNumber': accountNumber,
        'lotteryNumber': chosenNumber,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _previousWinnersColl(DrawType.golden).add({
        'position': position,
        'name': buyerName,
        'userName': buyerName,
        'lotteryNumber': chosenNumber,
        'userId': userId,
        'createdAt': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Golden winner #$position: $buyerName')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Golden pick failed: ${_prettyErr(e)}')));
    }
  }

  Widget _goldenLottTab() {
    final packetsQuery = _packetsColl(DrawType.golden).orderBy('createdAt', descending: false);

    return Column(
      children: [
        // Toolbar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.96),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.10), blurRadius: 12, offset: const Offset(0,6))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Golden Lott — Random Winner Picker', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                ElevatedButton.icon(
                  onPressed: _startGoldenDrawWithDialog,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start Golden Draw'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade700),
                ),
                ElevatedButton.icon(
                  onPressed: _isGoldenRunning ? () async {
                    await _stopDrawIn(DrawType.golden);
                    if (mounted) setState(()=>_isGoldenRunning=false);
                  } : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop Golden Draw'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
                ),
              ]),
              const SizedBox(height: 8),
              Text(
                _isGoldenRunning
                  ? 'Golden draw is RUNNING. Picking is disabled until you press Stop.'
                  : 'Select winners below (1st, 2nd, 3rd).',
                style: TextStyle(color: _isGoldenRunning ? Colors.red.shade700 : Colors.black54),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                ElevatedButton.icon(
                  onPressed: _isGoldenRunning ? null : () => _pickGoldenWinner(1),
                  icon: const Icon(Icons.emoji_events),
                  label: const Text('Pick Golden #1'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700),
                ),
                ElevatedButton.icon(
                  onPressed: _isGoldenRunning ? null : () => _pickGoldenWinner(2),
                  icon: const Icon(Icons.emoji_events_outlined),
                  label: const Text('Pick Golden #2'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700),
                ),
                ElevatedButton.icon(
                  onPressed: _isGoldenRunning ? null : () => _pickGoldenWinner(3),
                  icon: const Icon(Icons.military_tech),
                  label: const Text('Pick Golden #3'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700),
                ),
              ]),
              const SizedBox(height: 12),
const Divider(height: 1),
const SizedBox(height: 8),

// Soft delete (Golden) button in Golden Lott toolbar
ElevatedButton.icon(
  onPressed: (_isSoftDeleting || _isGoldenRunning)
      ? null
      : _softDeleteOldLuckyNumbersGolden,
  icon: _isSoftDeleting
      ? const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        )
      : const Icon(Icons.star, color: Colors.white),
  label: Text(_isSoftDeleting
      ? 'Working…'
      : 'Soft delete old lucky numbers (Golden)'),
  style: ElevatedButton.styleFrom(
    backgroundColor: Colors.amber.shade700,
    padding: const EdgeInsets.symmetric(vertical: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ),
),

            ]),
          ),
        ),

        // Packets list
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: packetsQuery.snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: Colors.white));
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Center(child: Text('No Golden packets yet — confirm some Golden payments.', style: TextStyle(color: Colors.white)));
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final d = docs[i].data();
                  final name = (d['buyerName'] ?? '').toString();
                  final count = (d['count'] ?? 0) as int;
                  return _packetRow(name: name, count: count);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _packetRow({required String name, required int count}) {
    List<Widget> boxes = List.generate(5, (i) {
      return Container(
        width: 26, height: 26,
        alignment: Alignment.center,
        margin: const EdgeInsets.only(right: 6),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.grey.shade400),
        ),
        child: Text('${i+1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      );
    });

    return FadeInUp(
      duration: const Duration(milliseconds: 250),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.96),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.10), blurRadius: 12, offset: const Offset(0, 6))],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name.isEmpty ? 'Anonymous' : name, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Row(children: boxes),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(12)),
              child: Text('Count: $count', style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.w700, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Maintenance card (ONE delete button)
// ---- Maintenance card (Regular + Golden)
Widget _maintenanceCardSoftDelete() {
  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.96),
      borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 14, offset: const Offset(0, 8))],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Maintenance', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        Text(
          'Soft delete lucky numbers for Regular or Golden (keeps audit trail, clears lott_packets numbers with one-time backup, resets participants).',
          style: TextStyle(color: Colors.black.withOpacity(0.75)),
        ),
        const SizedBox(height: 12),

        // Regular button
        ElevatedButton.icon(
          onPressed: _isSoftDeleting ? null : _softDeleteOldLuckyNumbersRegular,
          icon: _isSoftDeleting
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.cleaning_services, color: Colors.white),
          label: Text(_isSoftDeleting ? 'Working…' : 'Soft delete old lucky numbers (Regular)'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.indigo.shade700,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),

        const SizedBox(height: 8),

        // Golden button
        ElevatedButton.icon(
          onPressed: _isSoftDeleting ? null : _softDeleteOldLuckyNumbersGolden,
          icon: _isSoftDeleting
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.star, color: Colors.white),
          label: Text(_isSoftDeleting ? 'Working…' : 'Soft delete old lucky numbers (Golden)'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.amber.shade700,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    ),
  );
}



  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 10, // +4 golden tabs
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.black,
          elevation: 0,
          title: const Text('Admin Panel', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
          bottom: const TabBar(
            indicatorColor: Colors.white,
            isScrollable: true,
            tabs: [
              Tab(icon: Icon(Icons.dashboard), text: 'Dashboard'),
              Tab(icon: Icon(Icons.hourglass_top), text: 'Pending'),
              Tab(icon: Icon(Icons.verified), text: 'Confirmed'),
              Tab(icon: Icon(Icons.block), text: 'Rejected'),
              Tab(icon: Icon(Icons.inventory_2), text: 'Lott'),
              Tab(icon: Icon(Icons.list_alt), text: 'All'),
              // GOLDEN
              Tab(icon: Icon(Icons.hourglass_top_outlined), text: 'G-Pending'),
              Tab(icon: Icon(Icons.verified_outlined), text: 'G-Confirmed'),
              Tab(icon: Icon(Icons.block_outlined), text: 'G-Rejected'),
              Tab(icon: Icon(Icons.star_rate), text: 'Golden Lott'),
            ],
          ),
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: Image.asset('assets/background.png', fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: Colors.white)),
            ),
            TabBarView(
              children: [
                // Dashboard
                SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                     _dashboardHeader(),
_winnersPreviewCard(), // regular ⟷ golden switch
const SizedBox(height: 16),
_maintenanceCardSoftDelete(),
const SizedBox(height: 16),
Container(

                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.96),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 14, offset: Offset(0, 8))],
                        ),
                        child: const Text(
                          'Tip: Regular confirms are enabled only while REGULAR draw is RUNNING.\nGolden confirms are enabled only while GOLDEN draw is RUNNING.',
                          style: TextStyle(color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),
                // Pending (regular)
                _paymentsTabList(statusFilter: 'pending'),
                // Confirmed (regular)
                _paymentsTabList(statusFilter: 'confirmed'),
                // Rejected (regular)
                _paymentsTabList(statusFilter: 'rejected'),
                // Lott (regular)
                _lottTab(),
                // All (regular list)
                _paymentsTabList(statusFilter: null),

                // GOLDEN tabs
                _paymentsTabListGolden(statusFilter: 'pending'),
                _paymentsTabListGolden(statusFilter: 'confirmed'),
                _paymentsTabListGolden(statusFilter: 'rejected'),
                _goldenLottTab(),
              ],
            ),

            
          ],
        ),
      ),
    );
  }

  // ---- Payments list (REGULAR) — client-side hide golden to keep lists clean
  Widget _paymentsTabList({String? statusFilter}) {
    Query<Map<String, dynamic>> q;
    if (statusFilter == null) {
      q = _fs.collection('payments').orderBy('date', descending: true);
    } else {
      q = _fs.collection('payments').where('status', isEqualTo: statusFilter);
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.white));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No payments found.', style: TextStyle(color: Colors.white)));
        }
 
        var docs = snapshot.data!.docs;

        // hide golden payments from regular lists (non-destructive; client-side)
        docs = docs.where((d) => d.data()['isGolden'] != true).toList();

        if (statusFilter != null) {
          docs = docs.toList()
            ..sort((a,b){
              final da = a.data()['date'];
              final db = b.data()['date'];
              Timestamp? ta = da is Timestamp ? da : null;
              Timestamp? tb = db is Timestamp ? db : null;
              final aa = ta?.toDate().millisecondsSinceEpoch ?? 0;
              final bb = tb?.toDate().millisecondsSinceEpoch ?? 0;
              return bb.compareTo(aa);
            });
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final doc = docs[i];
            final data = doc.data();
            final confirmed = data['confirmed'] == true || _normStatus(data['status']) == 'confirmed';
            return _paymentCard(docId: doc.id, data: data, isConfirmed: confirmed);
          },
        );
      },
    );
  }

  // ---- Payments list (GOLDEN) — reads from golden_payments
  Widget _paymentsTabListGolden({required String statusFilter}) {
    Query<Map<String, dynamic>> q = _fs.collection('golden_payments')
      .where('status', isEqualTo: statusFilter);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.white));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No Golden payments found.', style: TextStyle(color: Colors.white)));
        }
        final docs = snapshot.data!.docs.toList()
          ..sort((a,b){
            final da = a.data()['date']; final db = b.data()['date'];
            Timestamp? ta = da is Timestamp ? da : null;
            Timestamp? tb = db is Timestamp ? db : null;
            final aa = ta?.toDate().millisecondsSinceEpoch ?? 0;
            final bb = tb?.toDate().millisecondsSinceEpoch ?? 0;
            return bb.compareTo(aa);
          });

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final doc = docs[i];
            final data = doc.data();
            final confirmed = data['confirmed'] == true || _normStatus(data['status']) == 'confirmed';
            return _paymentCard(
              docId: doc.id,
              data: data,
              isConfirmed: confirmed,
              confirmEnabledOverride: _isGoldenRunning,
              onConfirm: () async {
                await confirmGoldenPaymentWithBatch(_fs.collection('golden_payments').doc(doc.id), data);
              },
              onUndo: () async {
                await undoGoldenConfirmationWithBatch(_fs.collection('golden_payments').doc(doc.id), data);
              },
              onReject: () async {
                await _rejectPayment(_fs.collection('golden_payments').doc(doc.id), data);
              },
            );
          },
        );
      },
    );
  }
}
