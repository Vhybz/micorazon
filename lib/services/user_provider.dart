import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/user_model.dart';
import 'supabase_user_service.dart';
import 'sms_service.dart';

class UserNotifier extends StateNotifier<List<UserAccount>> {
  final SupabaseUserService service;
  final Ref ref;
  StreamSubscription? _subscription;
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  UserNotifier(this.service, this.ref) : super([]) {
    _init();
  }

  void _init() {
    _startHeartbeat();
    _startSubscription();
  }

  void _startSubscription() {
    _subscription?.cancel();
    _subscription = service.watchUsers().listen(
      (users) {
        final currentUser = ref.read(sessionUserProfileProvider);
        List<UserAccount> filteredUsers = users;
        
        if (currentUser?.role != UserRole.superAdmin && currentUser?.branchCode != null) {
          filteredUsers = users.where((u) => u.branchCode == currentUser!.branchCode).toList();
        }
        
        state = filteredUsers;
        
        // Update session profile if current user is in the list
        final currentId = ref.read(currentUserIdProvider);
        if (currentId != null) {
          final oldMe = ref.read(sessionUserProfileProvider);
          final me = users.where((u) => u.id == currentId).firstOrNull;
          if (me != null) {
            // SECURITY: If passcode changed remotely (e.g. by admin), lock the account immediately
            if (oldMe != null && (me.passcode != oldMe.passcode || me.passcodeSentAt != oldMe.passcodeSentAt)) {
              ref.read(passcodeUnlockedProvider.notifier).state = false;
            }
            ref.read(sessionUserProfileProvider.notifier).state = me;
          }
        }
      }, 
      onError: (e) {
        debugPrint('User Stream Connection Error (Resuming?): $e');
      },
      cancelOnError: false,
    );
  }

  void _startHeartbeat() {
    ref.listen(liveHeartbeatProvider, (previous, next) {
      final currentId = ref.read(currentUserIdProvider);
      if (currentId != null) {
        // Every 30 seconds (10 ticks of 3s heartbeat), update last seen in DB
        if (next.value != null && next.value! % 10 == 0) {
          updateLastSeen(currentId);
          // Also refresh the user list to see other people's online status
          loadUsers(silent: true);
        }
      }
    });
  }

  Future<void> updateLastSeen(String userId) async {
    try {
      final now = DateTime.now();
      await service.updateUserFields(userId, {'last_seen': now.toIso8601String()});
      
      // Update local state if the user is in our list
      final user = await _getUser(userId);
      if (user != null) {
        _updateLocalAndSession(user.copyWith(lastSeen: now));
      }
    } catch (e) {
      debugPrint('Heartbeat Error: $e');
    }
  }

  // Centralized method to update local state and notify session listeners
  void _updateLocalAndSession(UserAccount updatedUser) {
    // 1. Update the main list state
    state = [
      for (final u in state)
        if (u.id == updatedUser.id) updatedUser else u
    ];

    // 2. If this is the currently logged-in user, update their session profile instantly
    if (updatedUser.id == ref.read(currentUserIdProvider)) {
      ref.read(sessionUserProfileProvider.notifier).state = updatedUser;
    }
  }

  Future<void> loadUsers({bool silent = false}) async {
    if (_isLoading) return;
    try {
      if (!silent) {
        _isLoading = true;
        // Notify UI about loading state via a dedicated provider
        Future.microtask(() => ref.read(userLoadingProvider.notifier).state = true);
      }
      
      final currentId = ref.read(currentUserIdProvider);
      if (currentId == null) return;

      final currentUser = await service.getUserById(currentId);
      
      // Update session profile only if it changed to avoid unnecessary rebuilds
      if (currentUser != null) {
        final existing = ref.read(sessionUserProfileProvider);
        if (existing == null || existing.id != currentUser.id || existing.lastSeen != currentUser.lastSeen) {
          ref.read(sessionUserProfileProvider.notifier).state = currentUser;
        }
      }

      final allUsers = await service.getUsers();
      List<UserAccount> filteredUsers = allUsers;
      
      if (currentUser?.role != UserRole.superAdmin && currentUser?.branchCode != null) {
        filteredUsers = allUsers.where((u) => u.branchCode == currentUser!.branchCode).toList();
      }
      
      // Update state if the list is different. 
      // We use reference equality check for simplicity, or we could do a better check.
      // Simply assigning it will trigger listeners.
      state = filteredUsers;
    } catch (e) {
      debugPrint('Load Users Error: $e');
    } finally {
      _isLoading = false;
      if (!silent) {
        Future.microtask(() => ref.read(userLoadingProvider.notifier).state = false);
      }
    }
  }

  Future<void> addAccount(UserAccount account) async {
    try {
      debugPrint('Attempting to add user profile to database: ${account.id}');
      await service.addUser(account);
      state = [...state, account];
      debugPrint('User profile saved successfully.');
    } catch (e) {
      debugPrint('DATABASE ERROR (addUser): $e');
      rethrow;
    }
  }

  Future<void> updateProfile(String userId, {String? firstName, String? surname, String? phone, String? gender, DateTime? dob, String? branchCode}) async {
    try {
      final user = await _getUser(userId);
      if (user != null) {
        final updatedUser = user.copyWith(
          firstName: firstName,
          surname: surname,
          phone: phone,
          gender: gender,
          dob: dob,
          branchCode: branchCode,
        );
        
        final connectivity = await Connectivity().checkConnectivity();
        if (!connectivity.contains(ConnectivityResult.none)) {
          await service.updateUser(updatedUser);
        } else {
          _updateLocalAndSession(updatedUser);
          await service.updateUser(updatedUser); 
        }
      }
    } catch (e) {
      debugPrint('Profile Update Error: $e');
    }
  }

  Future<void> updateRoles(String userId, {UserRole? primaryRole, List<UserRole>? secondaryRoles}) async {
    try {
      final user = await _getUser(userId);
      if (user != null) {
        final updatedUser = user.copyWith(
          role: primaryRole,
          secondaryRoles: secondaryRoles,
        );
        _updateLocalAndSession(updatedUser); // Instant UI Update
        await service.updateUser(updatedUser);
      }
    } catch (e) {
      debugPrint('Role Update Error: $e');
    }
  }

  Future<void> approveUser(String userId) async {
    try {
      final user = await _getUser(userId);
      if (user != null) {
        final updatedUser = user.copyWith(status: AccountStatus.approved);
        _updateLocalAndSession(updatedUser);
        await service.updateUser(updatedUser);
        
        // Notify approved user via SMS
        await SmsService.sendApprovalSms(updatedUser);
      }
    } catch (e) {
      debugPrint('Approve User Error: $e');
    }
  }

  Future<void> suspendUser(String userId) async {
    try {
      final user = await _getUser(userId);
      if (user != null) {
        final updatedUser = user.copyWith(status: AccountStatus.suspended);
        _updateLocalAndSession(updatedUser);
        await service.updateUser(updatedUser);
      }
    } catch (e) {
      debugPrint('Suspend User Error: $e');
    }
  }

  Future<void> deleteUser(String userId) async {
    try {
      // 1. Attempt absolute hard delete (wipes from database)
      await service.hardDeleteUser(userId);
      
      // 2. Remove from local list
      state = state.where((u) => u.id != userId).toList();
    } catch (e) {
      debugPrint('Hard Delete failed, attempting Ghost Delete fallback: $e');
      try {
        // Fallback: If hard delete fails (usually due to sales history),
        // we use a "Ghost Delete" where we mark it as deleted and hide it everywhere.
        await service.deleteUser(userId); // Sets is_deleted = true
        state = state.where((u) => u.id != userId).toList();
      } catch (innerErr) {
        debugPrint('Ghost Delete fallback failed: $innerErr');
        rethrow;
      }
    }
  }

  Future<void> activateUser(String userId) async {
    try {
      final user = await _getUser(userId);
      if (user != null) {
        final updatedUser = user.copyWith(status: AccountStatus.approved);
        _updateLocalAndSession(updatedUser);
        await service.updateUser(updatedUser);
      }
    } catch (e) {
      debugPrint('Activate User Error: $e');
    }
  }

  Future<void> setPermissions(String userId, Set<String> permissions) async {
    try {
      final user = await _getUser(userId);
      if (user != null) {
        final updatedUser = user.copyWith(
          newlyAddedPermissions: permissions.difference(user.enabledPermissions),
          enabledPermissions: permissions,
        );
        _updateLocalAndSession(updatedUser); // Instant UI Update
        await service.updateUser(updatedUser);
      }
    } catch (e) {
      debugPrint('Set Permissions Error: $e');
    }
  }

  Future<void> updateSalary(String userId, {
    double? amount, 
    int? day, 
    DateTime? lastPaid, 
    bool? isAdvance,
    double? addSalaryPaid,
    double? addAdvanceTaken,
  }) async {
    try {
      final user = await _getUser(userId);
      if (user != null) {
        // We still update the local state so the UI looks correct
        final updatedUser = user.copyWith(
          salaryAmount: amount,
          salaryDay: day,
          lastSalaryDate: lastPaid,
          lastPaymentWasAdvance: isAdvance,
          totalSalaryPaid: user.totalSalaryPaid + (addSalaryPaid ?? 0),
          totalAdvancesTaken: user.totalAdvancesTaken + (addAdvanceTaken ?? 0),
        );
        
        _updateLocalAndSession(updatedUser);
        
        // We only send columns that Supabase API definitely recognizes
        final Map<String, dynamic> updates = {
          'salary_amount': amount,
          'salary_day': day,
          'total_salary_paid': updatedUser.totalSalaryPaid,
          'total_advances_taken': updatedUser.totalAdvancesTaken,
        };
        
        if (lastPaid != null) {
          updates['last_salary_date'] = "${lastPaid.year}-${lastPaid.month.toString().padLeft(2, '0')}-${lastPaid.day.toString().padLeft(2, '0')}";
        }
        
        if (isAdvance != null) {
          updates['last_payment_was_advance'] = isAdvance;
        }

        await service.updateUserFields(userId, updates);
      }
    } catch (e) {
      debugPrint('Update Salary Error: $e');
      rethrow;
    }
  }

  Future<void> updateTheme(String userId, {String? mode, int? color}) async {
    try {
      final user = await _getUser(userId);
      if (user != null) {
        final updatedUser = user.copyWith(
          themeMode: mode,
          themePrimaryColor: color,
        );
        _updateLocalAndSession(updatedUser);
        await service.updateUser(updatedUser);
      }
    } catch (e) {
      debugPrint('Update Theme Error: $e');
    }
  }

  Future<String?> updatePhoto(String userId, Uint8List bytes) async {
    try {
      final url = await service.uploadProfilePicture(userId, bytes);
      if (url != null) {
        final user = await _getUser(userId);
        if (user != null) {
          final updatedUser = user.copyWith(photoUrl: url);
          _updateLocalAndSession(updatedUser);
          await service.updateUser(updatedUser);
        }
      }
      return url;
    } catch (e) {
      debugPrint('Update Photo Error: $e');
      return null;
    }
  }

  Future<void> markPermissionAsSeen(String userId, String permission) async {
    try {
      final user = await _getUser(userId);
      if (user != null && user.newlyAddedPermissions.contains(permission)) {
        final updatedUser = user.copyWith(
          newlyAddedPermissions: (Set.from(user.newlyAddedPermissions)..remove(permission)),
        );
        _updateLocalAndSession(updatedUser);
        await service.updateUser(updatedUser);
      }
    } catch (e) {
      debugPrint('Mark Permission Error: $e');
    }
  }

  Future<void> promoteTemporarily(String userId, UserRole tempRole, DateTime start, DateTime end) async {
    try {
      final user = await _getUser(userId);
      if (user != null) {
        final updatedUser = user.copyWith(
          temporaryRole: tempRole, 
          tempRoleStart: start, 
          tempRoleEnd: end
        );
        _updateLocalAndSession(updatedUser);
        await service.updateUser(updatedUser);
      }
    } catch (e) {
      debugPrint('Promote Error: $e');
    }
  }

  Future<void> clearTemporaryPromotion(String userId) async {
    try {
      final user = await _getUser(userId);
      if (user != null) {
        final updatedUser = user.copyWith(clearPromotion: true);
        _updateLocalAndSession(updatedUser);
        await service.updateUser(updatedUser);
      }
    } catch (e) {
      debugPrint('Clear Promotion Error: $e');
    }
  }

  Future<void> togglePermission(String userId, String permission) async {
    try {
      final user = await _getUser(userId);
      if (user != null) {
        final updatedUser = user.copyWith(
          enabledPermissions: user.enabledPermissions.contains(permission)
              ? (Set.from(user.enabledPermissions)..remove(permission))
              : (Set.from(user.enabledPermissions)..add(permission)),
        );
        _updateLocalAndSession(updatedUser);
        await service.updateUser(updatedUser);
      }
    } catch (e) {
      debugPrint('Toggle Permission Error: $e');
    }
  }

  Future<void> updatePasscode(String userId, String passcode) async {
    try {
      final user = await _getUser(userId);
      if (user != null) {
        final now = DateTime.now();
        final updatedUser = user.copyWith(passcode: passcode, passcodeSentAt: now);
        
        // SECURITY: If updating current user's PIN, lock immediately
        if (userId == ref.read(currentUserIdProvider)) {
          ref.read(passcodeUnlockedProvider.notifier).state = false;
        }

        _updateLocalAndSession(updatedUser);
        await service.updateUserFields(userId, {
          'passcode': passcode,
          'passcode_sent_at': now.toIso8601String(),
        });
      }
    } catch (e) {
      debugPrint('Update Passcode Error: $e');
      rethrow;
    }
  }

  // Helper to find a user even if they aren't in the currently filtered state list
  Future<UserAccount?> _getUser(String id) async {
    try {
      return state.firstWhere((u) => u.id == id);
    } catch (_) {
      return await service.getUserById(id);
    }
  }

  Future<UserAccount?> fetchUserById(String id) async {
    try {
      final user = await service.getUserById(id);
      if (user != null) {
        state = [...state.where((u) => u.id != id), user];
      }
      return user;
    } catch (e) {
      debugPrint('Fetch User Error: $e');
      return null;
    }
  }

  Future<bool> checkPhoneExists(String phone) async {
    return await service.checkPhoneExists(phone);
  }

  Future<bool> checkIfAnyAdminExists() async {
    try {
      final allUsers = await service.getUsers();
      // Any approved admin or superAdmin counts as an existing administrator
      return allUsers.any((u) => 
        (u.role == UserRole.admin || u.role == UserRole.superAdmin) && 
        u.status == AccountStatus.approved &&
        !u.isDeleted
      );
    } catch (e) {
      return false;
    }
  }

  List<UserAccount> getPendingUsers() {
    return state.where((u) => !u.isDeleted && u.status == AccountStatus.pending).toList();
  }

  List<UserAccount> getCashiers() {
    return state.where((u) => !u.isDeleted && u.role == UserRole.cashier && u.status == AccountStatus.approved).toList();
  }

  bool get isAdminExists => state.any((u) => 
    (u.role == UserRole.admin || u.role == UserRole.superAdmin) && 
    u.status == AccountStatus.approved &&
    !u.isDeleted
  );
}

final userServiceProvider = Provider<SupabaseUserService>((ref) {
  return SupabaseUserService();
});

// Real logged-in user tracking
final currentUserIdProvider = StateProvider<String?>((ref) => null);

// This holds the currently logged-in user's profile and is updated instantly locally
final sessionUserProfileProvider = StateProvider<UserAccount?>((ref) => null);

/// A session-based state provider to track if the current user has unlocked the system
final passcodeUnlockedProvider = StateProvider<bool>((ref) => false);

/// A global state provider for Emergency System Lockdown
final systemLockdownProvider = StateProvider<bool>((ref) => false);

/// Listens for real-time changes to the current user's profile from the database
final currentUserStreamProvider = StreamProvider<UserAccount?>((ref) {
  final id = ref.watch(currentUserIdProvider);
  if (id == null) return const Stream.empty();
  
  return ref.watch(userServiceProvider).streamUser(id).handleError((error) {
    debugPrint('Real-time User Profile Stream Error (Normal on background): $error');
  });
});

/// A synchronous provider that gives access to the current user profile.
/// It prioritizes the manual session state for instant UI updates.
final currentUserProvider = Provider<UserAccount?>((ref) {
  final currentId = ref.watch(currentUserIdProvider);
  if (currentId == null) return null;

  // 1. Check the manual session state first (updated instantly by UserNotifier)
  final sessionUser = ref.watch(sessionUserProfileProvider);
  
  // 2. Check the real-time stream (source of truth for remote updates)
  final streamUser = ref.watch(currentUserStreamProvider).value;
  
  // Prioritize sessionUser for instant feedback, then streamUser, then fallback to current list
  if (sessionUser != null) return sessionUser;
  if (streamUser != null) return streamUser;

  try {
    return ref.watch(userProvider).firstWhere((u) => u.id == currentId);
  } catch (_) {
    return null;
  }
});

final userProvider = StateNotifierProvider<UserNotifier, List<UserAccount>>((ref) {
  return UserNotifier(ref.watch(userServiceProvider), ref);
});

final userLoadingProvider = StateProvider<bool>((ref) => false);

/// A heartbeat provider that triggers every 3 seconds to keep things "live"
final liveHeartbeatProvider = StreamProvider<int>((ref) {
  return Stream.periodic(const Duration(seconds: 3), (count) => count);
});
