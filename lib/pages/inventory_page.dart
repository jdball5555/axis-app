import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/inventory_item.dart';
import '../services/firestore_service.dart';
import 'activity_log_page.dart';

class AxisInventoryTab extends StatefulWidget {
  const AxisInventoryTab({super.key});

  // CACHE: Remembers title to prevent flickering
  static String? lastKnownName;
  static bool lastKnownShared = false;

  @override
  State<AxisInventoryTab> createState() => _AxisInventoryTabState();
}

class _AxisInventoryTabState extends State<AxisInventoryTab>
    with AutomaticKeepAliveClientMixin {
  final FirestoreService _db = FirestoreService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late Stream<List<InventoryItem>> _inventoryStream;
  Set<String> _mutedRooms = {};

  // Title Logic
  StreamSubscription<DocumentSnapshot>? _householdSub;
  String _currentSubscribedId = "";
  String _householdName = AxisInventoryTab.lastKnownName ?? "My Inventory";
  bool _isShared = AxisInventoryTab.lastKnownShared;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _inventoryStream = _db.getInventoryStream();
    _loadMutedRooms();
    _checkForHouseholdUpdate();
  }

  @override
  void didUpdateWidget(AxisInventoryTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    _checkForHouseholdUpdate();
  }

  @override
  void dispose() {
    _householdSub?.cancel();
    super.dispose();
  }

  void _checkForHouseholdUpdate() {
    final newId = _db.currentHouseholdId;
    if (newId == null || newId == _currentSubscribedId) return;

    _householdSub?.cancel();
    _currentSubscribedId = newId;

    _householdSub = _firestore
        .collection('households')
        .doc(newId)
        .snapshots()
        .listen((snapshot) {
          if (snapshot.exists && snapshot.data() != null) {
            final data = snapshot.data() as Map<String, dynamic>;
            final newName = data['name'] ?? "My Inventory";
            final List members = data['members'] ?? [];
            final newShared = members.length > 1;

            // Update Cache
            AxisInventoryTab.lastKnownName = newName;
            AxisInventoryTab.lastKnownShared = newShared;

            if (mounted) {
              setState(() {
                _householdName = newName;
                _isShared = newShared;
              });
            }
          }
        });
  }

  Future<void> _loadMutedRooms() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        // Load both lists to determine if a room is fully muted (no icons)
        // If a room is in BOTH mute lists, it has NO notifications.
        final runout = (prefs.getStringList('axis_muted_runout_rooms') ?? [])
            .toSet();
        final usage = (prefs.getStringList('axis_muted_usage_rooms') ?? [])
            .toSet();

        // _mutedRooms will store rooms where BOTH are muted (so we hide the icon)
        _mutedRooms = runout.intersection(usage);
      });
    }
  }

  // --- ACTIONS ---

  void _addItem(String name, String type, String? room) {
    _db.addItem(
      InventoryItem(name: name, type: type, roomLocation: room, quantity: 0),
    );

    if (type == 'Item') {
      _db.logActivity("CREATED ITEM", name, room ?? "Unknown", 0, 0);
    } else {
      _db.logActivity("CREATED ROOM", name, "N/A", 0, 0);
    }
  }

  void _confirmUseOne(InventoryItem item) {
    if (item.quantity <= 0) {
      _showSnack("None left to use!");
      return;
    }
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          backgroundColor: Theme.of(context).cardColor,
          title: Text(
            "Use Item?",
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
          content: Text(
            "Did you use 1 '${item.name}'?",
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          actions: [
            TextButton(
              child: Text(
                "Cancel",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              onPressed: () => Navigator.pop(ctx),
            ),
            TextButton(
              child: Text(
                "Yes, I used one",
                style: TextStyle(color: Theme.of(context).primaryColor),
              ),
              onPressed: () {
                _db.updateQuantity(
                  item.name,
                  item.roomLocation,
                  item.quantity - 1,
                );
                _db.logActivity(
                  "USED ONE",
                  item.name,
                  item.roomLocation ?? "Unknown",
                  -1,
                  item.quantity - 1,
                );
                Navigator.pop(ctx);
              },
            ),
          ],
        );
      },
    );
  }

  void _confirmDelete(InventoryItem item) {
    final isRoom = item.type == "Room";
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          backgroundColor: Theme.of(context).cardColor,
          title: Text(
            "Delete?",
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
          content: Text(
            isRoom
                ? "WARNING: Deleting '${item.name}' will also delete ALL items in this room."
                : "Are you sure you want to delete '${item.name}'?",
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          actions: [
            TextButton(
              child: Text(
                "Cancel",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              onPressed: () => Navigator.pop(ctx),
            ),
            TextButton(
              child: const Text(
                "Delete",
                style: TextStyle(color: Colors.redAccent),
              ),
              onPressed: () {
                if (isRoom) {
                  _db.deleteRoom(item.name);
                  _db.logActivity("ROOM DELETED", item.name, "N/A", 0, 0);
                } else {
                  _db.deleteItem(item.name, item.roomLocation);
                  _db.logActivity(
                    "DELETED",
                    item.name,
                    item.roomLocation ?? "Unknown",
                    -item.quantity,
                    0,
                  );
                }
                Navigator.pop(ctx);
              },
            ),
          ],
        );
      },
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(color: isDark ? Colors.white : null),
        ),
        backgroundColor: isDark ? const Color(0xFF2C2C2C) : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // --- SMART RESTOCK LOGIC ---

  void _showQuantityDialog(InventoryItem item, List<InventoryItem> allItems) {
    // 1. Find potential sources (Same Name, Different Room, Has Stock)
    final otherSources = allItems
        .where(
          (i) =>
              i.name.trim().toLowerCase() == item.name.trim().toLowerCase() &&
              i.roomLocation != item.roomLocation &&
              i.quantity > 0,
        )
        .toList();

    // 2. Determine initial selection
    String selectedSource = "NEW_PURCHASE";

    // Check if the saved default source is valid (exists in active inventory)
    if (item.defaultSource != null && item.defaultSource != "NEW_PURCHASE") {
      final defaultExists = otherSources.any(
        (s) => s.roomLocation == item.defaultSource,
      );
      if (defaultExists) {
        selectedSource = item.defaultSource!;
      }
    } else if (item.defaultSource == "NEW_PURCHASE") {
      selectedSource = "NEW_PURCHASE";
    }

    int quantityToAdd = 1;
    bool setAsDefault = false;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final newTotal = item.quantity + quantityToAdd;
            final theme = Theme.of(context);

            final savedDefault = item.defaultSource ?? "NEW_PURCHASE";
            final bool showSetDefault = selectedSource != savedDefault;

            return AlertDialog(
              backgroundColor: theme.cardColor,
              title: Text(
                "Restock ${item.name}",
                style: TextStyle(color: theme.colorScheme.onSurface),
                textAlign: TextAlign.center,
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // QUANTITY SELECTOR
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.remove_circle_outline,
                            color: theme.iconTheme.color,
                            size: 32,
                          ),
                          onPressed: () {
                            if (quantityToAdd > 1)
                              setDialogState(() => quantityToAdd--);
                          },
                        ),
                        Container(
                          constraints: const BoxConstraints(minWidth: 60),
                          alignment: Alignment.center,
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            "+$quantityToAdd",
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.add_circle_outline,
                            color: theme.iconTheme.color,
                            size: 32,
                          ),
                          onPressed: () {
                            setDialogState(() => quantityToAdd++);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),

                    // TOTAL DISPLAY
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 16,
                      ),
                      decoration: BoxDecoration(
                        color: theme.dividerColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "Total: ",
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            "${item.quantity}",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8.0,
                            ),
                            child: Icon(
                              Icons.arrow_forward,
                              size: 16,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          Text(
                            "$newTotal",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // SOURCE SELECTION UI
                    if (otherSources.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      const Divider(),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Source:",
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),

                      // 1. New Purchase Option
                      RadioListTile<String>(
                        value: "NEW_PURCHASE",
                        groupValue: selectedSource,
                        activeColor: theme.colorScheme.primary,
                        title: const Text("New Purchase"),
                        subtitle: const Text("Bought from store"),
                        contentPadding: EdgeInsets.zero,
                        onChanged: (val) =>
                            setDialogState(() => selectedSource = val!),
                        secondary: (savedDefault == "NEW_PURCHASE")
                            ? Icon(
                                Icons.star,
                                color: theme.colorScheme.primary,
                                size: 16,
                              )
                            : null,
                      ),

                      // 2. Room Options
                      ...otherSources.map((source) {
                        final isDefault =
                            source.roomLocation == item.defaultSource;
                        // Move default to top visually by list order logic (if handled by sort)
                        // Here we just map them. Sorting should be done on 'otherSources' list beforehand if strict order is needed.
                        // For now, mapping works.
                        return RadioListTile<String>(
                          value: source.roomLocation ?? "Unknown",
                          groupValue: selectedSource,
                          activeColor: theme.colorScheme.primary,
                          title: Row(
                            children: [
                              Text("From ${source.roomLocation}"),
                              if (isDefault)
                                Padding(
                                  padding: const EdgeInsets.only(left: 8.0),
                                  child: Icon(
                                    Icons.star,
                                    size: 16,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Text("Stock: ${source.quantity}"),
                          contentPadding: EdgeInsets.zero,
                          onChanged: (val) =>
                              setDialogState(() => selectedSource = val!),
                        );
                      }),

                      if (showSetDefault)
                        CheckboxListTile(
                          value: setAsDefault,
                          activeColor: theme.colorScheme.primary,
                          title: Text(
                            selectedSource == "NEW_PURCHASE"
                                ? "Set 'New Purchase' as default?"
                                : "Set '${selectedSource}' as default?",
                            style: const TextStyle(fontSize: 12),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (val) =>
                              setDialogState(() => setAsDefault = val ?? false),
                        ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  child: Text(
                    "Cancel",
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
                TextButton(
                  child: Text(
                    "Restock",
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: () async {
                    Navigator.pop(context);
                    if (setAsDefault)
                      await _db.setItemDefaultSource(
                        item.name,
                        item.roomLocation,
                        selectedSource,
                      );

                    if (selectedSource == "NEW_PURCHASE") {
                      _db.updateQuantity(
                        item.name,
                        item.roomLocation,
                        newTotal,
                      );
                      _db.logActivity(
                        "RESTOCKED",
                        item.name,
                        item.roomLocation ?? "Unknown",
                        quantityToAdd,
                        newTotal,
                      );
                      _showSnack("Restocked $quantityToAdd ${item.name}");
                    } else {
                      final sourceItem = otherSources.firstWhere(
                        (s) => s.roomLocation == selectedSource,
                      );
                      if (sourceItem.quantity < quantityToAdd) {
                        _showSnack(
                          "Not enough stock in ${sourceItem.roomLocation}!",
                        );
                        return;
                      }
                      _processTransfer(
                        sourceItem,
                        item,
                        quantityToAdd,
                        newTotal,
                      );
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _processTransfer(
    InventoryItem sourceItem,
    InventoryItem targetItem,
    int amount,
    int targetNewTotal,
  ) async {
    int newSourceQty = (sourceItem.quantity - amount).clamp(0, 9999);
    await _db.updateQuantity(
      sourceItem.name,
      sourceItem.roomLocation,
      newSourceQty,
    );
    await _db.updateQuantity(
      targetItem.name,
      targetItem.roomLocation,
      targetNewTotal,
    );

    await _db.logActivity(
      "MOVED TO ${targetItem.roomLocation}",
      sourceItem.name,
      sourceItem.roomLocation ?? "Unknown",
      -amount,
      newSourceQty,
    );
    await _db.logActivity(
      "RESTOCKED (from ${sourceItem.roomLocation})",
      targetItem.name,
      targetItem.roomLocation ?? "Unknown",
      amount,
      targetNewTotal,
    );

    _showSnack(
      "Moved $amount ${targetItem.name} from ${sourceItem.roomLocation} to ${targetItem.roomLocation}",
    );
  }

  // --- EXPORT LOGIC ---

  Future<void> _exportInventoryCSV() async {
    final snapshot = await _db.inventoryCollection.get();
    if (snapshot.docs.isEmpty) return;
    String csvData = "Name,Type,Room Location,Quantity\n";
    for (var doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      String safeName = (data['name'] ?? "").toString().replaceAll(',', '');
      String safeRoom = (data['roomLocation'] ?? "").toString().replaceAll(
        ',',
        '',
      );
      String type = data['type'] ?? "Item";
      String qty = (data['quantity'] ?? 0).toString();
      csvData += "$safeName,$type,$safeRoom,$qty\n";
    }
    await _shareFile(csvData, "axis_inventory.csv");
  }

  Future<void> _exportActivityLogCSV() async {
    final snapshot = await _db.logCollection
        .orderBy('timestamp', descending: true)
        .get();
    if (snapshot.docs.isEmpty) {
      _showSnack("Log is empty!");
      return;
    }
    String csvData = "Timestamp,Action,Item Name,Room,Change,Total\n";
    for (var doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      csvData +=
          "${data['timestamp']},${data['action']},${data['item']},${data['room']},${data['change']},${data['total']}\n";
    }
    await _shareFile(csvData, "axis_activity_log.csv");
  }

  Future<void> _shareFile(String content, String fileName) async {
    if (!mounted) return;
    final directory = await getTemporaryDirectory();
    final path = "${directory.path}/$fileName";
    final file = File(path);
    await file.writeAsString(content);
    await Share.shareXFiles([XFile(path)], text: 'Exported from Axis');
  }

  void _showExportMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      builder: (ctx) => Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.table_view),
            title: const Text("Export Inventory"),
            onTap: () {
              Navigator.pop(ctx);
              _exportInventoryCSV();
            },
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text("Export Logs"),
            onTap: () {
              Navigator.pop(ctx);
              _exportActivityLogCSV();
            },
          ),
        ],
      ),
    );
  }

  void _showAddDialog(List<String> rooms, List<String> existingItemNames) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).cardColor,
          title: Text(
            "Add to Inventory",
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  Icons.meeting_room,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: Text(
                  "Add Room",
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showNameInputDialog(
                    isRoom: true,
                    rooms: rooms,
                    existingItemNames: existingItemNames,
                  );
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.category,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: Text(
                  "Add Item",
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showNameInputDialog(
                    isRoom: false,
                    rooms: rooms,
                    existingItemNames: existingItemNames,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showNameInputDialog({
    required bool isRoom,
    required List<String> rooms,
    required List<String> existingItemNames,
  }) {
    final TextEditingController roomNameController = TextEditingController();
    TextEditingController? autocompleteController;
    String? selectedRoom = (!isRoom && rooms.isNotEmpty) ? rooms.first : null;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Theme(
              data: Theme.of(context),
              child: AlertDialog(
                backgroundColor: Theme.of(context).cardColor,
                title: Text(
                  isRoom ? "New Room" : "New Item",
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isRoom)
                      TextField(
                        controller: roomNameController,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        decoration: InputDecoration(
                          hintText: "Enter Room Name",
                          hintStyle: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    else
                      Autocomplete<String>(
                        optionsBuilder: (TextEditingValue textEditingValue) {
                          if (textEditingValue.text == '')
                            return const Iterable<String>.empty();
                          return existingItemNames.where(
                            (String option) => option.toLowerCase().contains(
                              textEditingValue.text.toLowerCase(),
                            ),
                          );
                        },
                        fieldViewBuilder:
                            (
                              context,
                              textEditingController,
                              focusNode,
                              onFieldSubmitted,
                            ) {
                              autocompleteController = textEditingController;
                              return TextField(
                                controller: textEditingController,
                                focusNode: focusNode,
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                ),
                                decoration: InputDecoration(
                                  hintText: "Enter Item Name",
                                  hintStyle: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              );
                            },
                      ),
                    const SizedBox(height: 20),
                    if (!isRoom) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Select Room:",
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      DropdownButton<String>(
                        value: selectedRoom,
                        dropdownColor: Theme.of(context).cardColor,
                        isExpanded: true,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        items: rooms
                            .map(
                              (String room) => DropdownMenuItem<String>(
                                value: room,
                                child: Text(room),
                              ),
                            )
                            .toList(),
                        onChanged: (String? newValue) =>
                            setState(() => selectedRoom = newValue),
                      ),
                    ],
                  ],
                ),
                actions: [
                  TextButton(
                    child: Text(
                      "Cancel",
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  TextButton(
                    child: Text(
                      "Save",
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () {
                      final String enteredName = isRoom
                          ? roomNameController.text.trim()
                          : (autocompleteController?.text.trim() ?? "");
                      if (enteredName.isNotEmpty) {
                        _addItem(
                          enteredName,
                          isRoom ? "Room" : "Item",
                          selectedRoom,
                        );
                        Navigator.pop(context);
                      }
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showMembersDialog(String householdId) {
    showDialog(
      context: context,
      builder: (ctx) => FutureBuilder<DocumentSnapshot>(
        future: _firestore.collection('households').doc(householdId).get(),
        builder: (context, snap) {
          if (!snap.hasData) return const SizedBox();
          final data = snap.data!.data() as Map<String, dynamic>;
          final ownerId = data['owner'];

          return FutureBuilder<List<Map<String, dynamic>>>(
            future: _db.getHouseholdMembers(householdId),
            builder: (context, membersSnap) {
              if (!membersSnap.hasData)
                return const AlertDialog(
                  content: SizedBox(
                    height: 50,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                );
              final members = membersSnap.data!;

              return AlertDialog(
                title: const Text("Shared With"),
                content: SizedBox(
                  width: double.maxFinite,
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: members.length,
                    separatorBuilder: (c, i) => const Divider(),
                    itemBuilder: (c, i) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(members[i]['displayName']),
                      subtitle: Text(
                        members[i]['uid'] == ownerId
                            ? "Owner"
                            : members[i]['email'],
                      ),
                    ),
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
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final topPadding =
        MediaQuery.of(context).orientation == Orientation.landscape
        ? 20.0
        : 140.0;
    final currentId = _db.currentHouseholdId;

    return StreamBuilder<List<InventoryItem>>(
      stream: _inventoryStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final inventoryList = snapshot.data ?? [];
        final roomList = inventoryList
            .where((element) => element.type == "Room")
            .toList();
        final roomNames = roomList.map((e) => e.name).toList();
        final existingItemNames = inventoryList
            .where((i) => i.type == 'Item')
            .map((i) => i.name)
            .toSet()
            .toList();

        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: FloatingActionButton(
            onPressed: () => _showAddDialog(roomNames, existingItemNames),
            backgroundColor: theme.colorScheme.primary,
            child: const Icon(Icons.add, color: Colors.white),
          ),
          body: Padding(
            padding: EdgeInsets.fromLTRB(20, topPadding, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // NO STREAM BUILDER HERE - USES STATE VARIABLES
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _householdName,
                          style: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        if (_isShared) ...[
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: () => _showMembersDialog(currentId!),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withOpacity(
                                  0.2,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.group,
                                size: 20,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.history,
                            color: theme.iconTheme.color,
                          ),
                          onPressed: () async => await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ActivityLogPage(),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => _showExportMenu(),
                          icon: Icon(
                            Icons.download,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  "Track your items",
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 20),

                Expanded(
                  child: inventoryList.isEmpty
                      ? Center(
                          child: Text(
                            "Click + to add",
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            int crossAxisCount = constraints.maxWidth > 600
                                ? 2
                                : 1;
                            return ListView.builder(
                              padding: EdgeInsets.zero,
                              itemCount: roomList.length,
                              itemBuilder: (context, index) {
                                final room = roomList[index];
                                final roomItems = inventoryList
                                    .where(
                                      (item) =>
                                          item.type == "Item" &&
                                          item.roomLocation == room.name,
                                    )
                                    .toList();
                                final isNotifActive = !_mutedRooms.contains(
                                  room.name,
                                );

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    GestureDetector(
                                      onLongPress: () => _confirmDelete(room),
                                      child: Container(
                                        margin: const EdgeInsets.only(
                                          top: 15,
                                          bottom: 5,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: theme.dividerColor.withOpacity(
                                            0.1,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: theme.dividerColor,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.meeting_room,
                                              color: theme.colorScheme.primary,
                                              size: 20,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              room.name,
                                              style: TextStyle(
                                                color:
                                                    theme.colorScheme.onSurface,
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            if (isNotifActive)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  left: 8.0,
                                                ),
                                                child: Icon(
                                                  Icons.notifications_active,
                                                  size: 14,
                                                  color: theme
                                                      .colorScheme
                                                      .primary
                                                      .withOpacity(0.7),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (roomItems.isEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          left: 20,
                                          bottom: 10,
                                        ),
                                        child: Text(
                                          "No items yet.",
                                          style: TextStyle(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                            fontStyle: FontStyle.italic,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      children: roomItems.map((item) {
                                        double cardWidth = crossAxisCount == 1
                                            ? double.infinity
                                            : (constraints.maxWidth - 10) / 2;
                                        return SizedBox(
                                          width: cardWidth,
                                          child: GestureDetector(
                                            onLongPress: () =>
                                                _confirmDelete(item),
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: theme.cardColor,
                                                borderRadius:
                                                    BorderRadius.circular(15),
                                                border: Border.all(
                                                  color: theme.dividerColor,
                                                ),
                                              ),
                                              child: ListTile(
                                                leading: Container(
                                                  width: 40,
                                                  height: 40,
                                                  alignment: Alignment.center,
                                                  decoration: BoxDecoration(
                                                    color: theme.dividerColor
                                                        .withOpacity(0.2),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: Text(
                                                    "${item.quantity}",
                                                    style: TextStyle(
                                                      color: theme
                                                          .colorScheme
                                                          .primary,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                ),
                                                title: Row(
                                                  children: [
                                                    Icon(
                                                      Icons.category,
                                                      size: 16,
                                                      color: theme
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        item.name,
                                                        style: TextStyle(
                                                          color: theme
                                                              .colorScheme
                                                              .onSurface,
                                                        ),
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                trailing: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    IconButton(
                                                      icon: Icon(
                                                        Icons.remove_circle,
                                                        color: theme
                                                            .colorScheme
                                                            .onSurfaceVariant,
                                                      ),
                                                      onPressed: () =>
                                                          _confirmUseOne(item),
                                                      tooltip: "Use One",
                                                    ),
                                                    IconButton(
                                                      icon: Icon(
                                                        Icons.add,
                                                        color: theme
                                                            .colorScheme
                                                            .onSurfaceVariant,
                                                      ),
                                                      onPressed: () =>
                                                          _showQuantityDialog(
                                                            item,
                                                            inventoryList,
                                                          ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
