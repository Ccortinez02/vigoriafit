import 'package:shared_preferences/shared_preferences.dart';

/// Every read and write is bound to an immutable UID, including in-flight writes.
/// Legacy brio_* keys are deliberately never read or automatically migrated.
class AccountPreferences {
  final SharedPreferences storage;
  final String uid;
  AccountPreferences(this.storage, this.uid) {
    if (uid.isEmpty) throw ArgumentError('An authenticated UID is required');
  }
  String _key(String key) => 'vigoria_v2_${Uri.encodeComponent(uid)}_$key';
  String? getString(String key) => storage.getString(_key(key));
  bool? getBool(String key) => storage.getBool(_key(key));
  int? getInt(String key) => storage.getInt(_key(key));
  List<String>? getStringList(String key) => storage.getStringList(_key(key));
  Future<bool> setString(String key, String value) =>
      storage.setString(_key(key), value);
  Future<bool> setBool(String key, bool value) =>
      storage.setBool(_key(key), value);
  Future<bool> setInt(String key, int value) =>
      storage.setInt(_key(key), value);
  Future<bool> setStringList(String key, List<String> value) =>
      storage.setStringList(_key(key), value);
  Future<bool> remove(String key) => storage.remove(_key(key));

  /// Elimina todas las claves de SharedPreferences que pertenecen a este usuario.
  Future<void> clearAll() async {
    final prefix = 'vigoria_v2_${Uri.encodeComponent(uid)}_';
    final keys = storage.getKeys().where((k) => k.startsWith(prefix)).toList();
    for (final k in keys) {
      await storage.remove(k);
    }
  }
}
