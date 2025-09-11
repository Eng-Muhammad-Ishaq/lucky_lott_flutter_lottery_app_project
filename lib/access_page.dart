import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AccessPage extends StatefulWidget {
  const AccessPage({super.key});

  @override
  State<AccessPage> createState() => _AccessPageState();
}

class _AccessPageState extends State<AccessPage> with TickerProviderStateMixin {
  // ---------------------------
  // State & controllers (kept names to preserve your logic)
  // ---------------------------
  bool _isLoading = false;
  bool showLogin = true;

  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController fullNameController = TextEditingController();

  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _nameFocus = FocusNode();

  bool _obscurePassword = true;

  // Animation controllers
  late AnimationController _iconBounceController;

  @override
  void initState() {
    super.initState();
    _iconBounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    fullNameController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _nameFocus.dispose();
    _iconBounceController.dispose();
    super.dispose();
  }

  // ---------------------------
  // Build
  // ---------------------------
  @override
  Widget build(BuildContext context) {
    MediaQuery.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;


    return Scaffold(
      // We want the app feel immersive - extend behind app bar if you add one
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Background gradient + abstract shapes
          _buildBackground(context),

          // Main content (fixed scroll behavior)
SingleChildScrollView(
  padding: EdgeInsets.only(bottom: 18 + bottomInset),
  child: SafeArea(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 18),

          // Top: big account icon with subtle bounce
          Center(
            child: Bounce(
              infinite: true,
              duration: const Duration(milliseconds: 1200),
              from: 6,
              child: CircleAvatar(
                radius: 56,
                backgroundColor: Colors.white.withOpacity(0.12),
                child: Icon(
                  Icons.account_circle,
                  size: 88,
                  color: Colors.white,
                ),
              ),
            ),
          ),

          const SizedBox(height: 18),

          // Title
          FadeInUp(
            duration: const Duration(milliseconds: 700),
            child: Text(
              showLogin ? "Welcome Back" : "Create Account",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),

          const SizedBox(height: 10),

          // Subtitle
          FadeInUp(
            delay: const Duration(milliseconds: 150),
            duration: const Duration(milliseconds: 700),
            child: Text(
              showLogin
                  ? "Sign in to continue to Lucky Lott"
                  : "Create an account to start buying tickets",
              style: TextStyle(
                color: Colors.white.withOpacity(0.92),
                fontSize: 14,
              ),
            ),
          ),

          const SizedBox(height: 18),

          // Tab toggles (Login / Sign Up)
          _buildToggleButtonsRow(),

          const SizedBox(height: 18),

          // Animated card container for forms
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            transitionBuilder: (child, animation) {
              final inAnim =
                  Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
                      .chain(CurveTween(curve: Curves.easeOut));
              return SlideTransition(
                position: animation.drive(inAnim),
                child: FadeTransition(opacity: animation, child: child),
              );
            },
            child: Padding(
              key: ValueKey<bool>(showLogin),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: _buildFormCard(),
            ),
          ),

          const SizedBox(height: 18),

          // Social icons row
          // Social icon (Google only, centered)
FadeInUp(
  delay: const Duration(milliseconds: 300),
  child: Center(
    child: _socialIcon(
      "assets/google.png",
      _handleGoogleLogin,
      tooltip: "Continue with Google",
    ),
  ),
),


          const SizedBox(height: 12),

          // Forgot password
          FadeInUp(
            delay: const Duration(milliseconds: 350),
            child: GestureDetector(
              onTap: _handleForgotPassword,
              child: Padding(
                padding: const EdgeInsets.only(top: 6.0),
                child: Text(
                  "Forgot Password?",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.95),
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ),

          // SMALL FIX: remove Spacer() (was causing overflow). use gap instead:
          const SizedBox(height: 18),

          // small footer / branding consistent with your ProfilePage
          Padding(
            padding: const EdgeInsets.only(bottom: 18.0),
            child: FadeInUp(
              delay: const Duration(milliseconds: 500),
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


          // Loading overlay (kept)
          if (_isLoading)
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

  // ---------------------------
  // Background builder (gradient + abstract shapes)
  // ---------------------------
  Widget _buildBackground(BuildContext context) {
    return Stack(
      children: [
        // main gradient
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF3BB78F), Color(0xFF0BAB64)], // green gradient
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),

        // soft top-left circle
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

        // soft bottom-right rotated rounded rectangle
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
      ],
    );
  }

  // ---------------------------
  // Toggle row -> Login / Sign Up
  // ---------------------------
  Widget _buildToggleButtonsRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildToggleButton("Login", showLogin, () {
          setState(() => showLogin = true);
        }),
        const SizedBox(width: 12),
        _buildToggleButton("Sign Up", !showLogin, () {
          setState(() => showLogin = false);
        }),
      ],
    );
  }

  Widget _buildToggleButton(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.white.withOpacity(0.18),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
              color: isSelected ? Colors.white.withOpacity(0.14) : Colors.white.withOpacity(0.06)),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    offset: const Offset(0, 6),
                    blurRadius: 12,
                  )
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.green.shade900 : Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  // ---------------------------
  // Form card (holds login OR signup based on showLogin)
  // ---------------------------
  Widget _buildFormCard() {
    return Container(
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
        children: [
          // Animated header inside card
          Row(
            children: [
              Icon(
                showLogin ? Icons.login : Icons.how_to_reg,
                color: Colors.green.shade700,
              ),
              const SizedBox(width: 8),
              Text(
                showLogin ? "Sign in with your account" : "Create your Lucky Lott account",
                style: TextStyle(
                  color: Colors.grey.shade900,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // AnimatedSwitcher to swap forms
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: showLogin ? _buildLoginForm() : _buildSignUpForm(),
          ),

          const SizedBox(height: 12),

          // Continue / Submit button
          _buildPrimaryActionButton(),

          const SizedBox(height: 8),

          // Small helper text (kept)
          Text(
            showLogin ? "Or continue using social accounts" : "By signing up you agree to our terms",
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ---------------------------
  // Login form (kept validations and controllers)
  // ---------------------------
  Widget _buildLoginForm() {
    return Column(
      key: const ValueKey('login_form'),
      children: [
        _buildTextField(
          controller: emailController,
          label: "Email",
          hint: "you@example.com",
          keyboardType: TextInputType.emailAddress,
          focusNode: _emailFocus,
          icon: Icons.email_outlined,
        ),
        const SizedBox(height: 8),
        _buildTextField(
          controller: passwordController,
          label: "Password",
          hint: "Enter password",
          obscure: _obscurePassword,
          focusNode: _passwordFocus,
          icon: Icons.lock_outline,
          suffix: GestureDetector(
            onTap: () => setState(() => _obscurePassword = !_obscurePassword),
            child: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off,
                color: Colors.grey.shade600),
          ),
        ),
      ],
    );
  }

  // ---------------------------
  // Sign-up form (kept saving to Firestore, fullNameController present)
  // ---------------------------
  Widget _buildSignUpForm() {
    return Column(
      key: const ValueKey('signup_form'),
      children: [
        _buildTextField(
          controller: fullNameController,
          label: "Full Name",
          hint: "Professor",
          keyboardType: TextInputType.name,
          focusNode: _nameFocus,
          icon: Icons.person_outline,
        ),
        const SizedBox(height: 8),
        _buildTextField(
          controller: emailController,
          label: "Email",
          hint: "you@example.com",
          keyboardType: TextInputType.emailAddress,
          focusNode: _emailFocus,
          icon: Icons.email_outlined,
        ),
        const SizedBox(height: 8),
        _buildTextField(
          controller: passwordController,
          label: "Password",
          hint: "Create a password",
          obscure: _obscurePassword,
          focusNode: _passwordFocus,
          icon: Icons.lock_outline,
          suffix: GestureDetector(
            onTap: () => setState(() => _obscurePassword = !_obscurePassword),
            child: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off,
                color: Colors.grey.shade600),
          ),
        ),
      ],
    );
  }

  // ---------------------------
  // Primary action button: calls your existing functions
  // ---------------------------
  Widget _buildPrimaryActionButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: () async {
            setState(() => _isLoading = true);
            if (showLogin) {
              await _loginWithEmail();
            } else {
              await _signUpWithEmail();
            }
            setState(() => _isLoading = false);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green.shade700,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 8,
            shadowColor: Colors.black45,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 6),
              Icon(
                showLogin ? Icons.login : Icons.how_to_reg,
                color: Colors.white,
              ),
              const SizedBox(width: 12),
              Text(
                showLogin ? "Login" : "Sign Up",
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------
  // Reusable input field builder with icon, hint, label etc.
  // ---------------------------
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType keyboardType = TextInputType.text,
    bool obscure = false,
    FocusNode? focusNode,
    IconData? icon,
    Widget? suffix,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 3))
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.green.shade700),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              obscureText: obscure,
              keyboardType: keyboardType,
              decoration: InputDecoration(
                labelText: label,
                hintText: hint,
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (suffix != null) suffix,
        ],
      ),
    );
  }

  // ---------------------------
  // Social icon button builder (kept image assets)
  // ---------------------------
  Widget _socialIcon(String assetPath, VoidCallback onTap, {String? tooltip}) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 6))],
          ),
          child: Image.asset(
            assetPath,
            width: 30,
            height: 30,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }

  // ---------------------------
  // Existing logic kept (forgot password, google sign-in, facebook placeholder)
  // I preserved your methods and their contents, only adapted small snackBar styles.
  // ---------------------------

  void _handleForgotPassword() {
    final TextEditingController resetEmailController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Forgot Password'),
        content: TextField(
          controller: resetEmailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Enter your email',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              setState(() => _isLoading = true);

              final email = resetEmailController.text.trim();
              if (email.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text("❌ Please enter an email."),
                    backgroundColor: Colors.red.shade400,
                  ),
                );
                setState(() => _isLoading = false);
                return;
              }

              try {
                await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text("📩 Reset email sent! Check the Mailbox or Spam!"),
                    backgroundColor: const Color.fromARGB(255, 0, 0, 0),
                  ),
                );
              } catch (e) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("❌ Error: $e"), backgroundColor: Colors.red.shade400),
                );
              }
              setState(() => _isLoading = false);
            },
            child: const Text('Send Email'),
          ),
        ],
      ),
    );
  }

  void _handleGoogleLogin() async {
    setState(() => _isLoading = true);

    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(scopes: ['email']);
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      UserCredential userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);

      final user = userCredential.user;

      if (user != null) {
        final userDoc = FirebaseFirestore.instance.collection('users').doc(user.uid);
        final snapshot = await userDoc.get();

        if (!snapshot.exists) {
          await userDoc.set({
            'full_name': user.displayName ?? '',
            'email': user.email ?? '',
            'photo_url': user.photoURL ?? '',
            'created_at': Timestamp.now(),
          });
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(" Welcome ${userCredential.user?.displayName}!"), backgroundColor: const Color.fromARGB(255, 0, 0, 0)),
      );

      Navigator.pushReplacementNamed(context, '/home');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Google Sign-In failed: $e"), backgroundColor: Colors.red.shade400),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  

  Future<void> _signUpWithEmail() async {
    setState(() => _isLoading = true);

    try {
      if (emailController.text.trim().isEmpty || passwordController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('⚠️ Please fill in all fields'), backgroundColor: Colors.orange.shade700),
        );
        setState(() => _isLoading = false);
        return;
      }

      final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      await FirebaseFirestore.instance.collection('users').doc(credential.user!.uid).set({
        'full_name': fullNameController.text.trim(),
        'email': emailController.text.trim(),
        'photo_url': '',
        'created_at': Timestamp.now(),
      });

      emailController.clear();
      passwordController.clear();
      fullNameController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('Congrats! Account created!'), backgroundColor: const Color.fromARGB(255, 0, 0, 0)),
      );

      Navigator.pushReplacementNamed(context, '/home');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Sign-Up Failed: $e'), backgroundColor: Colors.red.shade400),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loginWithEmail() async {
    setState(() => _isLoading = true);

    try {
      if (emailController.text.trim().isEmpty || passwordController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('⚠️ Please fill in all fields'), backgroundColor: Colors.orange.shade700),
        );
        setState(() => _isLoading = false);
        return;
      }

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      emailController.clear();
      passwordController.clear();
      fullNameController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('Logged in'), backgroundColor: const Color.fromARGB(255, 11, 11, 11)),
      );

      Navigator.pushReplacementNamed(context, '/home');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Login Failed: $e'), backgroundColor: Colors.red.shade400),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }
}
