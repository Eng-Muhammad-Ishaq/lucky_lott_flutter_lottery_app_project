// contact_page.dart
import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class ContactPage extends StatefulWidget {
  const ContactPage({super.key});

  @override
  State<ContactPage> createState() => _ContactPageState();
}

class _ContactPageState extends State<ContactPage> {
  static const String _email = 'luckylott.pvt@gmail.com';
  static const String _phone = '03453811669'; // display only
  static const String _phoneE164 = '+923453811669'; // used for tel: on Android
  // WhatsApp international (no plus): Pakistan +92
  static const String _whatsappNumberIntl = '923453811669';
  static const String _whatsappDisplay = 'luckylott 03453811669';

  // ---- helpers
  Future<bool> _tryExternal(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      return ok;
    } catch (_) {
      return false;
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$label copied to clipboard')));
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ---- actions
  Future<void> _launchEmail() async {
    final emailUri = Uri(
      scheme: 'mailto',
      path: _email,
      queryParameters: {'subject': 'Lucky Lott — Support Request'},
    );

    // 1) Try mailto: to an installed email app
    if (await _tryExternal(emailUri)) return;

    // 2) Fallback to Gmail web compose (works if Gmail/web available)
    final fallback = Uri.parse(
      'https://mail.google.com/mail/?view=cm&fs=1'
      '&to=${Uri.encodeComponent(_email)}'
      '&su=${Uri.encodeComponent('Lucky Lott — Support Request')}',
    );
    if (await _tryExternal(fallback)) return;

    _showError('No mail app found on this device.');
  }

  Future<void> _callNumber() async {
    // Use E.164 for Android reliability
    final telUriPrimary = Uri(scheme: 'tel', path: _phoneE164);
    if (await _tryExternal(telUriPrimary)) return;

    // Fallback to the local-format number just in case
    final telUriFallback = Uri(scheme: 'tel', path: _phone);
    if (await _tryExternal(telUriFallback)) return;

    _showError('Could not start call (no dialer available).');
  }

  Future<void> _openWhatsApp() async {
    final msg = Uri.encodeComponent('Hello Lucky Lott, I need support.');

    // 1) Try the native WhatsApp scheme directly
    final waScheme = Uri.parse('whatsapp://send?phone=$_whatsappNumberIntl&text=$msg');
    if (await _tryExternal(waScheme)) return;

    // 2) Fallback to universal wa.me link (browser / WhatsApp)
    final waMe = Uri.parse('https://wa.me/$_whatsappNumberIntl?text=$msg');
    if (await _tryExternal(waMe)) return;

    // 3) Open Play Store to install WhatsApp
    final market = Uri.parse('market://details?id=com.whatsapp');
    if (await _tryExternal(market)) return;

    // 4) Fallback to Play Store web
    final playStore = Uri.parse('https://play.google.com/store/apps/details?id=com.whatsapp');
    if (await _tryExternal(playStore)) return;

    _showError('Could not open WhatsApp.');
  }

  /// Material + InkWell contact tile so the ripple appears correctly on the rounded card.
  /// Provide rippleColor to tint the splash/highlight (use for branding).
  Widget _contactTile({
    required IconData iconData,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required VoidCallback onCopy,
    String? trailingText,
    Color? iconColor,
    Color? rippleColor,
  }) {
    final Color splash = (rippleColor ?? Colors.green).withOpacity(0.28);
    final Color highlight = (rippleColor ?? Colors.green).withOpacity(0.12);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Material(
        color: Colors.white.withOpacity(0.98),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          splashColor: splash,
          highlightColor: highlight,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              leading: Icon(iconData, color: iconColor ?? Colors.green.shade700, size: 28),
              title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(subtitle),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (trailingText != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: Text(trailingText, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    onPressed: onCopy,
                    tooltip: 'Copy',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottomInset = mq.viewInsets.bottom;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
        title: const Text('Contact Us',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context)),
      ),
      body: Stack(
        children: [
          // gradient background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF3BB78F), Color(0xFF0BAB64)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),

          // decorative shapes
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

          SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + bottomInset),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 18),

                  Center(
                    child: Bounce(
                      infinite: true,
                      duration: const Duration(milliseconds: 1200),
                      from: 6,
                      child: CircleAvatar(
                        radius: 56,
                        backgroundColor: Colors.white.withOpacity(0.12),
                        child: const Icon(Icons.contact_mail, size: 64, color: Colors.white),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  FadeInUp(
                    duration: const Duration(milliseconds: 700),
                    child: const Text('Contact Us',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        )),
                  ),

                  const SizedBox(height: 8),

                  FadeInUp(
                    delay: const Duration(milliseconds: 120),
                    child: Text(
                      'We’re here to help — reach out via email, phone or WhatsApp.',
                      style: TextStyle(color: Colors.white.withOpacity(0.92)),
                    ),
                  ),

                  const SizedBox(height: 18),

                  // content card
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Container(
                      width: double.infinity,
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
                          _contactTile(
                            iconData: Icons.email_outlined,
                            title: 'Email',
                            subtitle: _email,
                            iconColor: Colors.blue.shade700,
                            rippleColor: Colors.blue,
                            onTap: _launchEmail,
                            onCopy: () => _copyToClipboard(_email, 'Email'),
                          ),
                          _contactTile(
                            iconData: Icons.phone,
                            title: 'Call Us',
                            subtitle: _phone,
                            iconColor: Colors.orange.shade800,
                            rippleColor: Colors.orange,
                            onTap: _callNumber,
                            onCopy: () => _copyToClipboard(_phone, 'Phone'),
                            trailingText: 'Call',
                          ),
                          _contactTile(
                            iconData: FontAwesomeIcons.whatsapp,
                            title: 'WhatsApp',
                            subtitle: _whatsappDisplay,
                            iconColor: Colors.green.shade700,
                            rippleColor: Colors.green,
                            onTap: _openWhatsApp,
                            onCopy: () => _copyToClipboard(_whatsappDisplay, 'WhatsApp'),
                          ),

                          const SizedBox(height: 8),
                          const Divider(),
                          const SizedBox(height: 8),

                          const Text('Important Information',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text('• Support hours: Mon–Sat, 09:00–18:00 (local time). Responses usually within 24–48 hours.'),
                              SizedBox(height: 6),
                              Text('• For payment issues include your receipt image, transaction ID, and the date/time of payment.'),
                              SizedBox(height: 6),
                              Text('• Do NOT send full sensitive personal documents via chat. Use secure instructions if requested by support.'),
                              SizedBox(height: 6),
                              Text('• For disputes: send proof (receipt + account details) so we can investigate.'),
                              SizedBox(height: 6),
                              Text('• We may log support requests and attachments for fraud prevention and audit.'),
                            ],
                          ),

                          const SizedBox(height: 14),
                          const Text('Privacy & Safety',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 8),
                          const Text(
                            'We treat your data carefully. Receipt images and contact info are stored to verify payments and fight fraud. '
                            'If you need data removed, request via support and we will follow applicable law.',
                          ),

                          const SizedBox(height: 18),
                          Column(
                            children: const [
                              Text('© 2025 Lucky Lott. All rights reserved.',
                                  style: TextStyle(fontSize: 12, color: Colors.black54)),
                              SizedBox(height: 6),
                              Text('Powered by Professor',
                                  style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: Colors.black54)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
