import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../services/firestore_service.dart';
import '../../household_page.dart';
import '../widgets/settings_section.dart';

class AccountSettings extends StatefulWidget {
  const AccountSettings({super.key});

  @override
  State<AccountSettings> createState() => _AccountSettingsState();
}

class _AccountSettingsState extends State<AccountSettings> {
  final TextEditingController _nameController = TextEditingController();
  final FocusNode _nameFocus = FocusNode();
  bool _isEditingName = false;
  String _currentHouseholdName = "Loading..."; // Store name in state

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _nameController.text = user.displayName ?? "";
    }
    _loadHouseholdName();
  }

  // FIX: Load this once, not every time we build the UI
  Future<void> _loadHouseholdName() async {
    final String? id = FirestoreService().currentHouseholdId;
    if (id == null) {
      if (mounted)
        setState(() => _currentHouseholdName = "No Inventory Selected");
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('households')
          .doc(id)
          .get();
      if (mounted && doc.exists) {
        setState(
          () => _currentHouseholdName =
              "Current: ${doc.data()?['name'] ?? 'Unknown'}",
        );
      }
    } catch (e) {
      if (mounted) setState(() => _currentHouseholdName = "Current: Unknown");
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> _toggleNameEdit() async {
    if (_isEditingName) {
      if (_nameController.text.trim().isNotEmpty) {
        await FirestoreService().updateDisplayName(_nameController.text.trim());
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("Name updated")));
      }
      setState(() => _isEditingName = false);
    } else {
      setState(() => _isEditingName = true);
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _nameFocus.requestFocus();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = FirebaseAuth.instance.currentUser;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader("ACCOUNT", theme),
        SettingsSection(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.person, color: theme.iconTheme.color),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      focusNode: _nameFocus,
                      enabled: _isEditingName,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: "Display Name",
                        isDense: true,
                      ),
                      style: TextStyle(
                        color: _isEditingName
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurface.withOpacity(0.7),
                        fontWeight: FontWeight.bold,
                      ),
                      onSubmitted: (_) => _toggleNameEdit(),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _isEditingName ? Icons.check : Icons.edit,
                      color: theme.colorScheme.primary,
                    ),
                    onPressed: _toggleNameEdit,
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: theme.dividerColor),
            ListTile(
              leading: Icon(Icons.email_outlined),
              title: Text(user?.email ?? "Not Logged In"),
            ),
            ListTile(
              leading: Icon(Icons.swap_horiz),
              title: const Text("Switch Inventory"),
              subtitle: Text(
                _currentHouseholdName,
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (c) => const HouseholdPage()),
                );
                _loadHouseholdName(); // Refresh name on return
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text(
                "Sign Out",
                style: TextStyle(color: Colors.redAccent),
              ),
              onTap: () async {
                await FirebaseAuth.instance.signOut();
                if (mounted) Navigator.pop(context);
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHeader(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: TextStyle(
          color: theme.colorScheme.primary,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}
