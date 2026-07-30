import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/constants.dart';

class PhonePromptDialog extends StatefulWidget {
  const PhonePromptDialog({super.key});

  @override
  State<PhonePromptDialog> createState() => _PhonePromptDialogState();

  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (context) => const PhonePromptDialog(),
    );
  }
}

class _PhonePromptDialogState extends State<PhonePromptDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.m)),
      title: const Row(
        children: [
          Icon(Icons.sms_outlined, color: AppColors.primaryMaroon),
          SizedBox(width: 12),
          Text('Enter Phone Number', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Please provide the recipient\'s phone number to send the SMS receipt.', 
              style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 20),
            TextFormField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                hintText: 'e.g. 0244123456',
                prefixIcon: Icon(Icons.phone),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              validator: (v) {
                if (v == null || v.isEmpty) return 'Required';
                if (v.length < 10) return 'Invalid number';
                return null;
              },
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCEL'),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryMaroon,
            foregroundColor: Colors.white,
          ),
          child: const Text('SEND SMS'),
        ),
      ],
    );
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, _controller.text.trim());
    }
  }
}
