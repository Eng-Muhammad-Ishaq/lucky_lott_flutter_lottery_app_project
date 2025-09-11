// agreement_page.dart
// Full User Agreement page with "I Agree" checkbox and acceptance recording.
// UI matches AccessPage styling.

import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AgreementPage extends StatefulWidget {
  // If showAsModal is true, the page will pop after accept; otherwise it behaves normally.
  final bool showAsModal;
  const AgreementPage({super.key, this.showAsModal = false});

  @override
  State<AgreementPage> createState() => _AgreementPageState();
}

class _AgreementPageState extends State<AgreementPage> {
  bool _accepted = false;
  bool _isSaving = false;

  // agreement metadata
  static const _agreementVersion = '1.0';
  static const _effectiveDate = 'August 15, 2025';
  static const _prefsKey = 'acceptedAgreement_v1';

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'User Agreement',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          // Background gradient + decor
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
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(18, 20, 18, mq.viewInsets.bottom + 20),
              child: Column(
                children: [
                  const SizedBox(height: 18),

                  // Animated header
                  FadeInUp(
                    duration: const Duration(milliseconds: 700),
                    child: const Text(
                      'User Agreement',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),
                  FadeInUp(
                    delay: const Duration(milliseconds: 120),
                    child: Text(
                      'Please read the following terms carefully.',
                      style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14),
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Agreement card (scrollable inside)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Container(
                      width: double.infinity,
                      constraints: BoxConstraints(
                        // allow the card to grow but not explode
                        maxHeight: MediaQuery.of(context).size.height * 0.68,
                      ),
                      padding: const EdgeInsets.all(18),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Title
                          Center(
                            child: Text(
                              'User Agreement — Lucky Lott',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey.shade900),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Effective Date: $_effectiveDate',
                            style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey.shade900),
                          ),
                          const SizedBox(height: 12),

                          // Scrollable content inside the card (so long text stays manageable)
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: const [
                                  // --- Full Agreement text (condensed into readable blocks) ---
                                  // NOTE: This text mirrors the full agreement content for the app.
                                  Text(
                                    '1. Parties & Acceptance\n\n'
                                    'This User Agreement (“Agreement” or “Terms”) is between you (“you”, “user”) and Lucky Lott (“we”, “us”, “Lucky Lott”). By registering, logging in, submitting payment details, uploading images, or using any features of the Lucky Lott mobile application and related services (the “App”), you accept and agree to be bound by this Agreement. If you do not agree, do not use the App.\n\n',
                                    style: TextStyle(color: Colors.black87, fontSize: 14, height: 1.45),
                                  ),

                                  Text(
                                    '2. Services & Eligibility\n\n'
                                    'a. Lucky Lott provides a lottery-style ticket purchase service and related functionality (tickets, draws, winners, payment verification).\n'
                                    'b. You must be at least the minimum legal age in your jurisdiction to use the App and to participate in lotteries. If you are under that age, you must not use the App.\n'
                                    'c. You must provide accurate, current information when registering and keep it updated.\n\n',
                                    style: TextStyle(color: Colors.black87, fontSize: 14, height: 1.45),
                                  ),

                                  Text(
                                    '3. Account, Authentication & Security\n\n'
                                    'a. You are responsible for maintaining the confidentiality of your account credentials (email/password, social login). Do not share them.\n'
                                    'b. We provide Google sign-in as an option; login via Google uses data from your Google account as permitted by Google.\n'
                                    'c. You agree to notify us immediately if you suspect unauthorized use of your account. We will not be liable for losses caused by failure to secure your account.\n'
                                    'd. We may require additional verification (email, phone, or document) for certain transactions.\n\n',
                                    style: TextStyle(color: Colors.black87, fontSize: 14, height: 1.45),
                                  ),

                                  Text(
                                    '4. Payments, Receipts & No Refunds\n\n'
                                    'a. No Refund Policy: All purchases of tickets and ticket bundles are final and non-refundable unless otherwise required by law. By buying tickets you accept this.\n'
                                    'b. You must pay using the App’s supported payment channels (Easypaisa, JazzCash, Sadapay, Upaisa, or other supported methods). The App may instruct you to pay first to a specified account and then upload a receipt.\n'
                                    'c. You must upload a clear image of your payment receipt for verification. We store that image to verify payment. Payment submission is not complete until an admin or automated process confirms the payment in the App (status changes from pending to confirmed).\n'
                                    'd. We are not responsible for processing delays or errors in external payment networks or agents.\n\n',
                                    style: TextStyle(color: Colors.black87, fontSize: 14, height: 1.45),
                                  ),

                                  Text(
                                    '5. How We Handle Payment Verification & Ticket Assignment\n\n'
                                    'a. After you submit payment details and a receipt image, we create (i) a user ticket record under users/{uid}/tickets and (ii) a top-level payments record for admin processing. Both records are linked (userTicketPath & paymentRef). Both records contain your contact info and uploaded receipt URL.\n'
                                    'b. Admins review the payments entries and may confirm valid payments. When a payment is confirmed, the admin or automated process assigns lottery number(s) to your payment and/or user ticket. The number of assigned tickets depends on the selectedAmounts mapping (for example: Rs.100 → 1 ticket, Rs.200 → 3 tickets, Rs.300 → 5 tickets).\n'
                                    'c. Only confirmed payments participate in draws. Unconfirmed payments remain pending until confirmed or otherwise updated by admin action.\n\n',
                                    style: TextStyle(color: Colors.black87, fontSize: 14, height: 1.45),
                                  ),

                                  Text(
                                    '6. Uploaded Content & Use of Images\n\n'
                                    'a. You retain ownership of the photos and images you upload, but by uploading you grant Lucky Lott a non-exclusive, worldwide, royalty-free license to store, use, and process those images for verification, support, fraud prevention, customer service, and to display in the App when appropriate (for example, receipt preview or admin review).\n'
                                    'b. Receipt images and profile photos may be stored on third-party services (for example Cloudinary). Those services may have their own terms and policies. You consent to such third-party storage.\n'
                                    'c. Do not upload illegal content, copyrighted material you don’t own, or sensitive personal data (medical, government ID numbers) unless explicitly requested and authorized. If you must upload sensitive documents, follow secure instructions provided by us.\n\n',
                                    style: TextStyle(color: Colors.black87, fontSize: 14, height: 1.45),
                                  ),

                                  Text(
                                    '7. Data Collected, Purpose & Retention\n\n'
                                    'a. We collect information necessary for operation: name, email, phone, payment metadata, uploaded receipt images, transaction timestamps, ticket assignment, and app usage data. We also provide a dedicated in-app Contact/Support field — the contact method and any support message you submit through that field are stored with your account and used for support and dispute handling.\n'
                                    'b. Purposes: verify payments, assign tickets, run draws, communicate with you (email/push notifications), fraud prevention, audits, analytics, legal compliance.\n'
                                    'c. Retention: We retain payment and ticket records (including receipts) for as long as necessary to support disputes and regulatory requirements. Administrators may retain audit logs indefinitely. You may request deletion as permitted by applicable law; deletion may be limited if there are legal, regulatory, or business reasons to retain the record.\n\n',
                                    style: TextStyle(color: Colors.black87, fontSize: 14, height: 1.45),
                                  ),

                                  Text(
                                    '8. Admin Access & Support\n\n'
                                    'a. Admins and authorized staff may access user payment records, uploaded receipts, contact info, and ticket data for review and support. Admin actions (confirmations, undo, assigning numbers) are logged in an audit trail.\n'
                                    'b. Admins act per internal policy. We are not responsible for actions taken by rogue admins; if you suspect misuse, submit a support request using the App’s dedicated Contact/Support field so we can investigate.\n\n',
                                    style: TextStyle(color: Colors.black87, fontSize: 14, height: 1.45),
                                  ),

                                  Text(
                                    '9. Winner Selection & Prize Distribution\n\n'
                                    'a. Winners are selected by the process described in the App (selection from payments with confirmed lotteryNumbers). The App’s winner selection algorithm aims to be fair and may include constraints (for example, try to avoid selecting multiple winners from the same user). The algorithm may be run client-side or server-side; results written to draws/latest are canonical.\n'
                                    'b. Prize distribution: 50% of the total prize pool is distributed equally among winning tickets as per the published distribution rule; Lucky Lott retains 50% for operations and maintenance, unless otherwise specified. The precise award amounts per position are published in the App or draw announcement.\n'
                                    'c. Winners are announced publicly in the App for 24 hours; after that, the system clears numbers from non-winning payments and schedules the next draw (weekly by default).\n'
                                    'd. Prize claims: Winners must comply with any identity verification and claim process established by Lucky Lott. Failure to claim within required windows may forfeit the prize per the App’s policy.\n\n',
                                    style: TextStyle(color: Colors.black87, fontSize: 14, height: 1.45),
                                  ),

                                  Text(
                                    '10. Fraud, Disputes & Reversals\n\n'
                                    'a. We may refuse, suspend, or reverse ticket assignments and confirmed payments if fraud, mistake, or policy violations are detected. Reversals may update payments and users/{uid}/tickets to pending and remove lotteryNumbers.\n'
                                    'b. Disputes and support requests: Submit disputes or support requests only via the App’s dedicated Contact/Support field (do not attempt to use external methods unless the App provides them). When filing a dispute please include your payment reference, receipt details, and any requested supporting evidence. We will investigate and may require additional verification. Our decision is final subject to applicable law.\n\n',
                                    style: TextStyle(color: Colors.black87, fontSize: 14, height: 1.45),
                                  ),

                                  Text(
                                    '11. Notifications & Emails\n\n'
                                    'a. By using the App you consent to transactional emails, SMS (if provided), and push notifications for payment confirmations, wins, and other service-related messages. You may opt out of marketing messages but not transactional ones required to operate the service.\n\n',
                                    style: TextStyle(color: Colors.black87, fontSize: 14, height: 1.45),
                                  ),

                                  Text(
                                    '12. Third-Party Services & Limitations\n\n'
                                    'a. We use third-party services (Cloudinary for image storage, Firebase for auth & database, payment networks) and are not responsible for their outages, policy changes, or data use beyond what’s required for the App.\n'
                                    'b. You agree that Lucky Lott is not liable for third-party actions or failures.\n\n',
                                    style: TextStyle(color: Colors.black87, fontSize: 14, height: 1.45),
                                  ),

                                  Text(
                                    '13. Limits of Liability & Disclaimer\n\n'
                                    'a. THE SERVICE IS PROVIDED “AS IS.” TO THE MAXIMUM EXTENT PERMITTED BY LAW, LUCKY LOTT DISCLAIMS ALL WARRANTIES, EXPRESS OR IMPLIED, INCLUDING MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, OR NONINFRINGEMENT.\n'
                                    'b. LUCKY LOTT WILL NOT BE LIABLE FOR INDIRECT, INCIDENTAL, SPECIAL, OR CONSEQUENTIAL DAMAGES, OR LOST PROFITS, ARISING OUT OF YOUR USE OF THE APP, UNLESS REQUIRED BY LAW. OUR AGGREGATE LIABILITY IS LIMITED TO THE AMOUNT YOU PAID (IF ANY) TO US IN THE 12 MONTHS BEFORE THE CLAIM.\n\n',
                                    style: TextStyle(color: Colors.black87, fontSize: 14, height: 1.45),
                                  ),

                                  Text(
                                    '14. Account Termination & Suspension\n\n'
                                    'a. We may suspend or terminate accounts that violate this Agreement, attempt fraud, or for legal reasons. We may remove associated tickets or payments if required by law or policy.\n\n',
                                    style: TextStyle(color: Colors.black87, fontSize: 14, height: 1.45),
                                  ),

                                  Text(
                                    '15. Changes to the Agreement\n\n'
                                    'a. We may modify this Agreement from time to time. When changes are material, we will provide notice in the App or by email. Continued use after notice means you accept the new terms. The Effective Date at the top is the latest revision date.\n\n',
                                    style: TextStyle(color: Colors.black87, fontSize: 14, height: 1.45),
                                  ),

                                  Text(
                                    '16. Governing Law & Dispute Resolution\n\n'
                                    'a. This Agreement is governed by the laws of the jurisdiction where Lucky Lott is registered (update with your governing law). Disputes should be submitted first using the App’s dedicated Contact/Support field; unresolved disputes may be resolved in the courts or alternative dispute resolution mechanisms available in that jurisdiction.\n\n',
                                    style: TextStyle(color: Colors.black87, fontSize: 14, height: 1.45),
                                  ),

                                  Text(
                                    '17. User Representations & Warranties\n\n'
                                    'a. You represent that your uploaded receipts are truthful and accurate and that you have the right to provide any content you upload. You consent to the collection, storage, and usage described in this Agreement.\n\n',
                                    style: TextStyle(color: Colors.black87, fontSize: 14, height: 1.45),
                                  ),

                                  Text(
                                    '18. Privacy\n\n'
                                    'a. This Agreement incorporates our Privacy practices. For more details about how we collect, use, and share personal data, see our Privacy Policy (link/section). If you need immediate privacy details in the App, show a short “Privacy Summary” that references email storage, receipt images, and logs for disputes and fraud prevention.\n\n',
                                    style: TextStyle(color: Colors.black87, fontSize: 14, height: 1.45),
                                  ),

                                  Text(
                                    '19. Miscellaneous\n\n'
                                    'a. If a court finds a provision invalid, the rest remains enforceable. Headings are for convenience only. No waiver of a breach constitutes waiver of future breaches.\n\n',
                                    style: TextStyle(color: Colors.black87, fontSize: 14, height: 1.45),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Checkbox + accept button
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6.0),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Checkbox(
                              value: _accepted,
                              onChanged: (v) => setState(() => _accepted = v ?? false),
                              activeColor: Colors.green.shade700,
                            ),
                            const Expanded(
                              child: Text(
                                'I have read and agree to the Lucky Lott User Agreement.',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),

                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: (!_accepted || _isSaving) ? null : _onAcceptPressed,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade700,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 8,
                              shadowColor: Colors.black45,
                            ),
                            child: _isSaving
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Text('Accept & Continue', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Footer
                  FadeInUp(
                    delay: const Duration(milliseconds: 300),
                    child: const Text(
                      'Powered by Professor',
                      style: TextStyle(fontSize: 14, color: Colors.white70, fontStyle: FontStyle.italic),
                    ),
                  ),

                  const SizedBox(height: 18),
                ],
              ),
            ),
          ),

          // optional overlay while saving
          if (_isSaving)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black54,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _onAcceptPressed() async {
    setState(() => _isSaving = true);

    final user = FirebaseAuth.instance.currentUser;
    try {
      if (user != null) {
        // Save acceptance in Firestore under users/{uid}.acceptedAgreement
        final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
        await docRef.set({
          'acceptedAgreement': {
            'version': _agreementVersion,
            'effectiveDate': _effectiveDate,
            'acceptedAt': FieldValue.serverTimestamp(),
          }
        }, SetOptions(merge: true));
      } else {
        // Save locally if user not signed in yet
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_prefsKey, true);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Agreement accepted.')));

      if (widget.showAsModal) {
        Navigator.of(context).pop(true);
      } else {
        Navigator.of(context).maybePop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save acceptance: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
  