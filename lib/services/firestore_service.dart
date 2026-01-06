import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/inventory_item.dart';

class FirestoreService {
  static final FirestoreService _instance = FirestoreService._internal();
  factory FirestoreService() => _instance;
  FirestoreService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _currentHouseholdId;
  final _householdIdController = StreamController<String?>.broadcast();
  Stream<String?> get currentHouseholdIdStream => _householdIdController.stream;

  User? get currentUser => _auth.currentUser;
  String? get currentHouseholdId => _currentHouseholdId;

  // --- INIT ---
  Future<void> init() async {
    if (currentUser == null) return;
    DocumentSnapshot userDoc = await _db
        .collection('users')
        .doc(currentUser!.uid)
        .get();

    if (userDoc.exists && userDoc.data() != null) {
      Map<String, dynamic> data = userDoc.data() as Map<String, dynamic>;
      _currentHouseholdId = data['currentHouseholdId'];
    }

    if (_currentHouseholdId == null) {
      await createHousehold("My Inventory");
    } else {
      _householdIdController.add(_currentHouseholdId);
    }
  }

  // --- USER PROFILE ---
  Future<void> updateDisplayName(String name) async {
    if (currentUser == null) return;
    await _db.collection('users').doc(currentUser!.uid).update({
      'displayName': name,
    });
    await currentUser!.updateDisplayName(name);
  }

  // --- MEMBER MANAGEMENT ---
  Future<void> removeMember(String householdId, String userId) async {
    await _db.collection('households').doc(householdId).update({
      'members': FieldValue.arrayRemove([userId]),
    });
    await _db.collection('users').doc(userId).update({
      'joinedHouseholds': FieldValue.arrayRemove([householdId]),
    });
  }

  Future<List<Map<String, dynamic>>> getHouseholdMembers(
    String householdId,
  ) async {
    DocumentSnapshot houseDoc = await _db
        .collection('households')
        .doc(householdId)
        .get();
    List<dynamic> memberIds = houseDoc.get('members') ?? [];

    List<Map<String, dynamic>> members = [];
    for (String uid in memberIds) {
      DocumentSnapshot userDoc = await _db.collection('users').doc(uid).get();
      if (userDoc.exists) {
        members.add({
          'uid': uid,
          'displayName': userDoc.get('displayName') ?? 'Unknown',
          'email': userDoc.get('email') ?? '',
        });
      }
    }
    return members;
  }

  // --- INVITATION SYSTEM ---
  Future<void> sendInviteByEmail(String email) async {
    if (currentUser == null || _currentHouseholdId == null) return;

    QuerySnapshot query = await _db
        .collection('users')
        .where('email', isEqualTo: email.trim())
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      throw Exception("No account found with email: $email");
    }

    String recipientUid = query.docs.first.id;
    DocumentSnapshot houseDoc = await _db
        .collection('households')
        .doc(_currentHouseholdId)
        .get();
    String houseName = houseDoc.get('name');

    await _db
        .collection('users')
        .doc(recipientUid)
        .collection('invitations')
        .add({
          'householdId': _currentHouseholdId,
          'householdName': houseName,
          'inviterName': currentUser!.displayName ?? currentUser!.email,
          'timestamp': FieldValue.serverTimestamp(),
        });
  }

  Stream<List<Map<String, dynamic>>> getInvitationsStream() {
    if (currentUser == null) return Stream.value([]);
    return _db
        .collection('users')
        .doc(currentUser!.uid)
        .collection('invitations')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs.map((d) => {...d.data(), 'id': d.id}).toList(),
        );
  }

  Future<void> acceptInvitation(String inviteId, String householdId) async {
    if (currentUser == null) return;
    await _db.collection('households').doc(householdId).update({
      'members': FieldValue.arrayUnion([currentUser!.uid]),
    });
    await _db.collection('users').doc(currentUser!.uid).update({
      'joinedHouseholds': FieldValue.arrayUnion([householdId]),
    });
    await switchHousehold(householdId);
    await _db
        .collection('users')
        .doc(currentUser!.uid)
        .collection('invitations')
        .doc(inviteId)
        .delete();
  }

  Future<void> declineInvitation(String inviteId) async {
    if (currentUser == null) return;
    await _db
        .collection('users')
        .doc(currentUser!.uid)
        .collection('invitations')
        .doc(inviteId)
        .delete();
  }

  // --- HOUSEHOLD MANAGEMENT ---
  Future<void> createHousehold(String name) async {
    if (currentUser == null) return;
    DocumentReference householdRef = await _db.collection('households').add({
      'name': name,
      'owner': currentUser!.uid,
      'members': [currentUser!.uid],
      'createdAt': FieldValue.serverTimestamp(),
    });
    await switchHousehold(householdRef.id);
  }

  Future<void> switchHousehold(String householdId) async {
    if (currentUser == null) return;
    _currentHouseholdId = householdId;
    _householdIdController.add(householdId);
    await _db.collection('users').doc(currentUser!.uid).set({
      'currentHouseholdId': householdId,
      'joinedHouseholds': FieldValue.arrayUnion([householdId]),
      'email': currentUser!.email,
    }, SetOptions(merge: true));
  }

  // --- CORE DATA ---
  void _ensureHousehold() {
    if (_currentHouseholdId == null) throw Exception("No Inventory Selected");
  }

  CollectionReference get inventoryCollection {
    _ensureHousehold();
    return _db
        .collection('households')
        .doc(_currentHouseholdId)
        .collection('inventory');
  }

  CollectionReference get logCollection {
    _ensureHousehold();
    return _db
        .collection('households')
        .doc(_currentHouseholdId)
        .collection('activity_log');
  }

  Stream<List<InventoryItem>> getInventoryStream() {
    if (_currentHouseholdId == null) return Stream.value([]);
    return inventoryCollection.snapshots().map((snapshot) {
      return snapshot.docs
          .map(
            (doc) => InventoryItem.fromJson(doc.data() as Map<String, dynamic>),
          )
          .toList();
    });
  }

  Stream<List<Map<String, dynamic>>> getLogStream() {
    if (_currentHouseholdId == null) return Stream.value([]);
    return logCollection
        .orderBy('timestamp', descending: true)
        .limit(500)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            data['id'] = doc.id;
            return data;
          }).toList();
        });
  }

  // --- ID HELPER ---
  String _generateId(String name, String? room) {
    String cleanName = name.trim().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    String cleanRoom = (room ?? "None").trim().replaceAll(
      RegExp(r'[^a-zA-Z0-9]'),
      '',
    );
    return "${cleanName}_$cleanRoom";
  }

  Future<DocumentReference> _getItemRef(String name, String? room) async {
    String compositeId = _generateId(name, room);
    DocumentReference ref = inventoryCollection.doc(compositeId);
    DocumentSnapshot doc = await ref.get();
    if (doc.exists) return ref;

    DocumentReference oldRef = inventoryCollection.doc(name);
    DocumentSnapshot oldDoc = await oldRef.get();
    if (oldDoc.exists) return oldRef;

    return ref;
  }

  Future<void> addItem(InventoryItem item) async {
    String id = _generateId(item.name, item.roomLocation);
    await inventoryCollection.doc(id).set(item.toJson());
  }

  Future<void> updateQuantity(String name, String? room, int q) async {
    DocumentReference ref = await _getItemRef(name, room);
    await ref.update({'quantity': q});
  }

  // NEW: Update default source preference
  Future<void> setItemDefaultSource(
    String name,
    String? room,
    String source,
  ) async {
    DocumentReference ref = await _getItemRef(name, room);
    await ref.update({'defaultSource': source});
  }

  Future<void> deleteItem(String name, String? room) async {
    DocumentReference ref = await _getItemRef(name, room);
    await ref.delete();
  }

  Future<void> deleteRoom(String roomName) async {
    final items = await inventoryCollection
        .where('roomLocation', isEqualTo: roomName)
        .get();
    final batch = _db.batch();
    DocumentReference roomRef = await _getItemRef(roomName, null);
    batch.delete(roomRef);
    for (var doc in items.docs) batch.delete(doc.reference);
    await batch.commit();
  }

  Future<void> logActivity(
    String action,
    String item,
    String room,
    dynamic change,
    dynamic total,
  ) async {
    await logCollection.add({
      'timestamp': DateTime.now().toIso8601String(),
      'action': action,
      'item': item,
      'room': room,
      'change': change,
      'total': total,
      'user': currentUser?.displayName ?? currentUser?.email ?? 'Unknown',
    });
  }

  Future<void> updateLogEntry(String id, Map<String, dynamic> updates) async =>
      await logCollection.doc(id).update(updates);
  Future<void> deleteLogEntry(String id) async =>
      await logCollection.doc(id).delete();

  Future<void> batchImportLogs(List<String> lines) async {
    final batch = _db.batch();
    for (var line in lines) {
      List<String> p = line.split('|');
      if (p.length >= 6) {
        batch.set(logCollection.doc(), {
          'timestamp': p[0],
          'action': p[1],
          'item': p[2],
          'room': p[3],
          'change': num.tryParse(p[4]) ?? 0,
          'total': num.tryParse(p[5]) ?? 0,
          'user': 'Imported',
        });
      }
    }
    await batch.commit();
  }
}
