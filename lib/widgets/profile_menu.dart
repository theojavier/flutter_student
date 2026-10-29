// profile_menu.dart
//
// Self-contained profile menu widgets for the app header:
//   - ProfileMenuTrigger: the pill ("cylinder") button with the avatar and
//     drop-down chevron that lives in the AppBar actions.
//   - ProfileMenuPanel: the ink-and-green dropdown card.
//     down when the trigger is tapped.
//
// Mostly presentational — it takes the user's display data and three
// callbacks, so it doesn't need to know about routing, etc. The one
// exception is "Change Password": if you don't pass onChangePassword,
// this file handles it itself with a pop-up styled to match the student
// workspace that sends Firebase's
// built-in password reset email to whoever is currently signed in
// (works the same for students, teachers, and admins, since all three
// sign in via Firebase email/password). Pass your own onChangePassword
// if you want different behavior instead.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

const Color _menuInk = Color(0xFF121217);
const Color _menuInkSoft = Color(0xFF1D1D23);
const Color _menuInkLine = Color(0xFF37373D);
const Color _menuMuted = Color(0xFFA1A1AA);
const Color _menuGreen = Color(0xFF179C68);
const Color _menuGreenSoft = Color(0xFF17402A);

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

    final size = MediaQuery.of(context).size;
    final topInset = MediaQuery.of(context).padding.top;
    final wide = size.width >= 900;
    await showDialog(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) => Dialog(
        insetPadding: EdgeInsets.only(
          top: wide ? 68 : topInset + 58,
          right: wide ? 28 : 12,
          left: 12,
        ),
        alignment: Alignment.topRight,
        backgroundColor: Colors.transparent,
        elevation: 0,
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
    final compact = MediaQuery.of(context).size.width < 680;

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: BorderSide(color: _isOpen ? _menuGreen : const Color(0xFFDFE0DE)),
      ),
      child: InkWell(
        onTap: _openMenu,
        borderRadius: BorderRadius.circular(9),
        child: Padding(
          padding: EdgeInsets.fromLTRB(5, 4, compact ? 6 : 10, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: _menuGreen,
                backgroundImage:
                    widget.avatarUrl != null && widget.avatarUrl!.isNotEmpty
                    ? NetworkImage(widget.avatarUrl!)
                    : null,
                child: widget.avatarUrl == null || widget.avatarUrl!.isEmpty
                    ? const Icon(
                        Icons.person_outline,
                        size: 18,
                        color: Colors.white,
                      )
                    : null,
              ),
              if (!compact) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _menuInk,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.idNumber?.isNotEmpty == true
                            ? widget.idNumber!
                            : 'Student',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF75777D),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(width: 6),
              Icon(
                _isOpen
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: const Color(0xFF75777D),
                size: 18,
              ),
            ],
          ),
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
    final panelWidth = (MediaQuery.of(context).size.width - 24).clamp(
      220.0,
      300.0,
    );

    return Material(
      color: Colors.transparent,
      child: Container(
        width: panelWidth,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: _menuInk,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _menuInkLine),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: _menuInkSoft,
                border: Border(bottom: BorderSide(color: _menuInkLine)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: _menuGreen,
                    backgroundImage: avatarUrl != null && avatarUrl!.isNotEmpty
                        ? NetworkImage(avatarUrl!)
                        : null,
                    child: avatarUrl == null || avatarUrl!.isEmpty
                        ? const Icon(Icons.person_outline, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          idNumber?.isNotEmpty == true ? idNumber! : 'Student',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _menuMuted,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Menu items.
            _ProfileMenuTile(
              icon: Icons.person_outline,
              iconColor: const Color(0xFF70DFA9),
              iconBg: _menuGreenSoft,
              label: 'View Profile',
              onTap: onViewProfile,
            ),
            const Divider(
              height: 1,
              indent: 18,
              endIndent: 18,
              color: _menuInkLine,
            ),
            _ProfileMenuTile(
              icon: Icons.lock_outline,
              iconColor: const Color(0xFF70DFA9),
              iconBg: _menuGreenSoft,
              label: 'Change Password',
              onTap: onChangePassword,
            ),
            const Divider(
              height: 1,
              indent: 18,
              endIndent: 18,
              color: _menuInkLine,
            ),
            _ProfileMenuTile(
              icon: Icons.logout,
              iconColor: const Color(0xFFFF6B7E),
              iconBg: const Color(0xFF40202A),
              label: 'Logout',
              labelColor: const Color(0xFFFF6B7E),
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
                  color: labelColor ?? const Color(0xFFE7F8EF),
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
    builder: (_) => PointerInterceptor(child: const _ChangePasswordDialog()),
  );
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  // Same shared palette as LoginPage / ForgotPage.
  static const Color _headerColor = Color(0xFF091C12);
  static const Color _headerColorLight = Color(0xFF103320);
  static const Color _cardColor = Color(0xFF143523);
  static const Color _textColor = Color(0xFFF1FBF6);
  static const Color _mutedTextColor = Color(0xFF83C2A0);
  static const Color _accentColor = Color(0xFF179C68);
  static const Color _errorColor = Color(0xFFF87171);
  static const Color _successColor = Color(0xFF4BE2AC);

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
        setState(
          () => _errorMessage = "Something went wrong. Please try again.",
        );
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
                          border: Border.all(
                            color: _accentColor.withOpacity(0.4),
                          ),
                        ),
                        child: const Icon(
                          Icons.lock_reset,
                          color: _accentColor,
                          size: 28,
                        ),
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
                            vertical: 12,
                            horizontal: 14,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.22),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.08),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.alternate_email,
                                color: _accentColor,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  email ?? "No email on file",
                                  style: const TextStyle(
                                    color: _textColor,
                                    fontSize: 14,
                                  ),
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
                                color: Colors.white.withOpacity(0.2),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text(
                              "Done",
                              style: TextStyle(color: _textColor),
                            ),
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
                                child: const Text(
                                  "Cancel",
                                  style: TextStyle(color: _mutedTextColor),
                                ),
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
                                    disabledBackgroundColor: _accentColor
                                        .withOpacity(0.6),
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
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
                  style: const TextStyle(
                    color: _mutedTextColor,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
