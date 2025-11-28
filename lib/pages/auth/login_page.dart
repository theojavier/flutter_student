import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController studentIdController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final FirebaseFirestore db = FirebaseFirestore.instance;
  final FirebaseAuth auth = FirebaseAuth.instance;
  bool isFormValid = false;

  bool isLoading = false;
  bool _isPasswordVisible = false;
  StreamSubscription? _examListener;
  void _updateButtonState() {
    setState(() {
      isFormValid =
          studentIdController.text.isNotEmpty &&
          passwordController.text.isNotEmpty;
    });
  }

  @override
  void initState() {
    super.initState();
    studentIdController.addListener(_updateButtonState);
    passwordController.addListener(_updateButtonState);
  }

  Future<void> _login() async {
    final studentId = studentIdController.text.trim();
    final password = passwordController.text.trim();

    if (studentId.isEmpty) return _showError("Student ID required");
    if (password.isEmpty) return _showError("Password required");

    setState(() => isLoading = true);

    try {
      // Get Firestore user profile by Student ID
      final query = await db
          .collection("users")
          .where("studentId", isEqualTo: studentId)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        _showError("Student ID not found");
        setState(() => isLoading = false);
        return;
      }

      final doc = query.docs.first;
      final data = doc.data();

      final email = data["email"];
      final uid = data["UID"];
      final role = data["role"];

      if (email == null || uid == null) {
        _showError("Account setup error. Please contact admin.");
        setState(() => isLoading = false);
        return;
      }

      // Authenticate with FirebaseAuth
      final userCredential = await auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // UID consistency check
      if (userCredential.user == null || userCredential.user!.uid != uid) {
        _showError("Account mismatch. Please contact admin.");
        await auth.signOut();
        setState(() => isLoading = false);
        return;
      }

      // Proceed only if student role
      if (role.toString().toLowerCase() == "student") {
        await db.collection("users").doc(doc.id).update({
          "lastLogin": FieldValue.serverTimestamp(),
        });
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString("userId", doc.id);
        await prefs.setString("studentId", data["studentId"]);

        if (data.containsKey("program")) {
          await prefs.setString("program", data["program"]);
        }
        if (data.containsKey("yearBlock")) {
          await prefs.setString("yearBlock", data["yearBlock"]);
        }

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Welcome Student!")));

        // Start notifications listener
        final program = data["program"];
        final yearBlock = data["yearBlock"];
        if (program != null && yearBlock != null) {
          startExamListener(doc.id, program, yearBlock);
        }

        if (mounted) context.go('/home');
      } else {
        _showError("Access denied (not a student)");
      }
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? "Invalid Student ID or Password");
    } catch (e) {
      _showError("Login failed: $e");
    }

    setState(() => isLoading = false);
  }

  // Real-time exam notifications listener
  void startExamListener(String userId, String program, String yearBlock) {
    _examListener = db
        .collection('exams')
        .where('program', isEqualTo: program)
        .where('yearBlock', isEqualTo: yearBlock)
        .snapshots()
        .listen((snapshot) async {
          final userRef = db.collection('users').doc(userId);

          for (var examDoc in snapshot.docs) {
            final examId = examDoc.id;
            final notifRef = userRef.collection('notifications').doc(examId);

            final notifSnap = await notifRef.get();
            if (!notifSnap.exists) {
              await notifRef.set({
                'viewed': false,
                'subject': examDoc['subject'],
                'createdAt': examDoc['createdAt'],
              });
              debugPrint("Created notif for $userId -> exam $examId");
            }
          }
        });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _examListener?.cancel();
    studentIdController.removeListener(_updateButtonState);
    passwordController.removeListener(_updateButtonState);
    studentIdController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,

      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Image.asset(
                "assets/image/fots_student.png",
                width: 200,
                height: 200,
              ),
              const SizedBox(height: 60),

              // Student ID Field
              SizedBox(
                width: 320,
                child: TextField(
                  controller: studentIdController,
                  decoration: InputDecoration(
                    hintText: "Student ID",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 25),

              // Password Field with Eye Icon
              SizedBox(
                width: 320,
                child: TextField(
                  controller: passwordController,
                  obscureText: !_isPasswordVisible,
                  decoration: InputDecoration(
                    hintText: "Password",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _isPasswordVisible
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _isPasswordVisible = !_isPasswordVisible;
                        });
                      },
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 40),

              // Login Button
              isLoading
                  ? const CircularProgressIndicator()
                  : SizedBox(
                      width: 340,
                      child: ElevatedButton(
                        onPressed: isFormValid ? _login : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isFormValid
                              ? Colors.green
                              : Colors.grey,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text("Login"),
                      ),
                    ),

              const SizedBox(height: 20),

              // Forgot Password Button
              TextButton(
                onPressed: () {
                  context.go('/forgot');
                },
                child: const Text(
                  "Forgot Password?",
                  style: TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
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
