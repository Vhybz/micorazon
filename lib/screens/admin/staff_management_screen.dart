import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants.dart';
import '../../services/user_provider.dart';
import '../../models/user_model.dart';
import '../../widgets/main_app_bar.dart';

import '../../widgets/responsive_layout.dart';
import '../../widgets/app_sidebar.dart';
import '../../services/menu_service.dart';
import '../../models/branch_model.dart';
import '../../services/branch_provider.dart';
import '../../widgets/role_pop_scope.dart';
import '../../services/sms_service.dart';
import '../../widgets/passcode_guard.dart';

class StaffManagementScreen extends ConsumerStatefulWidget {
  const StaffManagementScreen({super.key});

  @override
  ConsumerState<StaffManagementScreen> createState() => _StaffManagementScreenState();
}

class _StaffManagementScreenState extends ConsumerState<StaffManagementScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(userProvider.notifier).loadUsers());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final theme = Theme.of(context);
    final users = ref.watch(userProvider);
    final isLoading = ref.watch(userLoadingProvider);
    final branchesAsync = ref.watch(branchesProvider);
    
    // Filtering logic
    final filteredUsers = users.where((u) {
      final query = _searchQuery.toLowerCase();
      return u.name.toLowerCase().contains(query) || 
             u.email.toLowerCase().contains(query) || 
             (u.phone?.contains(query) ?? false);
    }).toList();

    final pendingUsers = filteredUsers.where((u) => u.status == AccountStatus.pending).toList();
    final approvedUsers = filteredUsers.where((u) => u.status != AccountStatus.pending).toList();
    
    final isDesktop = ResponsiveLayout.isDesktop(context);
    const currentRoute = '/admin/staff';

    return RolePopScope(
      currentRoute: currentRoute,
      child: PasscodeGuard(
        child: Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          appBar: const MainAppBar(title: 'Staff Management', showMenuButton: true),
          drawer: isDesktop
              ? null
              : Drawer(
                  child: AppSidebar(
                    userId: user.id,
                    userName: user.name,
                    userRole: user.activePrimaryRole.toString().split('.').last.toUpperCase(),
                    currentRoute: currentRoute,
                    items: MenuService.getMenuItemsForUser(user),
                    onTap: (route) => MenuService.navigate(context, route, currentRoute),
                  ),
                ),
          body: Row(
            children: [
              if (isDesktop)
                AppSidebar(
                  userId: user.id,
                  userName: user.name,
                  userRole: user.activePrimaryRole.toString().split('.').last.toUpperCase(),
                  currentRoute: currentRoute,
                  items: MenuService.getMenuItemsForUser(user),
                  onTap: (route) => MenuService.navigate(context, route, currentRoute),
                ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => ref.read(userProvider.notifier).loadUsers(),
                  child: CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.all(AppSpacing.l),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate([
                            _buildHeader(context, ref),
                            const SizedBox(height: AppSpacing.m),
                            _buildSearchBar(context),
                            const SizedBox(height: AppSpacing.m),
                            _buildSummaryInfo(context, users, pendingUsers),
                            const SizedBox(height: AppSpacing.l),
                          ]),
                        ),
                      ),

                      if (isLoading && users.isEmpty)
                        const SliverFillRemaining(
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (users.isEmpty || (filteredUsers.isEmpty && _searchQuery.isNotEmpty))
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _buildEmptyState(context, user),
                        )
                      else ...[
                        if (pendingUsers.isNotEmpty) ...[
                          _buildSectionHeaderSliver('Pending Approvals', theme.colorScheme.secondary),
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) => _buildPendingUserCard(
                                  context, 
                                  ref, 
                                  pendingUsers[index], 
                                  branchesAsync.value ?? [], 
                                  theme
                                ),
                                childCount: pendingUsers.length,
                              ),
                            ),
                          ),
                        ],
                        
                        _buildSectionHeaderSliver('Team Members', theme.colorScheme.onSurface),
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
                          sliver: SliverGrid(
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: _getCrossAxisCount(context),
                              crossAxisSpacing: AppSpacing.m,
                              mainAxisSpacing: AppSpacing.m,
                              childAspectRatio: 2.8,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => _buildUserCard(
                                context, 
                                ref, 
                                approvedUsers[index], 
                                branchesAsync.value ?? [], 
                                theme
                              ),
                              childCount: approvedUsers.length,
                            ),
                          ),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 100)),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _getCrossAxisCount(BuildContext context) {
    double width = MediaQuery.of(context).size.width;
    if (ResponsiveLayout.isDesktop(context)) width -= 280; // Sidebar width
    if (width > 1200) return 3;
    if (width > 800) return 2;
    return 1;
  }

  Widget _buildSectionHeaderSliver(String title, Color color) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.xl, AppSpacing.l, AppSpacing.m),
      sliver: SliverToBoxAdapter(
        child: Text(
          title,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
        ),
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: 'Search by name, email or phone...',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _searchQuery.isNotEmpty 
          ? IconButton(
              icon: const Icon(Icons.clear), 
              onPressed: () {
                _searchController.clear();
                setState(() => _searchQuery = '');
              }) 
          : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.m)),
        filled: true,
        fillColor: theme.cardTheme.color,
      ),
      onChanged: (value) => setState(() => _searchQuery = value),
    );
  }

  Widget _buildEmptyState(BuildContext context, UserAccount currentUser) {
    final theme = Theme.of(context);
    final isSearching = _searchQuery.isNotEmpty;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isSearching ? Icons.search_off_rounded : Icons.people_outline_rounded, 
            size: 64, 
            color: theme.dividerColor
          ),
          const SizedBox(height: 16),
          Text(
            isSearching ? 'No results found' : 'No staff members found', 
            style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 18, fontWeight: FontWeight.bold)
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              isSearching 
                ? 'Try adjusting your search terms'
                : 'Showing results for branch: ${currentUser.branchCode ?? "All Branches"}. Ensure staff accounts are registered to this branch.', 
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              if (isSearching) {
                _searchController.clear();
                setState(() => _searchQuery = '');
              }
              ref.read(userProvider.notifier).loadUsers();
            },
            icon: const Icon(Icons.refresh_rounded),
            label: Text(isSearching ? 'Clear Search' : 'Reload Staff List'),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingUserCard(BuildContext context, WidgetRef ref, UserAccount user, List<Branch> branches, ThemeData theme) {
    final branch = branches.where((b) => b.code == user.branchCode).firstOrNull;
    final branchDisplay = branch != null ? '${branch.name} (${branch.location})' : (user.branchCode ?? "HQ");

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.m),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.m),
        side: BorderSide(color: theme.colorScheme.secondary.withValues(alpha: 0.2)),
      ),
      child: InkWell(
        onTap: () => _showUserDetails(context, user),
        borderRadius: BorderRadius.circular(AppRadius.m),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.m),
          child: Row(
            children: [
              _buildAvatar(context, user, size: 50),
              const SizedBox(width: AppSpacing.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text('${user.role.toString().split('.').last.toUpperCase()} • $branchDisplay',
                      style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                    Text(user.email, style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7))),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _circleIconButton(
                    icon: Icons.check_rounded, 
                    color: Colors.green, 
                    onPressed: () => _confirmApproval(context, ref, user),
                    tooltip: 'Approve',
                  ),
                  const SizedBox(width: 8),
                  _circleIconButton(
                    icon: Icons.close_rounded, 
                    color: Colors.red, 
                    onPressed: () => _confirmDelete(context, ref, user),
                    tooltip: 'Reject',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserCard(BuildContext context, WidgetRef ref, UserAccount user, List<Branch> branches, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final isSuspended = user.status == AccountStatus.suspended;
    final role = user.activePrimaryRole;
    final roleColor = _getRoleColor(role);
    final branch = branches.where((b) => b.code == user.branchCode).firstOrNull;
    final branchDisplay = branch != null ? branch.name : (user.branchCode ?? "HQ");

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.m),
        side: BorderSide(color: isDark ? theme.dividerColor : Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: () => _showUserDetails(context, user),
        borderRadius: BorderRadius.circular(AppRadius.m),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.m),
          child: Row(
            children: [
              Stack(
                children: [
                  _buildAvatar(context, user, size: 55),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: user.isOnline ? Colors.green : Colors.grey.shade400,
                        shape: BoxShape.circle,
                        border: Border.all(color: theme.cardTheme.color ?? theme.scaffoldBackgroundColor, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: AppSpacing.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      user.name, 
                      style: TextStyle(
                        fontWeight: FontWeight.bold, 
                        fontSize: 15,
                        color: isSuspended ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.onSurface,
                        decoration: isSuspended ? TextDecoration.lineThrough : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      role.name.toUpperCase(),
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: roleColor, letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.map_outlined, size: 10, color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(branchDisplay, 
                            style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 10),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _buildUserActionMenu(context, ref, user, isSuspended, user.hasActivePromotion),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isMobile = ResponsiveLayout.isMobile(context);
    
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Staff & Access Control', 
                style: TextStyle(fontSize: isMobile ? 20 : 24, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
              ),
              Text('Manage system roles, permissions, and team approvals', 
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
        ),
        Row(
          children: [
            if (!isMobile)
              IconButton(
                icon: Icon(Icons.refresh_rounded, color: theme.colorScheme.primary),
                onPressed: () => ref.read(userProvider.notifier).loadUsers(),
                tooltip: 'Refresh',
              ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () => _showAddUserDialog(context, ref),
              icon: const Icon(Icons.person_add_rounded),
              label: Text(isMobile ? 'Add' : 'Add Staff'),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.s)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryInfo(BuildContext context, List<UserAccount> active, List<UserAccount> pending) {
    return Wrap(
      spacing: AppSpacing.m,
      runSpacing: AppSpacing.m,
      children: [
        _miniStatCard(context, 'Total Staff', active.length.toString(), Icons.people, Colors.blue),
        _miniStatCard(context, 'Pending', pending.length.toString(), Icons.hourglass_top, Colors.orange),
        _miniStatCard(context, 'Active', active.where((u) => u.status == AccountStatus.approved).length.toString(), Icons.check_circle_outline, Colors.green),
      ],
    );
  }

  Widget _miniStatCard(BuildContext context, String label, String value, IconData icon, Color color) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppRadius.s),
        border: Border.all(color: color.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(width: 8),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildAvatar(BuildContext context, UserAccount user, {double size = 40}) {
    final roleColor = _getRoleColor(user.activePrimaryRole);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: roleColor.withValues(alpha: 0.2), width: 2),
      ),
      child: ClipOval(
        child: user.photoUrl != null && user.photoUrl!.isNotEmpty
            ? Image.network(
                user.photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _fallbackAvatar(user, roleColor, size),
              )
            : _fallbackAvatar(user, roleColor, size),
      ),
    );
  }

  Widget _fallbackAvatar(UserAccount user, Color color, double size) {
    return Container(
      color: color.withValues(alpha: 0.1),
      child: Icon(_getRoleIcon(user.activePrimaryRole), color: color, size: size * 0.5),
    );
  }

  Widget _circleIconButton({required IconData icon, required Color color, required VoidCallback onPressed, String? tooltip}) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 18),
      ),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
    );
  }

  void _confirmApproval(BuildContext context, WidgetRef ref, UserAccount user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve Staff?'),
        content: Text('Approve ${user.name} as ${user.role.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              ref.read(userProvider.notifier).approveUser(user.id);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
  }

  Widget _buildUserActionMenu(BuildContext context, WidgetRef ref, UserAccount user, bool isSuspended, bool isPromoted) {
    final theme = Theme.of(context);
    return PopupMenuButton<String>(
      onSelected: (action) => _handleUserAction(context, ref, user, action),
      icon: Icon(Icons.more_vert_rounded, color: theme.colorScheme.onSurfaceVariant, size: 20),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'manage_roles',
          child: Row(children: [Icon(Icons.admin_panel_settings_outlined, size: 18), SizedBox(width: 12), Text('Permissions')]),
        ),
        PopupMenuItem(
          value: 'promote',
          child: Row(children: [Icon(Icons.trending_up_rounded, size: 18, color: Colors.purple), const SizedBox(width: 12), Text('Temporary Role')]),
        ),
        const PopupMenuItem(
          value: 'passcode',
          child: Row(children: [Icon(Icons.lock_person_rounded, size: 18, color: AppColors.primaryMaroon), SizedBox(width: 12), Text('Security Passcode')]),
        ),
        if (isPromoted)
          const PopupMenuItem(
            value: 'clear_promo',
            child: Row(children: [Icon(Icons.layers_clear_outlined, size: 18, color: Colors.orange), SizedBox(width: 12), Text('Reset Role')]),
          ),
        PopupMenuItem(
          value: isSuspended ? 'activate' : 'suspend',
          child: Row(children: [Icon(isSuspended ? Icons.play_circle_outline : Icons.pause_circle_outline, size: 18), const SizedBox(width: 12), Text(isSuspended ? 'Activate' : 'Suspend')]),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'delete',
          child: Row(children: [Icon(Icons.delete_outline_rounded, color: Colors.red, size: 18), SizedBox(width: 12), Text('Remove', style: TextStyle(color: Colors.red))]),
        ),
      ],
    );
  }

  void _handleUserAction(BuildContext context, WidgetRef ref, UserAccount user, String action) {
    switch (action) {
      case 'suspend': ref.read(userProvider.notifier).suspendUser(user.id); break;
      case 'activate': ref.read(userProvider.notifier).activateUser(user.id); break;
      case 'delete': _confirmDelete(context, ref, user); break;
      case 'manage_roles': _showManageRolesDialog(context, ref, user); break;
      case 'promote': _showPromotionDialog(context, ref, user); break;
      case 'passcode': _showPasscodeDialog(context, ref, user); break;
      case 'clear_promo': ref.read(userProvider.notifier).clearTemporaryPromotion(user.id); break;
    }
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, UserAccount user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account?'),
        content: Text('Permanently delete ${user.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              try {
                // Show loading indicator
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => const Center(child: CircularProgressIndicator()),
                );

                await ref.read(userProvider.notifier).deleteUser(user.id);
                
                if (context.mounted) {
                  Navigator.pop(context); // Pop loading
                  Navigator.pop(context); // Pop confirm dialog
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${user.name} has been permanently removed from the system.'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  Navigator.pop(context); // Pop loading
                  
                  String errorMsg = e.toString();
                  if (errorMsg.contains('foreign key constraint')) {
                    errorMsg = 'Cannot hard-delete this user because they have associated records (like sales or salary history). Try suspending them instead to revoke access.';
                  }

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Delete failed: $errorMsg'),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 5),
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
  }

  void _showPromotionDialog(BuildContext context, WidgetRef ref, UserAccount user) {
    final theme = Theme.of(context);
    DateTimeRange? selectedRange;
    final availableRoles = UserRole.values
        .where((r) => r != UserRole.superAdmin && r != user.role)
        .toList();
    
    if (availableRoles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No other roles available for promotion.')),
      );
      return;
    }

    UserRole selectedRole = availableRoles.first;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
          title: Text('Temporarily Promote ${user.name}', overflow: TextOverflow.ellipsis),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Set a temporary role for a specific period. After the period ends, the user will revert to their original role.', 
                style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 24),
              DropdownButtonFormField<UserRole>(
                initialValue: selectedRole,
                decoration: const InputDecoration(labelText: 'Temporary Role'),
                items: availableRoles
                    .map((r) => DropdownMenuItem(value: r, child: Text(r.name.toUpperCase())))
                    .toList(),
                onChanged: (v) => setState(() => selectedRole = v!),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () async {
                  final range = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 90)),
                  );
                  if (range != null) {
                    setState(() => selectedRange = range);
                  }
                },
                icon: const Icon(Icons.date_range),
                label: Text(selectedRange == null 
                  ? 'Select Date Range' 
                  : '${DateFormat('MMM dd').format(selectedRange!.start)} - ${DateFormat('MMM dd').format(selectedRange!.end)}'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  side: BorderSide(color: selectedRange == null ? theme.dividerColor : theme.colorScheme.primary),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: theme.colorScheme.onSurfaceVariant))),
            ElevatedButton(
              onPressed: selectedRange == null ? null : () {
                ref.read(userProvider.notifier).promoteTemporarily(
                  user.id, 
                  selectedRole, 
                  selectedRange!.start, 
                  selectedRange!.end
                );
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${user.name} promoted to ${selectedRole.name} until ${DateFormat('MMM dd').format(selectedRange!.end)}')),
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: theme.colorScheme.primary, foregroundColor: Colors.white),
              child: const Text('Apply Promotion'),
            ),
          ],
        ),
      ),
    );
  }

  void _showPasscodeDialog(BuildContext context, WidgetRef ref, UserAccount user) {
    final controller = TextEditingController(text: user.passcode);
    bool isSaving = false;
    bool sendSms = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
          title: Row(
            children: [
              const Icon(Icons.lock_person_rounded, color: AppColors.primaryMaroon),
              const SizedBox(width: 12),
              Expanded(child: Text('Passcode: ${user.firstName}', overflow: TextOverflow.ellipsis)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Set a 4-digit numeric passcode for this staff member. This will be required for sensitive system areas.', 
                style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 24),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Security Passcode (4 Digits)',
                  hintText: 'e.g. 1234',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.password_rounded),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                style: const TextStyle(fontSize: 24, letterSpacing: 10, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                title: const Text('Send to staff via SMS', style: TextStyle(fontSize: 13)),
                value: sendSms,
                onChanged: (v) => setState(() => sendSms = v!),
                dense: true,
                contentPadding: EdgeInsets.zero,
                activeColor: AppColors.primaryMaroon,
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: isSaving ? null : () => Navigator.pop(context), child: const Text('CANCEL')),
            ElevatedButton(
              onPressed: isSaving ? null : () async {
                final code = controller.text.trim();
                if (code.length != 4) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Passcode must be exactly 4 digits.')));
                  return;
                }

                setState(() => isSaving = true);
                try {
                  await ref.read(userProvider.notifier).updatePasscode(user.id, code);
                  
                  if (sendSms && user.phone != null && user.phone!.isNotEmpty) {
                    // Using SmsService directly from imported file
                    await SmsService.sendPasscodeSms(user.phone!, user.firstName, code);
                  }

                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Passcode saved ${sendSms ? "and sent via SMS " : ""}for ${user.firstName}.'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    setState(() => isSaving = false);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryMaroon, foregroundColor: Colors.white),
              child: isSaving 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('SAVE & SEND'),
            ),
          ],
        ),
      ),
    );
  }

  void _showUserDetails(BuildContext context, UserAccount user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(user.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _detailRow('Email', user.email),
            _detailRow('Phone', user.phone ?? 'N/A'),
            _detailRow('Role', user.role.name.toUpperCase()),
            _detailRow('Status', user.status.name.toUpperCase()),
            _detailRow('Branch', user.branchCode ?? 'N/A'),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value, 
              style: const TextStyle(fontSize: 12),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Color _getRoleColor(UserRole role) {
    switch (role) {
      case UserRole.superAdmin: return Colors.black;
      case UserRole.admin: return Colors.purple;
      case UserRole.butcher: return AppColors.primaryMaroon;
      case UserRole.cashier: return Colors.blue;
    }
  }

  IconData _getRoleIcon(UserRole role) {
    switch (role) {
      case UserRole.superAdmin: return Icons.security;
      case UserRole.admin: return Icons.admin_panel_settings;
      case UserRole.butcher: return Icons.restaurant;
      case UserRole.cashier: return Icons.point_of_sale;
    }
  }

  // Reuse existing dialog logic but slightly cleaned up
  void _showAddUserDialog(BuildContext context, WidgetRef ref) {
    final currentUser = ref.read(currentUserProvider);
    final formKey = GlobalKey<FormState>();
    final firstNameController = TextEditingController();
    final surnameController = TextEditingController();
    final emailController = TextEditingController();
    UserRole selectedRole = UserRole.cashier;
    String? selectedBranchCode = currentUser?.branchCode;
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Register Staff'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: firstNameController,
                    decoration: const InputDecoration(labelText: 'First Name'),
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                  TextFormField(
                    controller: surnameController,
                    decoration: const InputDecoration(labelText: 'Surname'),
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                  TextFormField(
                    controller: emailController,
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: (v) => !v!.contains('@') ? 'Invalid email' : null,
                  ),
                  DropdownButtonFormField<UserRole>(
                    initialValue: selectedRole,
                    items: UserRole.values.where((r) => r != UserRole.superAdmin)
                        .map((r) => DropdownMenuItem(value: r, child: Text(r.name.toUpperCase()))).toList(),
                    onChanged: (v) => setState(() => selectedRole = v!),
                    decoration: const InputDecoration(labelText: 'Role'),
                  ),
                  Consumer(builder: (context, ref, _) {
                    final branches = ref.watch(branchesProvider).value ?? [];
                    return DropdownButtonFormField<String>(
                      initialValue: selectedBranchCode,
                      items: branches.map((b) => DropdownMenuItem(value: b.code, child: Text(b.name))).toList(),
                      onChanged: currentUser?.role == UserRole.superAdmin ? (v) => setState(() => selectedBranchCode = v) : null,
                      decoration: const InputDecoration(labelText: 'Branch'),
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: isSaving ? null : () async {
                if (formKey.currentState!.validate()) {
                  setState(() => isSaving = true);
                  final newUser = UserAccount(
                    id: 'temp-${DateTime.now().millisecondsSinceEpoch}',
                    firstName: firstNameController.text.trim(),
                    surname: surnameController.text.trim(),
                    email: emailController.text.trim(),
                    role: selectedRole,
                    branchCode: selectedBranchCode,
                    status: AccountStatus.approved,
                  );
                  await ref.read(userProvider.notifier).addAccount(newUser);
                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                }
              },
              child: isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  void _showManageRolesDialog(BuildContext context, WidgetRef ref, UserAccount user) {
    final theme = Theme.of(context);
    UserRole selectedPrimary = user.role;
    Set<String> selectedPermissions = Set.from(user.enabledPermissions);
    final salaryController = TextEditingController(text: user.salaryAmount?.toString() ?? '');
    final salaryDayController = TextEditingController(text: user.salaryDay?.toString() ?? '');
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Account Setup: ${user.firstName}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Role & Access', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 8),
                DropdownButtonFormField<UserRole>(
                  initialValue: selectedPrimary,
                  items: UserRole.values.map((r) => DropdownMenuItem(value: r, child: Text(r.name.toUpperCase()))).toList(),
                  onChanged: (v) => setState(() => selectedPrimary = v!),
                  decoration: const InputDecoration(labelText: 'Primary Role', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 24),
                const Text('Salary Configuration', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: salaryController,
                        decoration: const InputDecoration(labelText: 'Monthly Salary', prefixText: '₵ ', border: OutlineInputBorder()),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: salaryDayController,
                        decoration: const InputDecoration(labelText: 'Pay Day', hintText: '1-31', border: OutlineInputBorder()),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text('Menu Access', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.dividerColor),
                    borderRadius: BorderRadius.circular(AppRadius.s),
                  ),
                  child: Column(
                    children: MenuService.getAllAvailableDuties().map((duty) => CheckboxListTile(
                      title: Text(duty['label']!, style: const TextStyle(fontSize: 13)),
                      value: selectedPermissions.contains(duty['route']),
                      onChanged: (val) => setState(() {
                        if (val!) {
                          selectedPermissions.add(duty['route']!);
                        } else {
                          selectedPermissions.remove(duty['route']!);
                        }
                      }),
                      dense: true,
                      activeColor: theme.colorScheme.primary,
                    )).toList(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: isSaving ? null : () async {
                setState(() => isSaving = true);
                try {
                  final double? salary = double.tryParse(salaryController.text);
                  final int? day = int.tryParse(salaryDayController.text);

                  await ref.read(userProvider.notifier).updateRoles(user.id, primaryRole: selectedPrimary);
                  await ref.read(userProvider.notifier).setPermissions(user.id, selectedPermissions);
                  await ref.read(userProvider.notifier).updateSalary(user.id, amount: salary, day: day);

                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Staff configuration updated successfully'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  debugPrint('Staff Config Error: $e');
                  if (context.mounted) {
                    setState(() => isSaving = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error saving configuration: ${e.toString()}'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save Configuration'),
            ),
          ],
        ),
      ),
    );
  }
}
