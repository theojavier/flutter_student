// profile_menu.dart
//
// Self-contained profile menu widgets for the app header:
//   - ProfileMenuTrigger: the pill ("cylinder") button with the avatar and
//     drop-down chevron that lives in the AppBar actions.
//   - ProfileMenuPanel: the navy-themed header + white menu list that drops
//     down when the trigger is tapped.
//
// Mostly presentational — it takes the user's display data and three
// callbacks, so it doesn't need to know about routing, etc. The one
// exception is "Change Password": if you don't pass onChangePassword,
// this file handles it itself with a pop-up (styled to match the same
// dark navy theme as LoginPage/ForgotPage) that sends Firebase's
// built-in password reset email to whoever is currently signed in
// (works the same for students, teachers, and admins, since all three
// sign in via Firebase email/password). Pass your own onChangePassword
// if you want different behavior instead.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

class ProfileMenuTrigger extends StatefulWidget {
  final String? avatarUrl;
  final String name;
  final String? idNumber;
  final VoidCallback onViewProfile;
  final VoidCallback? onChangePassword;
  final VoidCallback onLogout;

  const ProfileMenuTrigger({
    super.key,
    required this.avatarUrl,
    required this.name,
    required this.idNumber,
    required this.onViewProfile,
    this.onChangePassword,
    required this.onLogout,
  });

  @override
  State<ProfileMenuTrigger> createState() => _ProfileMenuTriggerState();
}

class _ProfileMenuTriggerState extends State<ProfileMenuTrigger> {
  bool _isOpen = false;

  Future<void> _openMenu() async {
    setState(() => _isOpen = true);

    await showDialog(
      context: context,
      barrierColor: Colors.black12,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.only(top: 64, right: 20),
        alignment: Alignment.topRight,
        backgroundColor: Colors.transparent,
        child: PointerInterceptor(
          child: ProfileMenuPanel(
            avatarUrl: widget.avatarUrl,
            name: widget.name,
            idNumber: widget.idNumber,
            onViewProfile: () {
              Navigator.of(ctx).pop();
              widget.onViewProfile();
            },
            onChangePassword: () {
              Navigator.of(ctx).pop();
              // Use the trigger's own context (still mounted after the
              // menu dialog closes) rather than the menu's ctx.
              if (widget.onChangePassword != null) {
                widget.onChangePassword!();
              } else {
                confirmChangePassword(context);
              }
            },
            onLogout: () {
              Navigator.of(ctx).pop();
              widget.onLogout();
            },
          ),
        ),
      ),
    );

    if (mounted) setState(() => _isOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _openMenu,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          // The light "cylinder" pill sitting on the dark navy app bar.
          color: Colors.white.withOpacity(0.18),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                border: Border.fromBorderSide(
                  BorderSide(color: Color(0xFF2E86C1), width: 2),
                ),
              ),
              child: CircleAvatar(
                radius: 14,
                backgroundColor: Colors.white24,
                backgroundImage:
                    widget.avatarUrl != null && widget.avatarUrl!.isNotEmpty
                        ? NetworkImage(widget.avatarUrl!)
                        : null,
                child: (widget.avatarUrl == null || widget.avatarUrl!.isEmpty)
                    ? const Icon(Icons.person, size: 16, color: Colors.white)
                    : null,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              _isOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              color: Colors.white,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

class ProfileMenuPanel extends StatelessWidget {
  final String? avatarUrl;
  final String name;
  final String? idNumber;
  final VoidCallback onViewProfile;
  final VoidCallback onChangePassword;
  final VoidCallback onLogout;

  const ProfileMenuPanel({
    super.key,
    required this.avatarUrl,
    required this.name,
    required this.idNumber,
    required this.onViewProfile,
    required this.onChangePassword,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final panelWidth =
        (MediaQuery.of(context).size.width * 0.5).clamp(220.0, 260.0);

    return Material(
      color: Colors.transparent,
      child: Container(
        width: panelWidth,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 20,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header gradient — matches the app's navy theme (same family
            // as topColor / the desktop sidebar in responsive_scaffold.dart).
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0B2036), Color(0xFF1E5B8C)],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: Colors.white24,
                        backgroundImage:
                            avatarUrl != null && avatarUrl!.isNotEmpty
                                ? NetworkImage(avatarUrl!)
                                : null,
                        child: (avatarUrl == null || avatarUrl!.isEmpty)
                            ? const Icon(Icons.person,
                                size: 22, color: Colors.white)
                            : null,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2E86C1),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    name.toUpperCase(),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      height: 1.25,
                    ),
                  ),
                  if (idNumber != null && idNumber!.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.badge_outlined,
                            size: 13, color: Colors.white70),
                        const SizedBox(width: 4),
                        Text(
                          idNumber!,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // Menu items.
            _ProfileMenuTile(
              icon: Icons.person_outline,
              iconColor: const Color(0xFF0F2B45),
              iconBg: const Color(0xFFE7ECF2),
              label: 'View Profile',
              onTap: onViewProfile,
            ),
            const Divider(height: 1, indent: 18, endIndent: 18),
            _ProfileMenuTile(
              icon: Icons.lock_outline,
              iconColor: const Color(0xFF3B6FE0),
              iconBg: const Color(0xFFE4EBFC),
              label: 'Change Password',
              onTap: onChangePassword,
            ),
            const Divider(height: 1, indent: 18, endIndent: 18),
            _ProfileMenuTile(
              icon: Icons.logout,
              iconColor: const Color(0xFFE0533B),
              iconBg: const Color(0xFFFBE7E3),
              label: 'Logout',
              labelColor: const Color(0xFFE0533B),
              onTap: onLogout,
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

class _ProfileMenuTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final Color? labelColor;
  final VoidCallback onTap;

  const _ProfileMenuTile({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    required this.onTap,
    this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
              child: Icon(icon, size: 15, color: iconColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: labelColor ?? const Color(0xFF16324A),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Built-in "Change Password" fallback. Same behavior as before (send a
// Firebase password reset email to whoever is currently signed in) —
// only the pop-up's look has changed, now matching the dark navy /
// accent-blue theme used across LoginPage and ForgotPage.
// ---------------------------------------------------------------------
Future<void> confirmChangePassword(BuildContext context) {
  return showDialog(
    context: context,
    builder: (_) => PointerInterceptor(
      child: const _ChangePasswordDialog(),
    ),
  );
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  // Same shared palette as LoginPage / ForgotPage.
  static const Color _headerColor = Color(0xFF0F2B45);
  static const Color _headerColorLight = Color(0xFF17456F);
  static const Color _cardColor = Color(0xFF0F3B61);
  static const Color _textColor = Color(0xFFE6F0F8);
  static const Color _mutedTextColor = Color(0xFF9FB0C3);
  static const Color _accentColor = Color(0xFF3D8BFF);
  static const Color _errorColor = Color(0xFFF87171);
  static const Color _successColor = Color(0xFF4ADE80);

  bool _isSending = false;
  bool _sent = false;
  String? _errorMessage;

  String? get _email => FirebaseAuth.instance.currentUser?.email;

  Future<void> _sendResetEmail() async {
    final email = _email;
    if (email == null) {
      setState(() {
        _errorMessage = "No signed-in user found. Please log in again.";
      });
      return;
    }

    setState(() {
      _isSending = true;
      _errorMessage = null;
    });

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) setState(() => _sent = true);
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _errorMessage = _messageFor(e));
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = "Something went wrong. Please try again.");
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  String _messageFor(FirebaseAuthException e) {
    switch (e.code) {
      case 'too-many-requests':
        return 'Too many attempts. Please wait a bit and try again.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      case 'user-not-found':
        return 'No account found for this email.';
      default:
        return e.message ?? 'Could not send reset email (${e.code}).';
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = _email;

    return PointerInterceptor(
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              // Header zone — same gradient family as Login/Forgot.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
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
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _accentColor.withOpacity(0.15),
                        border: Border.all(color: _accentColor.withOpacity(0.4)),
                      ),
                      child: const Icon(Icons.lock_reset,
                          color: _accentColor, size: 28),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      "Change Password",
                      style: TextStyle(
                        color: _textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              // Body zone.
              Container(
                width: double.infinity,
                color: _cardColor,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_errorMessage != null)
                      _buildBanner(
                        title: "Something went wrong",
                        message: _errorMessage!,
                        color: _errorColor,
                        icon: Icons.error_outline,
                      )
                    else if (_sent)
                      _buildBanner(
                        title: "Email sent",
                        message:
                            "Check ${email ?? 'your inbox'} for a link to reset your password.",
                        color: _successColor,
                        icon: Icons.check_circle_outline,
                      )
                    else ...[
                      const Text(
                        "We'll send a password reset link to:",
                        style: TextStyle(
                          color: _mutedTextColor,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 14),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.22),
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: Colors.white.withOpacity(0.08)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.alternate_email,
                                color: _accentColor, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                email ?? "No email on file",
                                style: const TextStyle(
                                    color: _textColor, fontSize: 14),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    if (_sent)
                      SizedBox(
                        height: 46,
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                                color: Colors.white.withOpacity(0.2)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: const Text("Done",
                              style: TextStyle(color: _textColor)),
                        ),
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: _isSending
                                  ? null
                                  : () => Navigator.of(context).pop(),
                              child: const Text("Cancel",
                                  style: TextStyle(color: _mutedTextColor)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: SizedBox(
                              height: 46,
                              child: ElevatedButton(
                                onPressed: (_isSending || email == null)
                                    ? null
                                    : _sendResetEmail,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _accentColor,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor:
                                      _accentColor.withOpacity(0.6),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14)),
                                ),
                                child: _isSending
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text("Send Reset Link"),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                ),
              ],
            ),
          ),
        ),
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
      margin: const EdgeInsets.only(bottom: 4),
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
                  style:
                      const TextStyle(color: _mutedTextColor, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}