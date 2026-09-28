import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_functions/cloud_functions.dart';

class ForgotPage extends StatefulWidget {
  const ForgotPage({super.key});

  @override
  _ForgotPageState createState() => _ForgotPageState();
}

class _ForgotPageState extends State<ForgotPage> {
  // Shared theme palette (same as LoginPage / ProfilePage)
  static const Color _bgColor = Color(0xFF0B1220);
  static const Color _headerColor = Color(0xFF0F2B45);
  static const Color _headerColorLight = Color(0xFF17456F);
  static const Color _cardColor = Color(0xFF0F3B61);
  static const Color _textColor = Color(0xFFE6F0F8);
  static const Color _mutedTextColor = Color(0xFF9FB0C3);
  static const Color _accentColor = Color(0xFF3D8BFF);
  static const Color _errorColor = Color(0xFFF87171);
  static const Color _successColor = Color(0xFF4ADE80);

  final TextEditingController studentIdController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final FocusNode _emailFocus = FocusNode();
  final FirebaseFirestore db = FirebaseFirestore.instance;
  final FirebaseAuth auth = FirebaseAuth.instance;

  bool isLoading = false;
  bool _emailSent = false;
  String _errorMessage = "";
  String _successMessage = "";

  Future<void> _sendResetEmail() async {
    final studentId = studentIdController.text.trim();
    final email = emailController.text.trim();

    if (studentId.isEmpty) {
      _showError("Student ID required");
      return;
    }
    if (email.isEmpty) {
      _showError("Email required");
      return;
    }

    setState(() {
      isLoading = true;
      _errorMessage = "";
      _successMessage = "";
    });

    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-southeast1',
      ).httpsCallable('resetPasswordById');

      await callable.call({"id": studentId, "email": email});

      await auth.sendPasswordResetEmail(email: email);

      if (!mounted) return;
      setState(() {
        _emailSent = true;
        _successMessage = "Password reset email sent to $email";
      });

      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) context.go('/login');
      });
    } on FirebaseFunctionsException catch (e) {
      _showError(e.message ?? "Verification failed");
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? "Error sending reset email");
    } catch (e) {
      _showError("Error: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    setState(() {
      _errorMessage = msg;
      _successMessage = "";
    });
  }

  @override
  void dispose() {
    studentIdController.dispose();
    emailController.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: Stack(
        children: [
          // Soft glow, same as the login page
          Positioned(
            top: -120,
            left: -80,
            child: IgnorePointer(
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _accentColor.withOpacity(0.18),
                      _accentColor.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Stack(
              children: [
                Center(
                  // Hides the side scrollbar but keeps scrolling working
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      scrollbars: false,
                      overscroll: false,
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 64, 16, 24),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Container(
                          // Header zone + form zone fused into ONE rounded card
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.25),
                                blurRadius: 16,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildHeaderZone(),
                                _buildFormZone(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Back button (top-left)
                Positioned(
                  top: 8,
                  left: 12,
                  child: Material(
                    color: Colors.white.withOpacity(0.08),
                    shape: const CircleBorder(),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back,
                          color: _textColor, size: 22),
                      tooltip: "Back to login",
                      onPressed: () => context.go('/login'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Top zone: framed icon (like the profile avatar), title, tag chip
  Widget _buildHeaderZone() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 26),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_headerColorLight, _headerColor],
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _accentColor.withOpacity(0.9),
                  _accentColor.withOpacity(0.25),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: _accentColor.withOpacity(0.35),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(19),
              child: Container(
                color: _cardColor,
                child: const Icon(
                  Icons.lock_reset,
                  size: 42,
                  color: _accentColor,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            "Forgot Password?",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _textColor,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.25),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              "ACCOUNT RECOVERY",
              style: TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Bottom zone: section header, helper text, fields, button
  Widget _buildFormZone() {
    return Container(
      width: double.infinity,
      color: _cardColor,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: _accentColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.mail_outline,
                    size: 16, color: _accentColor),
              ),
              const SizedBox(width: 10),
              const Text(
                "Reset Password",
                style: TextStyle(
                  color: _textColor,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 1,
                  color: Colors.white.withOpacity(0.08),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            "Enter your Student ID and the email linked to your account. "
            "We'll send you a link to set a new password.",
            style: TextStyle(color: _mutedTextColor, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),

          // Error / success banner
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _errorMessage.isNotEmpty
                ? _buildBanner(
                    title: "Something went wrong",
                    message: _errorMessage,
                    color: _errorColor,
                    icon: Icons.error_outline,
                  )
                : _successMessage.isNotEmpty
                    ? _buildBanner(
                        title: "Email sent",
                        message: _successMessage,
                        color: _successColor,
                        icon: Icons.check_circle_outline,
                      )
                    : const SizedBox(width: double.infinity),
          ),

          // Student ID
          TextField(
            controller: studentIdController,
            style: const TextStyle(color: _textColor),
            cursorColor: _accentColor,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _emailFocus.requestFocus(),
            decoration: _fieldDecoration(
              hint: "Student ID",
              icon: Icons.badge_outlined,
            ),
          ),
          const SizedBox(height: 14),

          // Email
          TextField(
            controller: emailController,
            focusNode: _emailFocus,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(color: _textColor),
            cursorColor: _accentColor,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (!isLoading && !_emailSent) _sendResetEmail();
            },
            decoration: _fieldDecoration(
              hint: "Email",
              icon: Icons.alternate_email,
            ),
          ),
          const SizedBox(height: 22),

          // Send button
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: (isLoading || _emailSent) ? null : _sendResetEmail,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _accentColor.withOpacity(0.6),
                disabledForegroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: isLoading
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 10),
                        Text("Sending..."),
                      ],
                    )
                  : const Text("Send Reset Link"),
            ),
          ),
          const SizedBox(height: 6),

          // Back to login
          TextButton(
            onPressed: () => context.go('/login'),
            child: const Text(
              "Back to Login",
              style: TextStyle(
                color: _accentColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBanner({
    required String title,
    required String message,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        border: Border.all(color: color.withOpacity(0.35)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: const TextStyle(color: _mutedTextColor, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
  }) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: width),
        );

    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: _mutedTextColor, fontSize: 14),
      filled: true,
      fillColor: Colors.black.withOpacity(0.22),
      prefixIcon: Icon(icon, color: _accentColor.withOpacity(0.85), size: 20),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      enabledBorder: border(Colors.white.withOpacity(0.08)),
      focusedBorder: border(_accentColor, 1.5),
      border: border(Colors.white.withOpacity(0.08)),
    );
  }
}