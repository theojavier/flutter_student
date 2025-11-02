import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String? userId;

  @override
  void initState() {
    super.initState();
    _loadUserId();
  }

  Future<void> _loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      userId = prefs.getString("userId");
    });
  }

  @override
  Widget build(BuildContext context) {
    if (userId == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final userRef = FirebaseFirestore.instance.collection("users").doc(userId);

    return Scaffold(
      backgroundColor: Colors.white,
      body: FutureBuilder<DocumentSnapshot>(
        future: userRef.get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text("Profile not found"));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;

          //  Fix Imgur link handling
          String? imageUrl = data["profileImage"];
          if (imageUrl != null &&
              imageUrl.contains("imgur.com") &&
              !imageUrl.contains("i.imgur.com")) {
            imageUrl = "${imageUrl.replaceAll("imgur.com", "i.imgur.com")}.jpg";
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Blue Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: Colors.blue[800],
                  child: const Text(
                    "Profile",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // White Card with Profile Info
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundImage: (imageUrl != null && imageUrl.isNotEmpty)
                              ? NetworkImage(imageUrl)
                              : null,
                          backgroundColor: Colors.grey[300],
                          child: (imageUrl == null || imageUrl.isEmpty)
                              ? const Icon(Icons.person, size: 50, color: Colors.white)
                              : null,
                        ),
                        const SizedBox(height: 16),
                        // Personal Details
                        _buildSectionTitle("Personal Details"),
                        _buildDetail("Name", data["name"]),
                        _buildDetail("Student No.", data["studentId"]),
                        _buildDetail("Gender", data["gender"]),
                        _buildDetail("Date of Birth", data["dob"] ?? "N/A"),
                        _buildDetail("Civil Status", data["civilStatus"]),
                        _buildDetail("Nationality", data["nationality"]),
                        const SizedBox(height: 8),
                        // Enrolment Details
                        _buildSectionTitle("Enrolment Details"),
                        _buildDetail("Program", data["program"]),
                        _buildDetail("Year/Block", data["yearBlock"] ?? "N/A"),
                        _buildDetail("Semester", data["semester"]),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionTitle(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.green[700],
          ),
        ),
      );

  Widget _buildDetail(String label, dynamic value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              "$label: ${value ?? "N/A"}",
              style: const TextStyle(fontSize: 14, color: Colors.black87),
            ),
          ),
          const Divider(height: 1, color: Colors.grey),
        ],
      );
}
