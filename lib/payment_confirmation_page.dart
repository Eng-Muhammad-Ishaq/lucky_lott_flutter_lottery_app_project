// payment_confirmation_page.dart
// Scenario-aligned: Spark-safe; pending-only writes; draw-aware flags; cryptographic salts.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:animate_do/animate_do.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // clipboard
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

class PaymentConfirmationPage extends StatefulWidget {
  const PaymentConfirmationPage({super.key});
  @override
  State<PaymentConfirmationPage> createState() => _PaymentConfirmationPageState();
}

class _PaymentConfirmationPageState extends State<PaymentConfirmationPage> {
  bool _isLoading = false;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _accountController = TextEditingController();
  final TextEditingController _otherMethodController = TextEditingController();

  String? _selectedMethod;
  File? _receiptImage;
  int? _selectedAmount; // 100 / 200 / 300

  // Cloudinary
  final String cloudName = "dyanef8fu";
  final String uploadPreset = "lucky_preset";

  final List<String> _paymentMethods = [
    'Easypaisa','JazzCash','Sadapay','Nayapay','Upaisa','Other',
  ];

  bool _argsApplied = false;

  // Draw status banner
  String _drawStatus = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsApplied) return;
    _argsApplied = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && args['amount'] != null) {
      final a = args['amount'];
      final int? amount = (a is int) ? a : int.tryParse(a.toString());
      if (amount != null && (amount == 100 || amount == 200 || amount == 300)) {
        _selectedAmount = amount;
      }
    }
  }

  // ---- helpers
  int _amountToTicketCount(int amount) {
    if (amount == 100) return 1;
    if (amount == 200) return 3;
    if (amount == 300) return 5;
    return 1;
  }

  // --- cryptographic salts
  static final Random _rng = _secureRng();
  static Random _secureRng() {
    try { return Random.secure(); } catch (_) { return Random(); }
  }
  String _randomSaltHex([int bytesLen = 16]) {
    final bytes = List<int>.generate(bytesLen, (_) => _rng.nextInt(256));
    final sb = StringBuffer();
    for (final b in bytes) { sb.write(b.toRadixString(16).padLeft(2, '0')); }
    return sb.toString();
  }
  List<String> _generateTicketSalts(int n) =>
      List<String>.generate(n, (_) => _randomSaltHex(32)); // 32 bytes = 64 hex chars

  Future<void> _pickReceipt() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() => _receiptImage = File(image.path));
    }
  }

  Future<bool?> _showConfirmationDialog({
    required String name,
    required String account,
    required String method,
    required List<int> selectedAmounts,
    required File receiptImage,
    required int ticketCount,
  }) {
    final amountsText = selectedAmounts.map((a) => 'Rs. $a').join(', ');
    final total = selectedAmounts.fold<int>(0, (p, n) => p + n);

    final isRunning = _drawStatus.toLowerCase() == 'running';
    final phaseHint = isRunning
        ? 'Your payment will be reviewed during the current draw.'
        : 'Submissions now count toward the NEXT draw.';

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Payment Submission'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Name: $name'),
              const SizedBox(height: 6),
              Text('Account: $account'),
              const SizedBox(height: 6),
              Text('Method: $method'),
              const SizedBox(height: 6),
              Text('Amount(s): $amountsText'),
              const SizedBox(height: 6),
              Text('Tickets: $ticketCount'),
              const SizedBox(height: 6),
              Text('Total: Rs. $total', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text(phaseHint, style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 12),
              const Text('Receipt preview:'),
              const SizedBox(height: 8),
              SizedBox(
                height: 160, width: double.infinity,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(receiptImage, fit: BoxFit.cover),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: ()=>Navigator.of(context).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700),
            onPressed: ()=>Navigator.of(context).pop(true),
            child: const Text('Confirm & Submit'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitPayment() async {
    // Basic validation (KEEP: we never write admin-only fields)
    if (_nameController.text.isEmpty ||
        _accountController.text.isEmpty ||
        _selectedMethod == null ||
        _selectedAmount == null ||
        _receiptImage == null ||
        (_selectedMethod == 'Other' && _otherMethodController.text.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please complete all fields.")));
      return;
    }

    final name = _nameController.text.trim();
    final account = _accountController.text.trim();
    final method = _selectedMethod == 'Other' ? _otherMethodController.text.trim() : _selectedMethod!;
    final selectedAmounts = <int>[_selectedAmount!];
    final ticketCount = _amountToTicketCount(_selectedAmount!);
    final totalAmount = selectedAmounts.fold<int>(0, (p, n) => p + n);

    final confirmed = await _showConfirmationDialog(
      name: name, account: account, method: method,
      selectedAmounts: selectedAmounts, receiptImage: _receiptImage!, ticketCount: ticketCount,
    );
    if (confirmed != true) return;

    try {
      setState(() => _isLoading = true);

      // 1) Upload receipt to Cloudinary
      final uploadUrl = Uri.parse("https://api.cloudinary.com/v1_1/$cloudName/image/upload");
      final request = http.MultipartRequest('POST', uploadUrl)
        ..fields['upload_preset'] = uploadPreset
        ..fields['folder'] = "receipt_images"
        ..files.add(await http.MultipartFile.fromPath('file', _receiptImage!.path));
      final streamed = await request.send();
      final resp = await http.Response.fromStream(streamed);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception("Failed to upload image (${resp.statusCode}): ${resp.body}");
      }
      final img = json.decode(resp.body);
      final imageUrl = (img['secure_url'] as String?) ?? '';
      if (imageUrl.isEmpty) throw Exception("Cloudinary didn't return secure_url");

      // 2) Require user
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please sign in to submit payment.")));
        Navigator.pushNamed(context, '/access');
        return;
      }
      final userId = user.uid;
      final buyerEmail = user.email ?? '';
      const buyerPhone = ''; // not collected here

      // 3) Snapshot draws/latest (status & ids)
      String? drawPath;
      String? drawStatus;
      String? currentDrawId;
      String? nextDrawId;

      try {
        final drawDoc = await FirebaseFirestore.instance.collection('draws').doc('latest').get();
        if (drawDoc.exists) {
          final d = drawDoc.data() ?? <String, dynamic>{};
          drawPath = drawDoc.reference.path;
          drawStatus = (d['status'] ?? '').toString();
          currentDrawId = d['currentDrawId']?.toString();
          nextDrawId = d['nextDrawId']?.toString();
        }
      } catch (_) {}

      final isRunning = (drawStatus ?? '').toLowerCase() == 'running';
      final forNextDraw = !isRunning;

      // Decide which drawId to tag
      final String? drawId = isRunning
          ? (currentDrawId?.isNotEmpty == true ? currentDrawId : null)
          : (nextDrawId?.isNotEmpty == true ? nextDrawId : (currentDrawId?.isNotEmpty == true ? currentDrawId : null));

      // 4) Pre-generate cryptographic salts (one per ticket)
      final ticketSalts = _generateTicketSalts(ticketCount);

      // 5) Atomic write: user ticket + payment (PENDING ONLY)
      final fs = FirebaseFirestore.instance;
      final batch = fs.batch();

      final ticketRef = fs.collection('users').doc(userId).collection('tickets').doc();
      final paymentRef = fs.collection('payments').doc();

      final base = <String, dynamic>{
        'selectedAmounts': selectedAmounts,
        'totalAmount': totalAmount,
        'ticketCount': ticketCount,
        'receiptUrl': imageUrl,

        // REQUIRED by rules for create:
        'confirmed': false,
        'status': 'pending',

        // Owner/metadata
        'userId': userId,
        'date': FieldValue.serverTimestamp(),
        'archived': false,

        // Draw awareness (read-only hints for admins)
        'drawStatusAtSubmit': drawStatus ?? '',
        'forNextDraw': forNextDraw,
        'confirmationAllowedAtSubmit': isRunning,
        if (drawPath != null) 'drawPath': drawPath,
        if (drawId != null) 'drawId': drawId,
        'drawIdSource': isRunning ? 'current' : 'next',
        'drawAssignedAt': FieldValue.serverTimestamp(),

        // Integrity
        'ticketSalts': ticketSalts,
        'integrity': {'salted': true, 'ver': 1},

        // DO NOT set lotteryNumber (omit entirely). Allow empty list (per rules).
        'lotteryNumbers': <String>[],
      };

      final ticketData = {
        ...base,
        'buyerName': name,
        'buyerEmail': buyerEmail,
        'buyerPhone': buyerPhone,
        'accountNumber': account,
        'paymentMethod': method,
        'paymentRef': paymentRef.path,
        // tickets rules require: status=='pending', confirmed==false, no winner flags or numbers set
      };

      final paymentData = {
        ...base,
        'name': name,
        'buyerName': name,
        'buyerEmail': buyerEmail,
        'buyerPhone': buyerPhone,
        'accountNumber': account,
        'paymentMethod': method,
        'userTicketPath': ticketRef.path,
        // payments rules require: isOwner(userId), confirmed==false, status 'pending', no admin-only fields on create
      };

      batch.set(ticketRef, ticketData);
      batch.set(paymentRef, paymentData);
      await batch.commit();

      setState(() => _isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Payment submitted successfully.")));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error submitting payment: $e")));
    }
  }

  Widget _buildLoginStyleField(TextEditingController controller, String label, {TextInputType type = TextInputType.text}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 3))],
      ),
      child: TextField(
        controller: controller,
        keyboardType: type,
        style: const TextStyle(color: Colors.black87),
        decoration: InputDecoration(
          hintText: label,
          hintStyle: const TextStyle(color: Colors.grey),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  // Payment info card (copy copies digits only)
  Widget _buildPaymentInfoCard() {
    const accountDigits = '03453811669';
    const accountNumberLabel = 'Account Number : $accountDigits';
    const accountName = 'Acc Name : Muhammad Ishaq';
    const supported = 'Easypaisa, JazzCash, Sadapay, Upaisa and Bank Accounts Please Pay On One of Them';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 6.0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.98),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 18, offset: const Offset(0, 8))],
          border: Border.all(color: Colors.green.shade700, width: 1.2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Important Note: After submitting Payment Details you will get an Email of Payment Confirmation and the detail will also be confirmed in the Ticket History page in a Minute.',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Pay First on the given Acc Number and Then Enter the Payment Detail Below',
              style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(accountNumberLabel, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.black87)),
                      SizedBox(height: 6),
                      Text(accountName, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Copy account number',
                  onPressed: () {
                    Clipboard.setData(const ClipboardData(text: accountDigits));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account number copied')));
                  },
                  icon: Icon(Icons.copy, color: Colors.green.shade700),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text('The Above Account Number Have: $supported', style: TextStyle(color: Colors.black)),
          ],
        ),
      ),
    );
  }

  // Draw status banner
  Widget _drawStatusBanner() {
    final s = _drawStatus.toLowerCase();
    Color bg; String label; String hint;
    if (s == 'running') {
      bg = Colors.green.shade800; label = 'DRAW RUNNING'; hint = 'Submit now to join the current draw.';
    } else if (s == 'winner' || s == 'winners_announced') {
      bg = Colors.purple.shade700; label = 'WINNERS PHASE'; hint = 'Submissions now will count toward the NEXT draw.';
    } else {
      bg = Colors.blueGrey.shade700; label = 'NO ACTIVE DRAW'; hint = 'Your submission will be queued for the next draw.';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 6.0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: bg.withOpacity(0.95),
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 6))],
        ),
        child: Row(
          children: [
            const Icon(Icons.info, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(hint, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _accountController.dispose();
    _otherMethodController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottomInset = mq.viewInsets.bottom;
    final drawStream = FirebaseFirestore.instance.collection('draws').doc('latest').snapshots();

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(65),
        child: AppBar(
          backgroundColor: Colors.black,
          elevation: 0,
          centerTitle: true,
          title: const Text("Ticket Confirmation", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
        ),
      ),
      body: Stack(
        children: [
          // background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF3BB78F), Color(0xFF0BAB64)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
          ),
          Positioned(left: -60, top: -80,
            child: Container(width: 220, height: 220, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.06))),
          ),
          Positioned(right: -40, bottom: -80,
            child: Transform.rotate(angle: -0.2,
              child: Container(width: 300, height: 250, decoration: BoxDecoration(borderRadius: BorderRadius.circular(46), color: Colors.white.withOpacity(0.04))),
            ),
          ),

          // content
          SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + bottomInset),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 18),
                  FadeInUp(
                    duration: const Duration(milliseconds: 700),
                    child: const Text("Ticket Confirmation", style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(height: 10),
                  FadeInUp(
                    delay: const Duration(milliseconds: 120),
                    child: Text('Upload payment receipt and submit for verification.',
                        style: TextStyle(color: Colors.white.withOpacity(0.92), fontSize: 14)),
                  ),
                  const SizedBox(height: 12),

                  // reactive draw status banner
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: drawStream,
                    builder: (context, snap) {
                      _drawStatus = (snap.data?.data()?['status'] ?? '').toString();
                      return _drawStatusBanner();
                    },
                  ),

                  const SizedBox(height: 6),
                  _buildPaymentInfoCard(),

                  // form card
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.96),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.14), blurRadius: 26, offset: const Offset(0, 12))],
                      ),
                      child: Column(
                        children: [
                          _buildLoginStyleField(_nameController, "Buyer Name"),
                          _buildLoginStyleField(_accountController, "Account Number", type: TextInputType.number),

                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: DropdownButtonFormField<String>(
                              decoration: InputDecoration(
                                labelText: "Payment Method",
                                labelStyle: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
                                filled: true, fillColor: Colors.white,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.black26)),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.green.shade700)),
                              ),
                              dropdownColor: Colors.white,
                              style: const TextStyle(color: Colors.black),
                              value: _selectedMethod,
                              items: _paymentMethods.map((m)=>DropdownMenuItem(value: m, child: Text(m))).toList(),
                              onChanged: (value) => setState(() => _selectedMethod = value),
                            ),
                          ),

                          if (_selectedMethod == 'Other') _buildLoginStyleField(_otherMethodController, "Other Method Name"),

                          const SizedBox(height: 15),
                          const Align(alignment: Alignment.centerLeft, child: Text("Select Ticket Amount:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87))),
                          _amountTile(100),
                          _amountTile(200),
                          _amountTile(300),

                          const SizedBox(height: 20),
                          const Align(alignment: Alignment.centerLeft, child: Text("Upload Receipt Image:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87))),
                          const SizedBox(height: 10),

                          GestureDetector(
                            onTap: _pickReceipt,
                            child: Container(
                              width: double.infinity, height: 160,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(15),
                                border: Border.all(color: Colors.grey.shade400),
                              ),
                              child: _receiptImage != null
                                  ? ClipRRect(borderRadius: BorderRadius.circular(15), child: Image.file(_receiptImage!, fit: BoxFit.cover))
                                  : const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                      Icon(Icons.upload_file, size: 40, color: Colors.grey),
                                      SizedBox(height: 8),
                                      Text("Tap to Upload Receipt", style: TextStyle(color: Colors.grey)),
                                    ])),
                            ),
                          ),

                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity, height: 52,
                            child: ElevatedButton.icon(
                              onPressed: _isLoading ? null : _submitPayment,
                              icon: const Icon(Icons.send),
                              label: const Text("Submit", style: TextStyle(fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green.shade700, foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                                elevation: 12, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 18.0),
                    child: FadeInUp(
                      delay: const Duration(milliseconds: 300),
                      child: const Text('Powered by Professor', style: TextStyle(fontSize: 14, color: Colors.white70, fontStyle: FontStyle.italic)),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_isLoading) const PositionedFillOverlay(),
        ],
      ),
    );
  }

  Widget _amountTile(int value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.96),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 3))],
        ),
        child: RadioListTile<int>(
          title: Text("Rs. $value", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
          value: value,
          groupValue: _selectedAmount,
          onChanged: (val) => setState(() => _selectedAmount = val),
          activeColor: Colors.green.shade700,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }
}

class PositionedFillOverlay extends StatelessWidget {
  const PositionedFillOverlay({super.key});
  @override
  Widget build(BuildContext context) {
    return const Positioned.fill(
      child: ColoredBox(color: Colors.black54, child: Center(child: CircularProgressIndicator())),
    );
  }
}
