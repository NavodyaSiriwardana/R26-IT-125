import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'local_storage.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ─────────────────────────────────────
  // REGISTER
  // ─────────────────────────────────────

  static Future<bool> register({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth
          .createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final uid = credential.user!.uid;

      // Save user profile to Firestore
      await _db.collection('users').doc(uid).set({
        'name': name,
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Save to local storage — this becomes userId
      await LocalStorage.saveUserData(
        userId: uid,
        token: uid,
        name: name,
        email: email,
      );

      print('[AuthService] Registered: $uid');
      return true;

    } on FirebaseAuthException catch (e) {
      print('[AuthService] Register error: ${e.message}');
      return false;
    } catch (e) {
      print('[AuthService] Register error: $e');
      return false;
    }
  }

  // ─────────────────────────────────────
  // LOGIN
  // ─────────────────────────────────────

  static Future<bool> login({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth
          .signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final uid = credential.user!.uid;

      // Fetch user profile from Firestore
      final doc = await _db
          .collection('users')
          .doc(uid)
          .get();

      final name = doc.data()?['name'] ?? '';

      // Save to local storage — this becomes userId
      await LocalStorage.saveUserData(
        userId: uid,
        token: uid,
        name: name,
        email: email,
      );

      print('[AuthService] Login success: $uid');
      return true;

    } on FirebaseAuthException catch (e) {
      print('[AuthService] Login error: ${e.message}');
      return false;
    } catch (e) {
      print('[AuthService] Login error: $e');
      return false;
    }
  }

  // ─────────────────────────────────────
  // LOGOUT
  // ─────────────────────────────────────

  static Future<void> logout() async {
    await _auth.signOut();
    await LocalStorage.clearAll();
  }

  // ─────────────────────────────────────
  // CHECK CURRENT USER
  // ─────────────────────────────────────

  static bool isLoggedIn() {
    return _auth.currentUser != null;
  }
}