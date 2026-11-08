import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:go_router/go_router.dart';

class ForgotPage extends StatefulWidget {
  const ForgotPage({super.key});

  @override
  State<ForgotPage> createState() => _ForgotPageState();
}

class _ForgotPageState extends State<ForgotPage> {
  // Match the FOTS LoginPage palette.
  static const Color _paper = Color(0xFFF7F8F6);
  static const Color _ink = Color(0xFF111217);
  static const Color _green = Color(0xFF087B4F);
  static const Color _greenHover = Color(0xFF066640);
  static const Color _artBg = Color(0xFF101215);
  static const Color _border = Color(0xFFD9DDDA);
  static const Color _muted = Color(0xFF666C6C);
  static const Color _footMuted = Color(0xFF828783);
  static const Color _errorText = Color(0xFFA42237);
  static const Color _successText = Color(0xFF087B4F);

  static const double _breakpoint = 790;

  final TextEditingController studentIdController = TextEditingController();
  final TextEditingController emailController = TextEditingController();

  final FocusNode _emailFocus = FocusNode();
  final FirebaseAuth auth = FirebaseAuth.instance;

  bool isLoading = false;
  bool _emailSent = false;
  int? _resetAttemptsRemaining;
  String? _attemptsForAccount;
  int? _lockoutRemainingSeconds;
  Timer? _lockoutTimer;

  String _errorMessage = '';
  String _successMessage = '';

  //  PASSWORD RESET LOGIC 

  Future<void> _sendResetEmail() async {
    final studentId = studentIdController.text.trim();
    final email = emailController.text.trim();

    if (studentId.isEmpty) {
      _showError('Please enter your Student ID.');
      return;
    }

    if (email.isEmpty) {
      _showError('Please enter your registered email address.');
      return;
    }

    setState(() {
      isLoading = true;
      _errorMessage = '';
      _successMessage = '';
    });

    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-southeast1',
      ).httpsCallable('resetPasswordById');

      final result = await callable.call({'id': studentId, 'email': email});

      final response = result.data;
      if (response is Map && response['remainingAttempts'] is num && mounted) {
        final remaining = (response['remainingAttempts'] as num).toInt();
        _setAttemptStatus(studentId, email, remaining);
        if (remaining == 0) _startLockoutCountdown(60 * 60);
      }

      await auth.sendPasswordResetEmail(email: email);

      if (!mounted) return;

      setState(() {
        _emailSent = true;
        _successMessage = 'A password reset link has been sent to $email.';
      });
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        final details = e.details;
        final remaining = details is Map ? details['attemptsRemaining'] : null;
        final retryAfter = details is Map ? details['retryAfterSeconds'] : null;

        if (remaining is num) {
          final attemptsLeft = remaining.toInt();
          _setAttemptStatus(studentId, email, attemptsLeft);
          if (attemptsLeft == 0) {
            _startLockoutCountdown(
              retryAfter is num && retryAfter > 0
                  ? retryAfter.toInt()
                  : 60 * 60,
            );
          }
        } else if (e.code == 'resource-exhausted') {
          _setAttemptStatus(studentId, email, 0);
          _startLockoutCountdown(
            retryAfter is num && retryAfter > 0
                ? retryAfter.toInt()
                : 60 * 60,
          );
        }
      }
      _showError(
        e.code == 'resource-exhausted'
            ? ''
            : 'Student ID or email is incorrect. Please check your details and try again.',
      );
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? 'Unable to send the password reset email.');
    } catch (_) {
      _showError('Something went wrong. Please try again later.');
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;

    setState(() {
      _errorMessage = message;
      _successMessage = '';
    });
  }

  void _setAttemptStatus(String studentId, String email, int remaining) {
    _attemptsForAccount = _attemptKey(studentId, email);
    setState(() {
      _resetAttemptsRemaining = remaining;
    });
  }

  String _attemptKey(String studentId, String email) =>
      '${studentId.trim().toLowerCase()}|${email.trim().toLowerCase()}';

  bool get _isLockedOut =>
      _resetAttemptsRemaining == 0 &&
      (_lockoutRemainingSeconds == null || _lockoutRemainingSeconds! > 0);

  void _clearAttemptStatusIfAccountChanged() {
    if (_attemptsForAccount == null ||
        _attemptsForAccount ==
            _attemptKey(studentIdController.text, emailController.text)) {
      return;
    }

    _lockoutTimer?.cancel();
    setState(() {
      _attemptsForAccount = null;
      _resetAttemptsRemaining = null;
      _lockoutRemainingSeconds = null;
    });
  }

  void _startLockoutCountdown(int seconds) {
    _lockoutTimer?.cancel();
    if (seconds <= 0) {
      setState(() => _lockoutRemainingSeconds = 0);
      return;
    }
    setState(() {
      _lockoutRemainingSeconds = seconds;
    });
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final remaining = (_lockoutRemainingSeconds ?? 0) - 1;
      setState(() {
        _lockoutRemainingSeconds = remaining > 0 ? remaining : 0;
      });
      if (remaining <= 0) timer.cancel();
    });
  }

  String _formatLockoutTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    studentIdController.dispose();
    emailController.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  //  PAGE LAYOUT 

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

  //  BRAND / ART PANEL 

  Widget _buildArtPanel({required bool wide}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final titleSize = wide
            ? (MediaQuery.of(context).size.width * 0.08).clamp(56.0, 120.0)
            : 48.0;

        final glowSize = wide ? 500.0 : 300.0;

        final content = Column(
          mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBrandRow(),
            if (!wide) const SizedBox(height: 30),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GET BACK\nINTO\nFOCUS.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: titleSize,
                    fontWeight: FontWeight.w900,
                    height: 0.91,
                    letterSpacing: -0.075 * titleSize,
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'YOUR ACCOUNT / YOUR ACCESS',
                  style: TextStyle(
                    color: Color(0xFFB9C3BD),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.8,
                  ),
                ),
              ],
            ),
            if (wide)
              const Text(
                'FOTS STUDENT PORTAL  /  ACCOUNT RECOVERY',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  letterSpacing: 1.5,
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
                  left: wide ? w * 0.06 : w * 0.38,
                  top: wide ? MediaQuery.of(context).size.height * 0.16 : -100,
                  child: IgnorePointer(
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
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
                      : const EdgeInsets.fromLTRB(22, 19, 22, 22),
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
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.school_outlined, color: _green, size: 25),
          ),
        ),
        const SizedBox(width: 10),
        const Text(
          'FOTS',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: -1,
          ),
        ),
        const Spacer(),
        const Text(
          'STUDENT / 2026',
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

  //  FORM PANEL 

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
        padding: const EdgeInsets.fromLTRB(22, 30, 22, 42),
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
    final headingSize = wide
        ? (MediaQuery.of(context).size.width * 0.04).clamp(32.0, 46.0)
        : 37.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Back navigation
        TextButton.icon(
          onPressed: () => context.go('/login'),
          style: TextButton.styleFrom(
            foregroundColor: _muted,
            padding: EdgeInsets.zero,
          ),
          icon: const Icon(Icons.arrow_back, size: 17),
          label: const Text(
            'Back to login',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),

        const SizedBox(height: 24),

        const Text(
          '02 / ACCOUNT RECOVERY',
          style: TextStyle(
            color: _green,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
          ),
        ),

        const SizedBox(height: 14),

        Text(
          _emailSent ? 'Check your email.' : 'Forgot password?',
          style: TextStyle(
            color: _ink,
            fontSize: headingSize,
            fontWeight: FontWeight.w800,
            height: 1.06,
            letterSpacing: -0.052 * headingSize,
          ),
        ),

        const SizedBox(height: 12),

        Text(
          _emailSent
              ? 'Check your inbox for the reset link. Follow the instructions in the email to choose a new password.'
              : 'No worries. Verify your student account and we’ll send you a secure link to reset your password.',
          style: const TextStyle(color: _muted, fontSize: 14, height: 1.7),
        ),

        const SizedBox(height: 12),
        _buildAttemptNotice(),

        const SizedBox(height: 28),

        // Feedback message
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _errorMessage.isNotEmpty
              ? _buildMessage(message: _errorMessage, isSuccess: false)
              : _successMessage.isNotEmpty
              ? _buildMessage(message: _successMessage, isSuccess: true)
              : const SizedBox.shrink(),
        ),

        // Student ID
        _fieldLabel('Student ID'),

        TextField(
          controller: studentIdController,
          onChanged: (_) => _clearAttemptStatusIfAccountChanged(),
          enabled: !_emailSent && !isLoading,
          style: const TextStyle(color: _ink, fontSize: 16),
          cursorColor: _green,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.username],
          onSubmitted: (_) => _emailFocus.requestFocus(),
          decoration: _fieldDecoration(
            hint: 'Enter your Student ID',
            icon: Icons.badge_outlined,
          ),
        ),

        const SizedBox(height: 19),

        // Registered email
        _fieldLabel('Registered email'),

        TextField(
          controller: emailController,
          onChanged: (_) => _clearAttemptStatusIfAccountChanged(),
          focusNode: _emailFocus,
          enabled: !_emailSent && !isLoading,
          keyboardType: TextInputType.emailAddress,
          textCapitalization: TextCapitalization.none,
          autofillHints: const [AutofillHints.email],
          style: const TextStyle(color: _ink, fontSize: 16),
          cursorColor: _green,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            if (!isLoading && !_emailSent) {
              _sendResetEmail();
            }
          },
          decoration: _fieldDecoration(
            hint: 'Enter your registered email',
            icon: Icons.alternate_email,
          ),
        ),

        const SizedBox(height: 25),

        // Submit button
        SizedBox(
          width: double.infinity,
          height: 57,
          child: ElevatedButton(
            onPressed: (isLoading || _emailSent || _isLockedOut)
                ? null
                : _sendResetEmail,
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
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(width: 10),
                      Text('Sending reset link...'),
                    ],
                  )
                : Text(
                    _emailSent ? 'Reset link sent' : 'Send password reset link',
                  ),
          ),
        ),

        const SizedBox(height: 24),

        // Security note
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF3ED),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFD4E7D9)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.verified_user_outlined, color: _green, size: 19),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'For your security, use the email address linked to your student account.',
                  style: TextStyle(
                    color: Color(0xFF385447),
                    fontSize: 12,
                    height: 1.6,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 28),

        const Text(
          'FOTS Student Edition · Secure account recovery',
          style: TextStyle(color: _footMuted, fontSize: 11, height: 1.6),
        ),
      ],
    );
  }

  //  FORM HELPERS 

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

  Widget _buildMessage({required String message, required bool isSuccess}) {
    final color = isSuccess ? _successText : _errorText;
    final background = isSuccess
        ? const Color(0xFFEAF3ED)
        : const Color(0xFFFFEEF0);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isSuccess ? Icons.check_circle_outline : Icons.error_outline,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: 12,
                height: 1.6,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttemptNotice() {
    final remaining = _resetAttemptsRemaining;
    if (remaining == null || remaining > 2) {
      return const SizedBox.shrink();
    }

    final lockoutComplete = remaining == 0 && _lockoutRemainingSeconds == 0;
    final locked = remaining == 0 && !lockoutComplete;
    final message = locked
        ? _lockoutRemainingSeconds == null
              ? 'Attempt limit reached. Password resets are locked for 1 hour.'
              : 'Attempt limit reached. Try again in ${_formatLockoutTime(_lockoutRemainingSeconds!)}.'
        : lockoutComplete
        ? 'The lockout period has ended. You can try again now.'
        : remaining == 1
        ? '1 of 5 attempts remaining. Password resets lock for 1 hour after the next valid request.'
        : '${5 - remaining} of 5 attempts used. $remaining attempts remain before a 1-hour lockout.';
    final color = locked
        ? _errorText
        : lockoutComplete
        ? _successText
        : const Color(0xFF805B16);
    final background = locked
        ? const Color(0xFFFFEEF0)
        : lockoutComplete
        ? const Color(0xFFEAF3ED)
        : const Color(0xFFFFF6E5);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            locked
                ? Icons.error_outline
                : lockoutComplete
                ? Icons.check_circle_outline
                : Icons.warning_amber_rounded,
            color: color,
            size: 19,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: locked
                    ? _errorText
                    : lockoutComplete
                    ? _successText
                    : const Color(0xFF654A17),
                fontSize: 12,
                height: 1.5,
                fontWeight: FontWeight.w500,
              ),
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
    OutlineInputBorder border(Color color, [double width = 1]) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF9AA09B), fontSize: 14),
      prefixIcon: Icon(icon, color: _footMuted, size: 20),
      filled: true,
      fillColor: Colors.white,
      constraints: const BoxConstraints(minHeight: 56),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 15),
      enabledBorder: border(_border),
      focusedBorder: border(_green, 2),
      disabledBorder: border(_border),
      border: border(_border),
    );
  }
}
