import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../services/firestore_service.dart';
import '../../sign_in_page.dart';
import '../widgets/settings_widgets.dart';
import 'switch_inventories_settings.dart';

class AccountSettings extends StatefulWidget {
  const AccountSettings({super.key});

  @override
  State<AccountSettings> createState() => _AccountSettingsState();
}

class _AccountSettingsState extends State<AccountSettings> {
  final TextEditingController _nameController = TextEditingController();
  final FocusNode _nameFocus = FocusNode();
  bool _isEditingName = false;
  String _currentHouseholdName = "Loading...";

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _nameController.text = user.displayName ?? "";
    }
    _loadHouseholdName();
  }

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
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("Name updated")));
        }
      }
      setState(() => _isEditingName = false);
    } else {
      setState(() => _isEditingName = true);
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _nameFocus.requestFocus();
      });
    }
  }

  Widget _buildInviteCard(ThemeData theme, Map<String, dynamic> invite) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary.withOpacity(0.15),
            theme.colorScheme.primary.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.mark_email_unread_outlined,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 14,
                    ),
                    children: [
                      TextSpan(
                        text: invite['inviterName'] ?? "Someone",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const TextSpan(text: " invited you to "),
                      TextSpan(
                        text: invite['householdName'] ?? "Inventory",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 0),
                    side: BorderSide(color: theme.dividerColor),
                  ),
                  onPressed: () =>
                      FirestoreService().declineInvitation(invite['id']),
                  child: Text(
                    "Decline",
                    style: TextStyle(color: theme.colorScheme.onSurface),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 0),
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.black,
                    elevation: 0,
                  ),
                  onPressed: () => FirestoreService().acceptInvitation(
                    invite['id'],
                    invite['householdId'],
                  ),
                  child: const Text("Accept"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = FirebaseAuth.instance.currentUser;

    return ResponsiveSettingsGrid(
      children: [
        // --- 1. DISPLAY NAME ---
        Container(
          height: 70,
          margin: const EdgeInsets.only(bottom: 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                theme.colorScheme.primary.withOpacity(0.1),
                theme.colorScheme.primary.withOpacity(0.4),
              ],
              stops: const [0.0, 1.0],
            ),
            border: Border.all(color: theme.dividerColor.withOpacity(0.1)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.person_outline,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    focusNode: _nameFocus,
                    enabled: _isEditingName,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: "Display Name",
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    style: TextStyle(
                      fontSize: 16,
                      color: theme.colorScheme.onSurface,
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
        ),

        // --- 2. EMAIL (Read Only) ---
        GradientSettingsTile(
          icon: Icons.email_outlined,
          title: "Email",
          subtitle: user?.email ?? "Not Logged In",
          onTap: () {},
          trailing: const SizedBox(),
        ),

        // --- NEW: PENDING INVITATIONS ---
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: FirestoreService().getInvitationsStream(),
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const SizedBox.shrink();
            }
            return Column(
              children: snapshot.data!
                  .map((invite) => _buildInviteCard(theme, invite))
                  .toList(),
            );
          },
        ),

        // --- 3. SWITCH INVENTORY ---
        GradientSettingsTile(
          icon: Icons.swap_horiz,
          title: "Switch Inventory",
          subtitle: _currentHouseholdName,
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (c) => const SwitchInventoriesSettings(),
              ),
            );
            _loadHouseholdName();
          },
        ),

        // --- 4. SIGN OUT ---
        GradientSettingsTile(
          icon: Icons.logout,
          title: "Sign Out",
          subtitle: "Log out of this device",
          trailing: const SizedBox(),
          onTap: () async {
            bool? confirm = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                backgroundColor: theme.cardColor,
                contentPadding: const EdgeInsets.all(24),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.logout_rounded,
                        size: 32,
                        color: Colors.redAccent,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      "Sign Out",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "Are you sure you want to log out?",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 25),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text(
                              "Cancel",
                              style: TextStyle(
                                color: theme.colorScheme.onSurface,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              backgroundColor: Colors.redAccent,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text(
                              "Sign Out",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );

            if (confirm == true) {
              await FirebaseAuth.instance.signOut();
              if (mounted) {
                Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const SignInPage()),
                  (route) => false,
                );
              }
            }
          },
        ),
      ],
    );
  }
}
