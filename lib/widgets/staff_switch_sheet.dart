import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/user_provider.dart';
import '../core/constants.dart';
import 'account_switch_dialog.dart';

class StaffSwitchSheet extends ConsumerWidget {
  const StaffSwitchSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const StaffSwitchSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allUsers = ref.watch(userProvider);
    final currentUser = ref.watch(currentUserProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.l, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.switch_account_rounded, color: AppColors.primaryMaroon),
                SizedBox(width: 12),
                Text('Switch Account', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const Divider(),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: allUsers.length,
              padding: const EdgeInsets.only(bottom: 24),
              itemBuilder: (context, index) {
                final staff = allUsers[index];
                final isCurrent = staff.id == currentUser?.id;

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.l, vertical: 4),
                  leading: Container(
                    width: 45,
                    height: 45,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isCurrent ? AppColors.primaryMaroon : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: ClipOval(
                      child: staff.photoUrl != null && staff.photoUrl!.isNotEmpty
                          ? Image.network(staff.photoUrl!, fit: BoxFit.cover)
                          : Container(
                              color: Colors.grey.shade200,
                              child: Icon(Icons.person, color: Colors.grey.shade400),
                            ),
                    ),
                  ),
                  title: Text(staff.name, style: TextStyle(fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
                  subtitle: Text(staff.role.toString().split('.').last.toUpperCase(), style: const TextStyle(fontSize: 10, letterSpacing: 0.5)),
                  trailing: isCurrent 
                      ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                      : const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                  onTap: isCurrent ? null : () async {
                    final navigator = Navigator.of(context);
                    navigator.pop(); // Close bottom sheet
                    final success = await AccountSwitchDialog.show(context, staff);
                    if (success == true && context.mounted) {
                      // Refresh to apply new user's dashboard
                      navigator.pushReplacementNamed('/');
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
