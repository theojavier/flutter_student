import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../helpers/SecureStorageHelper.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  // Shared theme palette (matches NotificationsPage)
  static const Color _bgColor = Color(0xFF0B1220);
  static const Color _headerColor = Color(0xFF0F2B45);
  static const Color _headerColorLight = Color(0xFF17456F);
  static const Color _cardColor = Color(0xFF0F3B61);
  static const Color _textColor = Color(0xFFE6F0F8);
  static const Color _mutedTextColor = Color(0xFF9FB0C3);
  static const Color _accentColor = Color(0xFF3D8BFF);
  static const Color _onlineColor = Color(0xFF4ADE80);

  String? userId;

  @override
  void initState() {
    super.initState();
    _loadUserId();
  }

  Future<void> _loadUserId() async {
    final storeduserId = await SecureStorageHelper.read('userId');
    setState(() {
      userId = storeduserId;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (userId == null) {
      return const Scaffold(
        backgroundColor: _bgColor,
        body: Center(child: CircularProgressIndicator(color: _accentColor)),
      );
    }

    final userRef = FirebaseFirestore.instance.collection("users").doc(userId);

    return Scaffold(
      backgroundColor: _bgColor,
      body: FutureBuilder<DocumentSnapshot>(
        future: userRef.get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _accentColor),
            );
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(
              child: Text(
                "Profile not found",
                style: TextStyle(color: _textColor),
              ),
            );
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;

          // Fix Imgur link handling
          String? imageUrl = data["profileImage"];
          if (imageUrl != null &&
              imageUrl.contains("imgur.com") &&
              !imageUrl.contains("i.imgur.com")) {
            imageUrl = "${imageUrl.replaceAll("imgur.com", "i.imgur.com")}.jpg";
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Small floating title bar — separate from the card below
                _buildTitleBar(),
                const SizedBox(height: 16),
                // Avatar block + Personal Details fused into ONE rounded card:
                // rounded corners live on the outer wrapper, the two zones
                // inside just change color with no gap between them.
                Container(
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
                      children: [
                        _buildAvatarZone(imageUrl, data),
                        _buildDetailsZone(
                          title: "Personal Details",
                          headerIcon: Icons.badge_outlined,
                          rows: [
                            _DetailRow(
                              Icons.person_outline,
                              "Name",
                              data["name"],
                            ),
                            _DetailRow(Icons.wc, "Gender", data["gender"]),
                            _DetailRow(
                              Icons.favorite_border,
                              "Civil Status",
                              data["civilStatus"],
                            ),
                            _DetailRow(
                              Icons.flag_outlined,
                              "Nationality",
                              data["nationality"],
                            ),
                            _DetailRow(
                              Icons.cake_outlined,
                              "Date of Birth",
                              data["dob"] ?? "N/A",
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Enrolment Details — its own separate floating card
                _buildInfoCard(
                  title: "Enrolment Details",
                  headerIcon: Icons.school_outlined,
                  rows: [
                    _DetailRow(
                      Icons.menu_book_outlined,
                      "Program",
                      data["program"],
                    ),
                    _DetailRow(
                      Icons.groups_outlined,
                      "Year/Block",
                      data["yearBlock"] ?? "N/A",
                    ),
                    _DetailRow(
                      Icons.event_note_outlined,
                      "Semester",
                      data["semester"],
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ---------- GLOW HELPERS ----------

  // Small glowing icon chip (gradient ring + soft accent glow).
  // Used for the section header icons.
  Widget _glowIconChip(IconData icon, {double iconSize = 16}) {
    return Container(
      padding: const EdgeInsets.all(2), // ring thickness
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
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
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10), // outer radius minus ring
        child: Container(
          color: _cardColor, // solid fill so the glow stays outside
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: iconSize, color: Colors.white),
        ),
      ),
    );
  }

  // Compact floating bar: icon + "My Profile" with a "STUDENT INFORMATION" tag
  Widget _buildTitleBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_headerColorLight, _headerColor],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(3), // border thickness
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF3D8BFF).withOpacity(0.9),
                  const Color(0xFF3D8BFF).withOpacity(0.25),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF3D8BFF).withOpacity(0.35),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                12,
              ), // outer radius minus padding
              child: Container(
                color: const Color(0xFF0F3B61),
                padding: const EdgeInsets.all(10),
                child: const Icon(
                  Icons.badge_outlined,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "My Profile",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  "STUDENT INFORMATION",
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
        ],
      ),
    );
  }

  // Top zone of the fused card: avatar with status dot, name, ID chip
  Widget _buildAvatarZone(String? imageUrl, Map<String, dynamic> data) {
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
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 96,
                height: 96,
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
                  child: (imageUrl != null && imageUrl.isNotEmpty)
                      ? Image.network(imageUrl, fit: BoxFit.cover)
                      : Container(
                          color: _cardColor,
                          child: const Icon(
                            Icons.person,
                            size: 44,
                            color: _mutedTextColor,
                          ),
                        ),
                ),
              ),
              Positioned(
                bottom: 2,
                right: 2,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: _onlineColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: _headerColor, width: 2.5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            (data["name"] ?? "N/A").toString().toUpperCase(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _textColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 10),

          // Student ID pill — gradient ring + glow (solid fill inside)
          Container(
            padding: const EdgeInsets.all(1.5), // ring thickness
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
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
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: _cardColor, // solid so the glow doesn't bleed inside
                borderRadius: BorderRadius.circular(28.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.badge, size: 14, color: _accentColor),
                  const SizedBox(width: 6),
                  Text(
                    data["studentId"]?.toString() ?? "N/A",
                    style: const TextStyle(
                      color: _textColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Bottom zone of the fused card: small header + detail rows, no card
  // decoration of its own — it inherits the outer wrapper's rounded corners.
  Widget _buildDetailsZone({
    required String title,
    required IconData headerIcon,
    required List<_DetailRow> rows,
  }) {
    return Container(
      width: double.infinity,
      color: _cardColor,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _glowIconChip(headerIcon),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
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
          const SizedBox(height: 8),
          for (int i = 0; i < rows.length; i++)
            _buildDetail(rows[i], shaded: i.isOdd),
        ],
      ),
    );
  }

  // Standalone floating card — used for Enrolment Details
  Widget _buildInfoCard({
    required String title,
    required IconData headerIcon,
    required List<_DetailRow> rows,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_cardColor.withOpacity(0.9), _cardColor.withOpacity(0.55)],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _glowIconChip(headerIcon),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
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
            const SizedBox(height: 8),
            for (int i = 0; i < rows.length; i++)
              _buildDetail(rows[i], shaded: i.isOdd),
          ],
        ),
      ),
    );
  }

  Widget _buildDetail(_DetailRow row, {required bool shaded}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: shaded ? Colors.white.withOpacity(0.03) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(row.icon, size: 16, color: _accentColor.withOpacity(0.8)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              row.label,
              style: const TextStyle(fontSize: 13, color: _mutedTextColor),
            ),
          ),
          Text(
            (row.value ?? "N/A").toString(),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _textColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow {
  final IconData icon;
  final String label;
  final dynamic value;

  const _DetailRow(this.icon, this.label, this.value);
}