import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../helpers/SecureStorageHelper.dart';

final secureStorage = FlutterSecureStorage();

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // Palette from the FOTS student login design.
  static const Color _paper = Color(0xFFF7F8F6);
  static const Color _ink = Color(0xFF111217);
  static const Color _green = Color(0xFF087B4F);
  static const Color _greenHover = Color(0xFF066640);
  static const Color _artBg = Color(0xFF101215);
  static const Color _border = Color(0xFFD9DDDA);
  static const Color _muted = Color(0xFF666C6C);
  static const Color _footMuted = Color(0xFF828783);
  static const Color _errorText = Color(0xFFA42237);

  static const double _breakpoint = 790;

  final TextEditingController studentIdController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final FocusNode _passwordFocus = FocusNode();
  final FirebaseAuth auth = FirebaseAuth.instance;

  bool isLoading = false;
  bool _isPasswordVisible = false;
  String _loginError = "";

  // ---------------- LOGIC (unchanged) ----------------

  Future<void> _login() async {
    final studentId = studentIdController.text.trim();
    final password = passwordController.text.trim();

    if (studentId.isEmpty || password.isEmpty) {
      setState(
        () => _loginError = "Please enter your Student ID and password.",
      );
      return;
    }

    setState(() {
      isLoading = true;
      _loginError = "";
    });

    try {
      final functions = FirebaseFunctions.instanceFor(
        region: 'asia-southeast1',
      );

      final result = await functions.httpsCallable('loginWithStudentId').call({
        'studentId': studentId,
      });

      final data = result.data;
      final email = data['email'];
      final role = data['role'];
      final program = data['program'];
      final yearBlock = data['yearBlock'];

      final userCredential = await auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (userCredential.user == null) {
        _showError("Login failed: no user returned");
        return;
      }

      // Proceed only if student role
      if (role.toString().toLowerCase() == "student") {
        await SecureStorageHelper.write("userId", userCredential.user!.uid);
        await SecureStorageHelper.write("studentId", studentId);

        if (program != null) {
          await SecureStorageHelper.write("program", program);
        }
        if (yearBlock != null) {
          await SecureStorageHelper.write("yearBlock", yearBlock);
        }

        if (mounted) context.go('/home');
      } else {
        _showError("Access denied (not a student)");
      }
    } on FirebaseFunctionsException catch (e) {
      _showError(e.message ?? "Invalid Student ID or password");
    } on FirebaseAuthException {
      _showError("Invalid Student ID or password");
    } catch (e) {
      _showError("Login failed: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _loginError = message);
  }

  @override
  void dispose() {
    studentIdController.dispose();
    passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _paper,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth > _breakpoint;

          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 11, child: _buildArtPanel(wide: true)),
                Expanded(
                  flex: 10,
                  child: _buildFormPanel(wide: true, constraints: constraints),
                ),
              ],
            );
          }

          // Narrow / mobile: art on top, form below, whole page scrolls
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildArtPanel(wide: false),
                _buildFormPanel(wide: false, constraints: constraints),
              ],
            ),
          );
        },
      ),
    );
  }

  // ----- Left / top dark art panel -----
  Widget _buildArtPanel({required bool wide}) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final titleSize = wide
            ? (MediaQuery.of(context).size.width * 0.08).clamp(56.0, 120.0)
            : 56.0;

        final glowSize = wide ? 500.0 : 330.0;
        final glowLeft = wide ? w * 0.06 : w * 0.45;
        final glowTop = wide
            ? 0.16 * MediaQuery.of(context).size.height
            : -130.0;

        final content = Column(
          mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBrandRow(),
            if (!wide) const SizedBox(height: 29),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                "STAY\nIN\nFOCUS.",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: titleSize,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.085 * titleSize,
                  height: 0.91,
                ),
              ),
            ),
            if (wide)
              const Text(
                "FACE ON THE SCREEN / STUDENT WORKSPACE",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  letterSpacing: 1.8,
                ),
              ),
          ],
        );

        return Container(
          color: _artBg,
          constraints: BoxConstraints(minHeight: wide ? 0 : 190),
          child: ClipRect(
            child: Stack(
              children: [
                Positioned(
                  left: glowLeft,
                  top: glowTop,
                  child: IgnorePointer(
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Opacity(
                        opacity: 0.78,
                        child: Transform.rotate(
                          angle: -35 * math.pi / 180,
                          child: Container(
                            width: glowSize,
                            height: glowSize,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  Color(0xFF2CD281),
                                  Color(0xFF087B4F),
                                  Color(0xFF064A33),
                                  Color(0x00064A33),
                                ],
                                stops: [0.0, 0.43, 0.60, 0.73],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: wide
                      ? const EdgeInsets.all(30)
                      : const EdgeInsets.fromLTRB(22, 19, 22, 19),
                  child: content,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBrandRow() {
    return Row(
      children: [
        Container(
          width: 39,
          height: 39,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Image.asset(
            'assets/image/student_font-removebg-preview.png',
            width: 32,
            height: 32,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(width: 10),
        const Text(
          "FOTS",
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: -1,
          ),
        ),
        const Spacer(),
        const Text(
          "STUDENT / 2026",
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w500,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  // ----- Right / bottom form panel -----
  Widget _buildFormPanel({
    required bool wide,
    required BoxConstraints constraints,
  }) {
    final form = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: wide ? 440 : double.infinity),
      child: _buildForm(wide: wide),
    );

    if (!wide) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(22, 30, 22, 48),
        child: form,
      );
    }

    return SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: constraints.maxWidth * 0.08,
              vertical: 36,
            ),
            child: form,
          ),
        ),
      ),
    );
  }

  Widget _buildForm({required bool wide}) {
    final h1Size = wide
        ? (MediaQuery.of(context).size.width * 0.04).clamp(32.0, 49.0)
        : 37.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          "01 / STUDENT ACCESS",
          style: TextStyle(
            color: _green,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          "Welcome back.",
          style: TextStyle(
            color: _ink,
            fontSize: h1Size,
            fontWeight: FontWeight.w800,
            height: 1.06,
            letterSpacing: -0.052 * h1Size,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          "Sign in to access your approved exams, desktop eye calibration, and mobile face monitoring.",
          style: TextStyle(color: _muted, fontSize: 14, height: 1.7),
        ),
        const SizedBox(height: 28),

        // Student ID
        _fieldLabel("Student ID"),
        TextField(
          controller: studentIdController,
          style: const TextStyle(color: _ink, fontSize: 16),
          cursorColor: _green,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.username],
          onSubmitted: (_) => _passwordFocus.requestFocus(),
          decoration: _fieldDecoration(hint: "Enter your Student ID"),
        ),
        const SizedBox(height: 17),

        // Password
        _fieldLabel("Password"),
        TextField(
          controller: passwordController,
          focusNode: _passwordFocus,
          obscureText: !_isPasswordVisible,
          style: const TextStyle(color: _ink, fontSize: 16),
          cursorColor: _green,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.password],
          onSubmitted: (_) {
            if (!isLoading) _login();
          },
          decoration: _fieldDecoration(
            hint: "Enter your password",
            suffix: IconButton(
              icon: Icon(
                _isPasswordVisible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: _footMuted,
                size: 20,
              ),
              onPressed: () =>
                  setState(() => _isPasswordVisible = !_isPasswordVisible),
            ),
          ),
        ),
        const SizedBox(height: 25),

        // Sign in button
        SizedBox(
          width: double.infinity,
          height: 57,
          child: ElevatedButton(
            onPressed: isLoading ? null : _login,
            style: ButtonStyle(
              elevation: const WidgetStatePropertyAll(0),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              foregroundColor: const WidgetStatePropertyAll(Colors.white),
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.disabled)) {
                  return _green.withValues(alpha: 0.6);
                }
                if (states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.pressed)) {
                  return _greenHover;
                }
                return _green;
              }),
              textStyle: const WidgetStatePropertyAll(
                TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
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
                      Text(
                        "Signing in...",
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  )
                : const Text("Sign in to Student Portal"),
          ),
        ),

        // Error text (same spot as the HTML's .error div)
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 20),
            margin: const EdgeInsets.only(top: 12),
            child: _loginError.isEmpty
                ? const SizedBox.shrink()
                : Semantics(
                    liveRegion: true,
                    child: Text(
                      _loginError,
                      style: const TextStyle(color: _errorText, fontSize: 12),
                    ),
                  ),
          ),
        ),

        // Forgot password
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: () => context.go('/forgot'),
            child: const Text(
              "Forgot Password?",
              style: TextStyle(
                color: _green,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),

        const SizedBox(height: 20),
        const Text(
          "FOTS Student Edition · Designed for web and future Flutter WebView use.",
          style: TextStyle(color: _footMuted, fontSize: 11, height: 1.6),
        ),
      ],
    );
  }

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: _ink,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration({required String hint, Widget? suffix}) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: color, width: width),
        );

    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF9AA09B), fontSize: 16),
      filled: true,
      fillColor: Colors.white,
      suffixIcon: suffix,
      constraints: const BoxConstraints(minHeight: 56),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 15),
      enabledBorder: border(_border),
      focusedBorder: border(_green, 2),
      border: border(_border),
    );
  }
}
