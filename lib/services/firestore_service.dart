import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/inventory_item.dart';

class FirestoreService {
  String? get userId => FirebaseAuth.instance.currentUser?.uid;

  // --- COLLECTIONS ---
  CollectionReference get inventoryCollection {
    if (userId == null) throw Exception("User not logged in");
    return FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('inventory');
  }

  CollectionReference get logCollection {
    if (userId == null) throw Exception("User not logged in");
    return FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('activity_log');
  }

  // --- STREAMS ---

  Stream<List<InventoryItem>> getInventoryStream() {
    return inventoryCollection.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        return InventoryItem.fromJson(data);
      }).toList();
    });
  }

  // UPDATED: Now includes Document ID and fetches 500 items
  Stream<List<Map<String, dynamic>>> getLogStream() {
    return logCollection
        .orderBy('timestamp', descending: true)
        .limit(500) // Increased limit
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            data['id'] = doc.id; // INJECT ID
            return data;
          }).toList();
        });
  }

  // --- ACTIONS ---

  Future<void> addItem(InventoryItem item) async {
    await inventoryCollection.doc(item.name).set(item.toJson());
  }

  Future<void> updateQuantity(String itemName, int newQuantity) async {
    await inventoryCollection.doc(itemName).update({'quantity': newQuantity});
  }

  Future<void> deleteItem(String itemName) async {
    await inventoryCollection.doc(itemName).delete();
  }

  Future<void> deleteRoom(String roomName) async {
    await inventoryCollection.doc(roomName).delete();
    final itemsInRoom = await inventoryCollection
        .where('roomLocation', isEqualTo: roomName)
        .where('type', isEqualTo: 'Item')
        .get();

    final batch = FirebaseFirestore.instance.batch();
    for (var doc in itemsInRoom.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  Future<void> logActivity(
    String action,
    String item,
    String room,
    int change,
    int total,
  ) async {
    await logCollection.add({
      'timestamp': DateTime.now().toIso8601String(),
      'action': action,
      'item': item,
      'room': room,
      'change': change,
      'total': total,
      'note': '', // Initialize empty note
    });
  }

  // NEW: Update Log
  Future<void> updateLogEntry(String id, Map<String, dynamic> updates) async {
    await logCollection.doc(id).update(updates);
  }

  // NEW: Delete Log
  Future<void> deleteLogEntry(String id) async {
    await logCollection.doc(id).delete();
  }

  Future<void> batchImportLogs(List<String> csvLines) async {
    final batch = FirebaseFirestore.instance.batch();
    for (var line in csvLines) {
      List<String> parts = line.split('|');
      if (parts.length >= 6) {
        DocumentReference docRef = logCollection.doc();
        batch.set(docRef, {
          'timestamp': parts[0],
          'action': parts[1],
          'item': parts[2],
          'room': parts[3],
          'change': int.tryParse(parts[4]) ?? 0,
          'total': int.tryParse(parts[5]) ?? 0,
          'note': parts.length > 6 ? parts[6] : '', // Capture note if exists
        });
      }
    }
    await batch.commit();
  }
}
