import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitalpath/models/user_profile_model.dart';

class UserProfileService {
  static const _profileKey = 'user_profile_v2';

  static UserProfileService? _instance;
  factory UserProfileService() =>
      _instance ??= UserProfileService._internal();
  UserProfileService._internal();

  UserProfileModel? _cached;

  Future<UserProfileModel?> getProfile() async {
    if (_cached != null) return _cached;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profileKey);
    if (raw == null) return null;
    try {
      _cached = UserProfileModel.fromJsonString(raw);
      return _cached;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveProfile(UserProfileModel profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileKey, profile.toJsonString());
    _cached = profile;
  }

  Future<UserRole?> getRole() async {
    final p = await getProfile();
    return p?.role;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_profileKey);
    _cached = null;
  }
}
