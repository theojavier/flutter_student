import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

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
      // Call your Cloud Function
      final functions = FirebaseFunctions.instanceFor(
        region: 'asia-southeast1',
      );

      final result = await functions.httpsCallable('loginWithStudentId').call({
        'studentId': studentId,
        'password': password,
      });

      final data = result.data;
      final token = data['token'];
      final role = data['role'];
      final program = data['program'];
      final yearBlock = data['yearBlock'];

      // Sign in with the custom token
      final userCredential = await auth.signInWithCustomToken(token);

      if (userCredential.user == null) {
        _showError("Login failed: no user returned");
        setState(() => isLoading = false);
        return;
      }

      // Proceed only if student role
      if (role.toString().toLowerCase() == "student") {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString("userId", userCredential.user!.uid);
        await prefs.setString("studentId", studentId);

        if (program != null) await prefs.setString("program", program);
        if (yearBlock != null) await prefs.setString("yearBlock", yearBlock);

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Welcome Student!")));

        if (program != null && yearBlock != null) {
          startExamListener(userCredential.user!.uid, program, yearBlock);
        }

        if (mounted) context.go('/home');
      } else {
        _showError("Access denied (not a student)");
      }
    } on FirebaseFunctionsException catch (e) {
      _showError(e.message ?? "Login failed");
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
