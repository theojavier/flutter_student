// main_scaffold.dart
import 'package:flutter/material.dart';

class MainScaffold extends StatelessWidget {
  final Widget body;
  final String title;

  const MainScaffold({super.key, required this.body, this.title = ""});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green[700],
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Center(
          child: Image.asset("assets/logo.png", height: 40),
        ),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications),
                onPressed: () {
                  Navigator.pushNamed(context, "/notifications");
                },
              ),
              // 🔴 Badge placeholder
              Positioned(
                right: 10,
                top: 10,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                      color: Colors.red, borderRadius: BorderRadius.circular(8)),
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  child: const Text("5",
                      style: TextStyle(color: Colors.white, fontSize: 12),
                      textAlign: TextAlign.center),
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: CircleAvatar(
              backgroundImage: AssetImage("assets/profile.png"),
            ),
          )
        ],
      ),
      drawer: _buildDrawer(context),
      body: body,
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // 🔹 Drawer Header
          UserAccountsDrawerHeader(
            decoration: BoxDecoration(color: Colors.green[700]),
            accountName: const Text("Name",
                style: TextStyle(fontWeight: FontWeight.bold)),
            accountEmail: const Text("Section"),
            currentAccountPicture: const CircleAvatar(
              backgroundImage: AssetImage("assets/profile.png"),
            ),
            otherAccountsPictures: [
              IconButton(
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                onPressed: () {
                  // TODO: expand "My Profile / History"
                },
              ),
            ],
          ),

          ListTile(
            leading: const Icon(Icons.home),
            title: const Text("Home"),
            onTap: () => Navigator.pushReplacementNamed(context, "/home"),
          ),
          ListTile(
            leading: const Icon(Icons.book),
            title: const Text("Exam Item Page"),
            onTap: () => Navigator.pushReplacementNamed(context, "/exam-item"),
          ),
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text("Schedule"),
            onTap: () => Navigator.pushReplacementNamed(context, "/schedule"),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text("Exam History"),
            onTap: () => Navigator.pushReplacementNamed(context, "/exam-history"),
          ),
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text("Profile"),
            onTap: () => Navigator.pushReplacementNamed(context, "/profile"),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text("Logout"),
            onTap: () {
              // TODO: logout logic
            },
          ),
        ],
      ),
    );
  }
}
