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

  @override
  Widget build(BuildContext context) {
    // Make the header full width and with no margin so it visually connects
    // to the AppBar when the same color is used.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: SizedBox(
            height: 160, // adjust height to taste
            width: double.infinity,
            child: UserAccountsDrawerHeader(
              margin: EdgeInsets.zero, // important: remove default gap
              decoration: const BoxDecoration(
                 color: Color(0xFF0F2B45),// same as AppBar for fused look
              ),
              accountName: Text(
                widget.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFE6F0F8),
                ),
              ),
              accountEmail: Text(
                widget.section,
                style: const TextStyle(color: Colors.white70),
              ),
              currentAccountPicture: CircleAvatar(
                backgroundColor: Color(0xFF0F2B45),
                child: widget.profileImageUrl != null
                    ? ClipOval(
                        child: Image.network(
                          widget.profileImageUrl!,
                          key: ValueKey(
                            widget.profileImageUrl,
                          ), //  cache by URL
                          fit: BoxFit.cover,
                          width: 80,
                          height: 80,
                        ),
                      )
                    : const Icon(Icons.person, size: 40, color: Colors.grey),
              ),
              onDetailsPressed: () => setState(() => _expanded = !_expanded),
            ),
          ),
        ),

        // Expandable options (hidden by default)
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Container(
            color: Color.fromARGB(255, 19, 54, 87),
            child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.person,color: Colors.white),
                title: const Text("My Profile",
                style: TextStyle(color: Color(0xFFE6F0F8)), ),
                onTap: () {
                  setState(() => _expanded = false);
                  if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                    Navigator.of(context).pop();
                  }
                  widget.onProfileTap();
                },
              ),
              ListTile(
                leading: const Icon(Icons.history,color: Colors.white),
                title: const Text("History",
                style: TextStyle(color: Color(0xFFE6F0F8)), ),
                onTap: () {
                  setState(() => _expanded = false);
                  if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                    Navigator.of(context).pop();
                  }
                  widget.onHistoryTap();
                },
              ),
            ],
            ),
          ),
          duration: const Duration(milliseconds: 60),
          crossFadeState: _expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
        ),
      ],
    );
  }
}
