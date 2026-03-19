import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../services/firestore_service.dart';

import '../../../models/text_input.dart';
import '../widgets/settings_format.dart';

class SwitchInventoriesSettings extends StatefulWidget {
  const SwitchInventoriesSettings({super.key});

  @override
  State<SwitchInventoriesSettings> createState() =>
      _SwitchInventoriesSettingsState();
}

class _SwitchInventoriesSettingsState extends State<SwitchInventoriesSettings> {
  final FirestoreService _fs = FirestoreService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Optimistic UI: Track invites we've just acted on to hide them instantly
  final Set<String> _hiddenInviteIds = {};

  // --- ACTIONS ---

  void _showCreateDialog() {
    showSmartTextInputDialog(
      context: context,
      title: "Create New Inventory",
      label: "Inventory Name",
      buttonText: "Create",
      onSubmit: (val) async => await _fs.createHousehold(val),
    );
  }

  void _showInviteDialog() {
    showSmartTextInputDialog(
      context: context,
      title: "Invite Member",
      label: "Email Address",
      buttonText: "Invite",
      onSubmit: (val) async {
        try {
          final String email = val.trim();
          final String? householdId = _fs.currentHouseholdId;
          final User? currentUser = _auth.currentUser;

          if (householdId == null || currentUser == null) {
            throw "No active inventory selected.";
          }

          final hhDoc = await _db
              .collection('households')
              .doc(householdId)
              .get();
          final String householdName = hhDoc.data()?['name'] ?? "Inventory";

          final userDoc = await _db
              .collection('users')
              .doc(currentUser.uid)
              .get();
          final String inviterName =
              userDoc.data()?['displayName'] ?? "A friend";

          await _db.collection('invitations').add({
            'email': email,
            'householdId': householdId,
            'householdName': householdName,
            'inviterName': inviterName,
            'inviterUid': currentUser.uid,
            'status': 'pending',
            'timestamp': FieldValue.serverTimestamp(),
          });

          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text("Invitation sent!")));
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text("Error: $e")));
          }
        }
      },
    );
  }

  void _showRenameDialog(String id, String currentName) {
    showSmartTextInputDialog(
      context: context,
      title: "Rename Inventory",
      label: "New Name",
      buttonText: "Save",
      initialValue: currentName,
      onSubmit: (val) async {
        await _db.collection('households').doc(id).update({'name': val});
        if (mounted) setState(() {});
      },
    );
  }

  void _confirmDelete(String id, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: const Text("Delete Inventory?"),
        content: Text("Permanently delete '$name'? This cannot be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final uid = _auth.currentUser?.uid;
              if (uid == null) return;

              await _db.collection('households').doc(id).delete();
              await _db.collection('users').doc(uid).update({
                'joinedHouseholds': FieldValue.arrayRemove([id]),
              });

              if (mounted) {
                Navigator.pop(ctx);
                setState(() {});
              }
            },
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showRemoveConfirmDialog(String memberName) {
    final theme = Theme.of(context);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                Icons.person_remove_rounded,
                size: 32,
                color: Colors.redAccent,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              "Remove Member",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "Are you sure you want to remove $memberName from this inventory?",
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
                      "Remove",
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
  }

  void _showMembersDialog(String householdId, String ownerId, String name) {
    showDialog(
      context: context,
      builder: (ctx) => FutureBuilder<List<Map<String, dynamic>>>(
        future: _fs.getHouseholdMembers(householdId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const AlertDialog(
              content: SizedBox(
                height: 50,
                child: Center(child: CircularProgressIndicator()),
              ),
            );
          }
          final members = snapshot.data!;
          final currentUserUid = _auth.currentUser!.uid;
          final isOwner = currentUserUid == ownerId;

          return AlertDialog(
            title: Text("$name Members"),
            content: SizedBox(
              width: double.maxFinite,
              child: members.isEmpty
                  ? const Text("No members found.")
                  : ListView.separated(
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
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primary.withOpacity(0.1),
                            child: Text(
                              (m['displayName'] ?? "?")[0].toUpperCase(),
                            ),
                          ),
                          title: Text(
                            (m['displayName'] ?? "Unknown") +
                                (isMe ? " (You)" : ""),
                          ),
                          subtitle: Text(
                            isMemberOwner ? "Owner" : (m['email'] ?? ""),
                          ),
                          trailing: (isOwner && !isMemberOwner)
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.remove_circle_outline,
                                    color: Colors.red,
                                  ),
                                  onPressed: () async {
                                    final confirm =
                                        await _showRemoveConfirmDialog(
                                          m['displayName'] ?? "this member",
                                        );

                                    if (confirm != true) return;

                                    await _db
                                        .collection('households')
                                        .doc(householdId)
                                        .update({
                                          'members': FieldValue.arrayRemove([
                                            m['uid'],
                                          ]),
                                        });
                                    await _db
                                        .collection('users')
                                        .doc(m['uid'])
                                        .update({
                                          'joinedHouseholds':
                                              FieldValue.arrayRemove([
                                                householdId,
                                              ]),
                                        });

                                    if (mounted) {
                                      Navigator.pop(ctx);
                                      _showMembersDialog(
                                        householdId,
                                        ownerId,
                                        name,
                                      );
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

  // --- DATABASE HELPERS ---
  Future<void> _handleDecline(String inviteId) async {
    // Optimistic Update
    setState(() {
      _hiddenInviteIds.add(inviteId);
    });
    // Direct Delete
    await _db.collection('invitations').doc(inviteId).delete();
  }

  Future<void> _handleAccept(String inviteId, String householdId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Optimistic Update
    setState(() {
      _hiddenInviteIds.add(inviteId);
    });

    // 1. Add user to Household members
    await _db.collection('households').doc(householdId).update({
      'members': FieldValue.arrayUnion([user.uid]),
    });

    // 2. Add Household to User's list
    await _db.collection('users').doc(user.uid).update({
      'joinedHouseholds': FieldValue.arrayUnion([householdId]),
    });

    // 3. Delete the invitation so it never appears again
    await _db.collection('invitations').doc(inviteId).delete();
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    final theme = Theme.of(context);

    if (user == null) {
      return const Scaffold(body: Center(child: Text("Log in required")));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Switch Inventory",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _db.collection('users').doc(user.uid).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!.data() as Map<String, dynamic>?;
          final List joinedIds = data?['joinedHouseholds'] ?? [];
          final String currentId = _fs.currentHouseholdId ?? "";

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GradientSettingsTile(
                  icon: Icons.add_circle_outline,
                  title: "Create New Inventory",
                  subtitle: "Start a fresh collection",
                  onTap: _showCreateDialog,
                ),
                GradientSettingsTile(
                  icon: Icons.person_add_alt_1_outlined,
                  title: "Invite Member",
                  subtitle: "Add to current inventory",
                  onTap: _showInviteDialog,
                ),


                // --- PENDING INVITES SECTION ---
                StreamBuilder<QuerySnapshot>(
                  stream: _db
                      .collection('invitations')
                      .where('email', isEqualTo: user.email)
                      .where('status', isEqualTo: 'pending')
                      .snapshots(),
                  builder: (context, inviteSnap) {
                    if (!inviteSnap.hasData || inviteSnap.data!.docs.isEmpty) {
                      return const SizedBox.shrink();
                    }

                    final visibleInvites = inviteSnap.data!.docs
                        .where((doc) => !_hiddenInviteIds.contains(doc.id))
                        .toList();

                    if (visibleInvites.isEmpty) return const SizedBox.shrink();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 15),
                        const SettingsHeader(title: "Pending Invites"),
                        ...visibleInvites.map((doc) {
                          final invite = doc.data() as Map<String, dynamic>;
                          invite['id'] = doc.id; // Ensure ID is in the map
                          return InviteSettingsTile(
                            invite: invite,
                            onAccept: () =>
                                _handleAccept(doc.id, invite['householdId']),
                            onDecline: () => _handleDecline(doc.id),
                          );
                        }).toList(),
                      ],
                    );
                  },
                ),

                // ---------------------------------
                const SizedBox(height: 25),

                const SettingsHeader(title: "Your Inventories"),

                if (joinedIds.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(30),
                    decoration: BoxDecoration(
                      color: theme.dividerColor.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: theme.dividerColor.withOpacity(0.1),
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 40,
                          color: theme.disabledColor,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "No inventories yet",
                          style: TextStyle(color: theme.disabledColor),
                        ),
                      ],
                    ),
                  )
                else
                  Column(
                    children: joinedIds.map<Widget>((id) {
                      return FutureBuilder<DocumentSnapshot>(
                        future: _db.collection('households').doc(id).get(),
                        builder: (context, hhSnap) {
                          if (!hhSnap.hasData) {
                            return const SizedBox(
                              height: 80,
                              child: Center(
                                child: LinearProgressIndicator(minHeight: 2),
                              ),
                            );
                          }

                          final hhData =
                              hhSnap.data!.data() as Map<String, dynamic>?;
                          if (hhData == null) return const SizedBox();

                          final name = hhData['name'] ?? "Unknown";
                          final ownerId = hhData['owner'] ?? "";
                          final members = hhData['members'] ?? [];
                          final isCurrent = id == currentId;
                          final isShared = members.length > 1;
                          final isOwner = ownerId == user.uid;

                          return GradientSettingsTile(
                            icon: isCurrent
                                ? Icons.check
                                : Icons.radio_button_unchecked,
                            title: name,
                            subtitle: isCurrent ? "Active" : "Tap to Switch",
                            onTap: () async {
                              if (!isCurrent) {
                                await _fs.switchHousehold(id);
                                if (mounted) setState(() {});
                              }
                            },
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isShared)
                                  IconButton(
                                    icon: Icon(
                                      Icons.group_outlined,
                                      color: theme.colorScheme.primary,
                                    ),
                                    onPressed: () => _showMembersDialog(
                                      id as String,
                                      ownerId,
                                      name,
                                    ),
                                  ),
                                if (isOwner)
                                  PopupMenuButton<String>(
                                    icon: Icon(
                                      Icons.more_vert,
                                      color: theme.colorScheme.onSurface
                                          .withOpacity(0.6),
                                    ),
                                    onSelected: (val) {
                                      if (val == 'rename') {
                                        _showRenameDialog(id as String, name);
                                      }
                                      if (val == 'delete') {
                                        _confirmDelete(id as String, name);
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                        value: 'rename',
                                        child: Text('Rename'),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Text(
                                          'Delete',
                                          style: TextStyle(color: Colors.red),
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          );
                        },
                      );
                    }).toList(),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
