import 'package:flutter/material.dart';

class NavHeader extends StatefulWidget {
  final String name;
  final String section;
  final String? profileImageUrl;
  final VoidCallback onProfileTap;
  final VoidCallback onHistoryTap;

  const NavHeader({
    super.key,
    required this.name,
    required this.section,
    this.profileImageUrl,
    required this.onProfileTap,
    required this.onHistoryTap,
  });

  @override
  State<NavHeader> createState() => _NavHeaderState();
}

class _NavHeaderState extends State<NavHeader> {
  bool _expanded = false;

  void _toggleExpand() {
    setState(() => _expanded = !_expanded);
  }

  void _handleTap(VoidCallback callback) {
    // ✅ Collapse dropdown first
    if (_expanded) setState(() => _expanded = false);

    // ✅ Then call the actual navigation callback
    Future.microtask(callback);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: _toggleExpand,
          child: SizedBox(
            height: 160,
            width: double.infinity,
            child: UserAccountsDrawerHeader(
              margin: EdgeInsets.zero,
              decoration: const BoxDecoration(
                color: Colors.blue,
              ),
              accountName: Text(
                widget.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              accountEmail: Text(
                widget.section,
                style: const TextStyle(color: Colors.white70),
              ),
              currentAccountPicture: CircleAvatar(
                backgroundColor: Colors.white,
                child: widget.profileImageUrl != null
                    ? ClipOval(
                        child: Image.network(
                          widget.profileImageUrl!,
                          key: ValueKey(widget.profileImageUrl),
                          fit: BoxFit.cover,
                          width: 80,
                          height: 80,
                        ),
                      )
                    : const Icon(Icons.person, size: 40, color: Colors.grey),
              ),
              onDetailsPressed: _toggleExpand,
            ),
          ),
        ),

        // 🔹 Dropdown (closes when any option clicked)
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text("My Profile"),
                onTap: () => _handleTap(widget.onProfileTap),
              ),
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text("History"),
                onTap: () => _handleTap(widget.onHistoryTap),
              ),
            ],
          ),
          duration: const Duration(milliseconds: 200),
          crossFadeState:
              _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
        ),
      ],
    );
  }
}
