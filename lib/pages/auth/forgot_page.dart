import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

class ForgotPage extends StatefulWidget {
  const ForgotPage({super.key});

  @override
  _ForgotPageState createState() => _ForgotPageState();
}

class _ForgotPageState extends State<ForgotPage> {
  final TextEditingController studentIdController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final FirebaseFirestore db = FirebaseFirestore.instance;
  final FirebaseAuth auth = FirebaseAuth.instance;

  bool isLoading = false;

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

    setState(() => isLoading = true);

    try {
      // Verify Student ID exists first
      final query = await db
          .collection("users")
          .where("studentId", isEqualTo: studentId)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        _showError("No account found with Student ID $studentId");
        setState(() => isLoading = false);
        return;
      }

      final data = query.docs.first.data();
      final firestoreEmail = data["email"];

      //  Check if entered email matches Firestore email
      if (firestoreEmail != email) {
        _showError("Email does not match this Student ID");
        setState(() => isLoading = false);
        return;
      }

      //  If matched, send reset email
      await auth.sendPasswordResetEmail(email: email);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Password reset email sent to $email"),
             backgroundColor: Colors.green,
          ),
        );
        Future.delayed(const Duration(seconds: 1), () {
          // If using go_router
          context.go('/login');

          // OR if using Navigator
          // Navigator.pop(context);
        });
      }
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? "Error sending reset email");
    } catch (e) {
      _showError("Error: $e");
    }

    setState(() => isLoading = false);
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF0D1014),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              const Text(
                "Forgot Password?",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFE6F0F8),
                ),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: 340,
                child: TextField(
                  controller: studentIdController,
                  style: TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: "Enter Student ID",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.white70),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: 340,
                child: TextField(
                  controller: emailController,
                  style: TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: "Enter Email",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.white70),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              isLoading
                  ? const CircularProgressIndicator()
                  : SizedBox(
                      width: 320,
                      child: ElevatedButton(
                        onPressed: _sendResetEmail,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          "Send Reset Link",
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
