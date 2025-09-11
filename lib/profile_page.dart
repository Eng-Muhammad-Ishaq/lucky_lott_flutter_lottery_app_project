// profile_page.dart
// UI: AccessPage style + clearer image upload controls.
// NOTE: All Cloudinary / Firestore / Auth logic is unchanged from your original file.

import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:animate_do/animate_do.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  // form
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  // image
  final ImagePicker _picker = ImagePicker();
  File? _localImageFile; // newly picked local image
  String? _remoteImageUrl; // image url from Firestore (if any)
  // ignore: unused_field
  String? _remoteImageFileName;

  // loading / saving states
  bool _isPageLoading = true;
  bool _isSaving = false;
  bool _showIncompleteDialog = false;

  // Cloudinary config (kept same as your original)
  final String _cloudName = "dyanef8fu";
  final String _uploadPreset = "lucky_preset";

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  // Pull-to-refresh handler
  Future<void> _onRefresh() async {
    await _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isPageLoading = true;
    });

    try {
      final user = _auth.currentUser;
      if (user == null) {
        setState(() {
          _isPageLoading = false;
        });
        return;
      }

      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        final name = (data['name'] ?? '').toString();
        final phone = (data['phone'] ?? '').toString();
        final imageUrl = (data['imageUrl'] ?? '').toString();
        final imageFileName = (data['imageFileName'] ?? '').toString();

        _nameController.text = name;
        _phoneController.text = phone;
        _remoteImageUrl = imageUrl.isNotEmpty ? imageUrl : null;
        _remoteImageFileName = imageFileName.isNotEmpty ? imageFileName : null;

        // If profile incomplete, show the dialog once
        final isIncomplete = name.trim().isEmpty || phone.trim().isEmpty || _remoteImageUrl == null;
        if (isIncomplete && !_showIncompleteDialog) {
          _showIncompleteDialog = true;
          Future.delayed(Duration.zero, () {
            if (mounted) {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text("Complete your profile"),
                  content: const Text("To continue using the app, please complete your profile."),
                  actions: [
                    TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text("OK"))
                  ],
                ),
              );
            }
          });
        }
      } else {
        _remoteImageUrl = null;
        _remoteImageFileName = null;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to load profile: $e")));
      }
    } finally {
      if (mounted) setState(() => _isPageLoading = false);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(source: source, imageQuality: 85);
      if (picked != null) {
        setState(() {
          _localImageFile = File(picked.path);
        });
        // small UI feedback (doesn't change any upload logic)
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Image selected — press Save Changes to upload")));
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Image pick failed: $e")));
    }
  }

  void _showImageOptions() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.of(ctx).pop();
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.of(ctx).pop();
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      ),
    );
  }

  // Validate name & phone
  String? _validateName(String? val) {
    if (val == null || val.trim().isEmpty) return "Name is required";
    if (val.trim().length < 2) return "Enter at least 2 characters";
    return null;
  }

  String? _validatePhone(String? val) {
    if (val == null || val.trim().isEmpty) return "Phone is required";
    final cleaned = val.replaceAll(RegExp(r'\s+'), '');
    final reg = RegExp(r'^[0-9]{7,15}$'); // basic rule
    if (!reg.hasMatch(cleaned)) return "Enter valid digits (7-15)";
    return null;
  }

  Future<void> _saveProfile() async {
    // run validation
    final form = _formKey.currentState;
    if (form == null) return;
    if (!form.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please fix form errors")));
      return;
    }

    final user = _auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("❌ User not logged in")));
      return;
    }

    setState(() => _isSaving = true);

    String? uploadedImageUrl;
    String? uploadedFileName;

    try {
      // Upload only if user picked a new local image
      if (_localImageFile != null) {
        final uri = Uri.parse("https://api.cloudinary.com/v1_1/$_cloudName/image/upload");
        final request = http.MultipartRequest('POST', uri)
          ..fields['upload_preset'] = _uploadPreset
          ..files.add(await http.MultipartFile.fromPath('file', _localImageFile!.path));

        final streamed = await request.send();
        final res = await http.Response.fromStream(streamed);

        if (res.statusCode >= 200 && res.statusCode < 300) {
          final data = json.decode(res.body);
          uploadedImageUrl = data['secure_url'];
          uploadedFileName = data['public_id'] ?? _localImageFile!.path.split('/').last;
        } else {
          throw Exception('Cloudinary upload failed (${res.statusCode})');
        }
      }

      // Prepare map to write to Firestore (merge existing)
      final Map<String, dynamic> updateMap = {
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'updated_at': FieldValue.serverTimestamp(),
      };

      if (uploadedImageUrl != null) {
        updateMap['imageUrl'] = uploadedImageUrl;
        updateMap['imageFileName'] = uploadedFileName ?? '';
      }

      await _firestore.collection('users').doc(user.uid).set(updateMap, SetOptions(merge: true));

      // Clear local image (we now rely on remote or keep local for preview)
      setState(() {
        if (uploadedImageUrl != null) {
          _remoteImageUrl = uploadedImageUrl;
          _remoteImageFileName = uploadedFileName;
          _localImageFile = null; // optional: clear so we show network
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Profile updated successfully!")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ Failed to update profile: $e")));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _sendPasswordResetEmail() async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No signed-in user with email.")));
      return;
    }
    try {
      await _auth.sendPasswordResetEmail(email: user.email!);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Password reset email sent.")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to send reset email: $e")));
    }
  }

  Future<void> _signOut() async {
    await _auth.signOut();
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/access');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Widget _buildAvatar(double radius) {
    final double size = radius * 2;
    final Widget avatarChild = _localImageFile != null
        ? ClipOval(child: Image.file(_localImageFile!, width: size, height: size, fit: BoxFit.cover))
        : (_remoteImageUrl != null
            ? ClipOval(child: Image.network(_remoteImageUrl!, width: size, height: size, fit: BoxFit.cover))
            : CircleAvatar(radius: radius, backgroundColor: Colors.white.withOpacity(0.12), child: Icon(Icons.person, size: radius, color: Colors.white)));

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
      child: SizedBox(width: size, height: size, child: avatarChild, key: ValueKey(_localImageFile?.path ?? _remoteImageUrl ?? 'default')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    final isLoggedIn = user != null;
    MediaQuery.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
        title: const Text("Profile", style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.maybePop(context),
        ),
      ),
      body: Stack(
        children: [
          // background gradient + shapes (same as AccessPage)
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
          RefreshIndicator(
            onRefresh: _onRefresh,
            child: _isPageLoading
                ? ListView(
                    children: const [
                      SizedBox(height: 220),
                      Center(child: CircularProgressIndicator(color: Colors.white)),
                    ],
                  )
                : SingleChildScrollView(
                    padding: EdgeInsets.only(bottom: 18 + bottomInset),
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 18),

                            // Top: big avatar with subtle bounce (matches AccessPage)
                            Center(
                              child: Bounce(
                                infinite: true,
                                duration: const Duration(milliseconds: 1200),
                                from: 6,
                                child: _buildAvatar(56),
                              ),
                            ),

                            const SizedBox(height: 12),

                            // camera overlay button (small) - tappable
                            Stack(
                              alignment: Alignment.center,
                              children: const [
                                SizedBox(height: 6),
                              ],
                            ),

                            // Clear Change Photo button so users can see how to upload
                            TextButton.icon(
                              onPressed: _showImageOptions,
                              icon: const Icon(Icons.camera_alt, color: Colors.white),
                              label: const Text('Upload Photo', style: TextStyle(color: Colors.white)),
                              style: TextButton.styleFrom(
                                backgroundColor: Colors.grey.shade700.withOpacity(0.2),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              ),
                            ),

                            const SizedBox(height: 12),

                            // Title & subtitle
                            FadeInUp(
                              duration: const Duration(milliseconds: 700),
                              child: const Text(
                                "Your Profile",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),

                            const SizedBox(height: 10),

                            FadeInUp(
                              delay: const Duration(milliseconds: 150),
                              duration: const Duration(milliseconds: 700),
                              child: Text(
                                isLoggedIn ? (user.email ?? '') : 'Not signed in',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.92),
                                  fontSize: 14,
                                ),
                              ),
                            ),

                            const SizedBox(height: 18),

                            // Card container styled like AccessPage's form card
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
                                    Row(
                                      children: [
                                        Icon(Icons.person_outline, color: Colors.green.shade700),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Edit your profile',
                                          style: TextStyle(
                                            color: Colors.grey.shade900,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 14),

                                    Form(
                                      key: _formKey,
                                      autovalidateMode: AutovalidateMode.onUserInteraction,
                                      child: Column(
                                        children: [
                                          // Name field wrapped to mimic AccessPage input style
                                          _styledInput(
                                            controller: _nameController,
                                            label: 'Full Name',
                                            hint: 'Professor',
                                            icon: Icons.person_outline,
                                            validator: _validateName,
                                          ),
                                          const SizedBox(height: 8),

                                          _styledInput(
                                            controller: _phoneController,
                                            label: 'Phone number',
                                            hint: '0345 0000000',
                                            icon: Icons.phone,
                                            keyboardType: TextInputType.phone,
                                            validator: _validatePhone,
                                          ),

                                          const SizedBox(height: 12),

                                          // Save button
                                          SizedBox(
                                            width: double.infinity,
                                            height: 52,
                                            child: ElevatedButton(
                                              onPressed: _isSaving ? null : _saveProfile,
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.green.shade700,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                                elevation: 8,
                                                shadowColor: Colors.black45,
                                              ),
                                              child: _isSaving
                                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                                  : Row(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      children: const [
                                                        SizedBox(width: 6),
                                                        Icon(Icons.save, color: Colors.white),
                                                        SizedBox(width: 12),
                                                        Text('Save Changes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                                      ],
                                                    ),
                                            ),
                                          ),

                                          const SizedBox(height: 8),

                                          Text(
                                            'By saving, you agree to our terms',
                                            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                                          ),

                                          const SizedBox(height: 8),

                                          OutlinedButton.icon(
                                            onPressed: _sendPasswordResetEmail,
                                            icon: Icon(Icons.lock_reset, color: Colors.green.shade700),
                                            label: const Text('Send Password Reset Email'),
                                            style: OutlinedButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(vertical: 14),
                                              side: BorderSide(color: Colors.green.shade100),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                            ),
                                          ),

                                          const SizedBox(height: 8),

                                          OutlinedButton.icon(
                                            onPressed: isLoggedIn ? _signOut : () => Navigator.pushNamed(context, '/access'),
                                            icon: Icon(isLoggedIn ? Icons.logout : Icons.login, color: isLoggedIn ? Colors.red : Colors.green),
                                            label: Text(isLoggedIn ? 'Sign Out' : 'Sign In'),
                                            style: OutlinedButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(vertical: 14),
                                              side: BorderSide(color: Colors.grey.shade200),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 18),

                            // Footer - replace Spacer() with fixed gap so scrolling works
                            Padding(
                              padding: const EdgeInsets.only(bottom: 18.0),
                              child: FadeInUp(
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
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
        ),],
      ),
      // Bottom Navigation Bar (added)
      bottomNavigationBar: BottomNavigationBar(
  type: BottomNavigationBarType.fixed,        // keep black bg with 4 items
  currentIndex: 2,                             // 0=Home, 1=History, 2=Profile, 3=Winners
  backgroundColor: Colors.black,
  selectedItemColor: Colors.white,
  unselectedItemColor: Colors.white70,
  onTap: (index) {
    if (index == 0) {
      Navigator.pushNamed(context, '/home');   // <-- use your home route (e.g. '/home' or '/')
    } else if (index == 1) {
      Navigator.pushNamed(context, '/tickethistorypage');
    } else if (index == 2) {
      // already on Profile
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

  // Helper that creates AccessPage-like input containers
  Widget _styledInput({
    required TextEditingController controller,
    required String label,
    String? hint,
    IconData? icon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 3))],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.green.shade700),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: TextFormField(
              controller: controller,
              keyboardType: keyboardType,
              validator: validator,
              decoration: InputDecoration(
                labelText: label,
                hintText: hint,
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
