import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/firestore_service.dart';

class HouseholdPage extends StatefulWidget {
  const HouseholdPage({super.key});

  @override
  State<HouseholdPage> createState() => _HouseholdPageState();
}

class _HouseholdPageState extends State<HouseholdPage> {
  final FirestoreService _fs = FirestoreService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  void _showCreateDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: Text(
          "Create New Inventory",
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: "Inventory Name",
            labelStyle: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Theme.of(context).dividerColor),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              "Cancel",
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.black,
            ),
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                await _fs.createHousehold(controller.text.trim());
                if (mounted) Navigator.pop(ctx);
              }
            },
            child: const Text("Create"),
          ),
        ],
      ),
    );
  }

  // --- NEW: RENAME DIALOG ---
  void _showRenameDialog(String householdId, String currentName) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: Text(
          "Rename Inventory",
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: "Inventory Name",
            labelStyle: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Theme.of(context).dividerColor),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              "Cancel",
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.black,
            ),
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                await _db.collection('households').doc(householdId).update({
                  'name': controller.text.trim(),
                });
                if (mounted) {
                  Navigator.pop(ctx);
                  setState(() {}); // Trigger rebuild to update UI immediately
                }
              }
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  void _showInviteDialog() {
    final controller = TextEditingController();
    bool _loading = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: Theme.of(context).cardColor,
            title: Text(
              "Invite Member",
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Enter email address to invite:",
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: controller,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  decoration: InputDecoration(
                    labelText: "Email Address",
                    labelStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    border: const OutlineInputBorder(),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Theme.of(context).dividerColor,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  "Cancel",
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.black,
                ),
                onPressed: _loading
                    ? null
                    : () async {
                        setDialogState(() => _loading = true);
                        try {
                          await _fs.sendInviteByEmail(controller.text.trim());
                          if (mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Invitation sent!")),
                            );
                          }
                        } catch (e) {
                          setDialogState(() => _loading = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(e.toString()),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                child: const Text("Invite"),
              ),
            ],
          );
        },
      ),
    );
  }

  // NEW: Manage Members Dialog
  void _showMembersDialog(
    String householdId,
    String ownerId,
    String householdName,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => FutureBuilder<List<Map<String, dynamic>>>(
        future: _fs.getHouseholdMembers(householdId),
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const AlertDialog(
              content: SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator()),
              ),
            );

          final members = snapshot.data!;
          final currentUserUid = _auth.currentUser!.uid;
          final isOwner = currentUserUid == ownerId;

          return AlertDialog(
            title: Text("$householdName Members"),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: members.length,
                separatorBuilder: (c, i) => const Divider(),
                itemBuilder: (c, i) {
                  final m = members[i];
                  final isMe = m['uid'] == currentUserUid;
                  final isMemberOwner = m['uid'] == ownerId;

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      child: Text(m['displayName'][0].toUpperCase()),
                    ),
                    title: Text(m['displayName'] + (isMe ? " (You)" : "")),
                    subtitle: Text(isMemberOwner ? "Owner" : m['email']),
                    trailing: (isOwner && !isMemberOwner)
                        ? IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.red,
                            ),
                            onPressed: () async {
                              // Confirm delete
                              bool? confirm = await showDialog(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: const Text("Remove Member?"),
                                  content: Text(
                                    "Remove ${m['displayName']} from this inventory?",
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(c, false),
                                      child: const Text("Cancel"),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(c, true),
                                      child: const Text(
                                        "Remove",
                                        style: TextStyle(color: Colors.red),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await _fs.removeMember(householdId, m['uid']);
                                if (mounted)
                                  Navigator.pop(ctx); // Close list to refresh
                              }
                            },
                          )
                        : null,
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Close"),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = _auth.currentUser;
    if (user == null)
      return const Scaffold(body: Center(child: Text("Please log in.")));

    return Scaffold(
      appBar: AppBar(title: const Text("My Inventories")),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _db.collection('users').doc(user.uid).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());

          final userData = snapshot.data!.data() as Map<String, dynamic>?;
          final List joinedIds = userData?['joinedHouseholds'] ?? [];
          final String currentId = _fs.currentHouseholdId ?? "";

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // CURRENT INFO CARD
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  border: Border.all(
                    color: theme.colorScheme.primary.withOpacity(0.5),
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Text(
                      "Current Inventory (ID: $currentId)",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.person_add),
                      label: const Text("Invite Member"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: Colors.black,
                      ),
                      onPressed: _showInviteDialog,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),

              ElevatedButton.icon(
                icon: const Icon(Icons.add_home),
                label: const Text("Create New Inventory"),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: _showCreateDialog,
              ),
              const SizedBox(height: 20),
              const Text(
                "Your Inventories",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 10),

              // LIST OF JOINED HOUSEHOLDS
              ...joinedIds.map((id) {
                return FutureBuilder<DocumentSnapshot>(
                  future: _db.collection('households').doc(id).get(),
                  builder: (context, hhSnapshot) {
                    if (!hhSnapshot.hasData) return const SizedBox();
                    final hhData =
                        hhSnapshot.data!.data() as Map<String, dynamic>?;
                    final name = hhData?['name'] ?? "Unknown";
                    final ownerId = hhData?['owner'] ?? "";
                    final List members = hhData?['members'] ?? [];
                    final isCurrent = id == currentId;
                    final isShared = members.length > 1;
                    final isOwner = ownerId == user.uid;

                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: isCurrent
                              ? theme.colorScheme.primary
                              : theme.dividerColor,
                          width: isCurrent ? 2 : 1,
                        ),
                      ),
                      color: isCurrent
                          ? theme.colorScheme.primary.withOpacity(0.05)
                          : theme.cardColor,
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: Icon(
                          isCurrent
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: isCurrent
                              ? theme.colorScheme.primary
                              : theme.disabledColor,
                        ),
                        title: Row(
                          children: [
                            Text(
                              name,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isCurrent
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                            if (isShared) ...[
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () =>
                                    _showMembersDialog(id, ownerId, name),
                                child: Icon(
                                  Icons.group,
                                  size: 16,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          "ID: $id",
                          style: const TextStyle(fontSize: 10),
                        ),
                        trailing: isCurrent
                            ? Chip(
                                label: const Text("Active"),
                                backgroundColor: theme.colorScheme.primary
                                    .withOpacity(0.2),
                                side: BorderSide.none,
                              )
                            : ElevatedButton(
                                child: const Text("Switch"),
                                onPressed: () async {
                                  await _fs.switchHousehold(id);
                                  if (mounted) setState(() {});
                                },
                              ),
                        // LONG PRESS TO RENAME
                        onLongPress: () {
                          if (isOwner) {
                            _showRenameDialog(id, name);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  "Only the owner can rename this inventory.",
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    );
                  },
                );
              }).toList(),
            ],
          );
        },
      ),
    );
  }
}
