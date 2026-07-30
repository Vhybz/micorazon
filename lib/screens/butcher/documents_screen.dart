import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

import '../../core/constants.dart';
import '../../widgets/main_app_bar.dart';
import '../../widgets/app_sidebar.dart';
import '../../services/menu_service.dart';
import '../../services/user_provider.dart';
import '../../widgets/responsive_layout.dart';
import '../../models/user_model.dart';
import '../../models/document_model.dart';
import '../../services/document_provider.dart';
import '../../widgets/role_pop_scope.dart';

class DocumentsScreen extends ConsumerWidget {
  final bool isNested;
  const DocumentsScreen({super.key, this.isNested = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const Center(child: CircularProgressIndicator());

    final theme = Theme.of(context);
    final isDesktop = ResponsiveLayout.isDesktop(context);
    final bool isAdmin = user.activeRoles.contains(UserRole.admin) || user.activeRoles.contains(UserRole.superAdmin);
    
    final bool showScaffold = isAdmin && !isNested;
    
    final String currentRoute = isAdmin ? '/admin/documents' : 'butcher:documents';
    final menuItems = ref.watch(isAdmin ? menuItemsProvider : butcherMenuItemsProvider);

    final documents = ref.watch(documentProvider);

    Widget content = RolePopScope(
      currentRoute: currentRoute,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Compliance Documents', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: theme.colorScheme.onSurface)),
                      Text('View and manage regulatory certifications', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.m),
                ElevatedButton.icon(
                  onPressed: () => _showUploadDialog(context, ref),
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Upload Document'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            if (documents.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(40.0),
                  child: Column(
                    children: [
                      Icon(Icons.folder_open, size: 64, color: theme.dividerColor),
                      const SizedBox(height: 16),
                      Text(
                        user.branchCode == null 
                          ? 'Branch code missing. Please update your profile.' 
                          : 'No documents uploaded yet for branch ${user.branchCode}.', 
                        style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: documents.length,
                itemBuilder: (context, index) {
                  final doc = documents[index];
                  return _buildDocCard(context, ref, doc);
                }
              ),
            const SizedBox(height: AppSpacing.xl),
            Text('System Intelligence', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: theme.colorScheme.onSurface)),
            const SizedBox(height: AppSpacing.m),
            _buildDocItem(
              context,
              'Daily Operations Summary', 
              'Automated yield & efficiency metrics', 
              'LIVE REPORT', 
              Colors.green,
              onTap: () {},
            ),
          ],
        ),
      ),
    );

    if (showScaffold) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: const MainAppBar(title: 'Compliance Documents'),
        drawer: isDesktop ? null : Drawer(
          child: AppSidebar(
            userId: user.id,
            userName: user.name,
            userRole: user.activePrimaryRole.name.toUpperCase(),
            currentRoute: currentRoute,
            items: menuItems,
            onTap: (route) => MenuService.navigate(context, route, currentRoute),
          ),
        ),
        body: Row(
          children: [
            if (isDesktop)
              AppSidebar(
                userId: user.id,
                userName: user.name,
                userRole: user.activePrimaryRole.name.toUpperCase(),
                currentRoute: currentRoute,
                items: menuItems,
                onTap: (route) => MenuService.navigate(context, route, currentRoute),
              ),
            Expanded(child: content),
          ],
        ),
      );
    }

    return content;
  }

  Widget _buildDocCard(BuildContext context, WidgetRef ref, DocumentRecord doc) {
    final theme = Theme.of(context);
    final fileName = doc.fileUrl.split('?').first.toLowerCase();
    final isImage = fileName.endsWith('.jpg') || fileName.endsWith('.png') || fileName.endsWith('.jpeg') || fileName.endsWith('.webp');
    final isPdf = fileName.endsWith('.pdf');
    final isDoc = fileName.endsWith('.doc') || fileName.endsWith('.docx');
    final isExcel = fileName.endsWith('.xls') || fileName.endsWith('.xlsx');

    IconData fileIcon = Icons.description;
    Color iconColor = theme.colorScheme.primary;

    if (isPdf) {
      fileIcon = Icons.picture_as_pdf;
      iconColor = Colors.red;
    } else if (isDoc) {
      fileIcon = Icons.article;
      iconColor = Colors.blue;
    } else if (isExcel) {
      fileIcon = Icons.table_chart;
      iconColor = Colors.green;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.m),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _viewDocument(doc),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isImage)
              SizedBox(
                height: 120,
                width: double.infinity,
                child: Image.network(
                  doc.fileUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Icon(Icons.broken_image, color: theme.dividerColor),
                  ),
                ),
              )
            else
              Container(
                height: 80,
                width: double.infinity,
                color: iconColor.withValues(alpha: 0.05),
                child: Icon(fileIcon, color: iconColor, size: 32),
              ),
            ListTile(
              contentPadding: const EdgeInsets.all(AppSpacing.m),
              title: Text(doc.title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: theme.colorScheme.onSurface)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(doc.description, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 10, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(DateFormat('MMM dd, yyyy').format(doc.createdAt), style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ],
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (value) => _handleAction(context, ref, doc, value),
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'view', child: Row(children: [Icon(Icons.visibility, size: 18), SizedBox(width: 8), Text('View')])),
                  const PopupMenuItem(value: 'update', child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('Update')])),
                  const PopupMenuItem(value: 'download', child: Row(children: [Icon(Icons.download, size: 18), SizedBox(width: 8), Text('Download')])),
                  const PopupMenuDivider(),
                  const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, color: Colors.red, size: 18), SizedBox(width: 8), Text('Delete', style: TextStyle(color: Colors.red))])),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocItem(BuildContext context, String title, String subtitle, String tag, Color tagColor, {required VoidCallback onTap}) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.insights, color: Colors.blue),
        title: Text(
          title, 
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: theme.colorScheme.onSurface),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          subtitle, 
          style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: tagColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(tag, style: TextStyle(color: tagColor, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        onTap: onTap,
      ),
    );
  }

  void _handleAction(BuildContext context, WidgetRef ref, DocumentRecord doc, String action) {
    switch (action) {
      case 'view':
        _viewDocument(doc);
        break;
      case 'update':
        _showUpdateDialog(context, ref, doc);
        break;
      case 'download':
        _downloadDocument(context, doc);
        break;
      case 'delete':
        _confirmDelete(context, ref, doc);
        break;
    }
  }

  Future<void> _viewDocument(DocumentRecord doc) async {
    final url = Uri.parse(doc.fileUrl);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _downloadDocument(BuildContext context, DocumentRecord doc) async {
    try {
      final response = await http.get(Uri.parse(doc.fileUrl));
      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        final fileName = doc.fileUrl.split('/').last.split('?').first;
        
        final String? path = await FilePicker.platform.saveFile(
          fileName: fileName,
          bytes: bytes,
        );

        if (path != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('File saved to: $path')),
          );
        }
      } else {
        throw Exception('Failed to fetch file from server');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error downloading file: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, DocumentRecord doc) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text('Are you sure you want to delete "${doc.title}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await ref.read(documentProvider.notifier).deleteDocument(doc);
              if (context.mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showUploadDialog(BuildContext context, WidgetRef ref) {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    Uint8List? fileBytes;
    String? fileName;
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: !isSaving,
      builder: (context) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
        title: const Text('Upload Document'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Title', hintText: 'e.g. Sanitary Certificate')),
                TextField(controller: descController, decoration: const InputDecoration(labelText: 'Description', hintText: 'Briefly describe the document')),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: isSaving ? null : () async {
                    FilePickerResult? result = await FilePicker.platform.pickFiles(
                      type: FileType.any,
                      withData: true,
                    );
                    
                    if (result != null && result.files.single.bytes != null) {
                      fileBytes = result.files.single.bytes;
                      fileName = result.files.single.name;
                      setDialogState(() {});
                    }
                  }, 
                  icon: const Icon(Icons.attach_file),
                  label: Text(fileName ?? 'Select File'),
                ),
                if (isSaving)
                  const Padding(
                    padding: EdgeInsets.only(top: 16.0),
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: isSaving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: (isSaving || fileBytes == null || titleController.text.isEmpty) ? null : () async {
              setDialogState(() => isSaving = true);
              try {
                await ref.read(documentProvider.notifier).uploadAndAddDocument(fileBytes!, fileName!, titleController.text, descController.text);
                if (context.mounted) Navigator.pop(context);
              } catch (e) {
                setDialogState(() => isSaving = false);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.red));
                }
              }
            }, 
            child: const Text('Upload'),
          ),
        ],
      )),
    );
  }

  void _showUpdateDialog(BuildContext context, WidgetRef ref, DocumentRecord doc) {
    final titleController = TextEditingController(text: doc.title);
    final descController = TextEditingController(text: doc.description);
    Uint8List? fileBytes;
    String? fileName;
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: !isSaving,
      builder: (context) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
        title: const Text('Update Document'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Title')),
                TextField(controller: descController, decoration: const InputDecoration(labelText: 'Description')),
                const SizedBox(height: 20),
                Text('Current File: ${doc.fileUrl.split('/').last.split('?').first}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: isSaving ? null : () async {
                    FilePickerResult? result = await FilePicker.platform.pickFiles(
                      type: FileType.any,
                      withData: true,
                    );
                    
                    if (result != null && result.files.single.bytes != null) {
                      fileBytes = result.files.single.bytes;
                      fileName = result.files.single.name;
                      setDialogState(() {});
                    }
                  }, 
                  icon: const Icon(Icons.change_circle),
                  label: Text(fileName ?? 'Replace File (Optional)'),
                ),
                if (isSaving)
                  const Padding(
                    padding: EdgeInsets.only(top: 16.0),
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: isSaving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: isSaving ? null : () async {
              setDialogState(() => isSaving = true);
              try {
                await ref.read(documentProvider.notifier).updateDocument(
                  doc, 
                  newBytes: fileBytes, 
                  newFileName: fileName,
                  title: titleController.text,
                  description: descController.text,
                );
                if (context.mounted) Navigator.pop(context);
              } catch (e) {
                setDialogState(() => isSaving = false);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e'), backgroundColor: Colors.red));
                }
              }
            }, 
            child: const Text('Save Changes'),
          ),
        ],
      )),
    );
  }
}
