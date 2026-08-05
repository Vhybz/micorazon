import 'package:flutter/material.dart';

class CartItemTile extends StatelessWidget {
  final String name;
  final String? category;
  final String qty;
  final String weight;
  final String amount;
  final VoidCallback onDelete;

  const CartItemTile({
    super.key,
    required this.name,
    this.category,
    required this.qty,
    required this.weight,
    required this.amount,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(Icons.image, size: 20, color: theme.dividerColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (category != null)
                  Text(category!.toUpperCase(), style: TextStyle(color: theme.colorScheme.primary, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.onSurface)),
                Text('$qty x $weight', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 11)),
              ],
            ),
          ),
          Text(amount, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.onSurface)),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onDelete,
            icon: Icon(Icons.delete_outline, size: 18, color: theme.colorScheme.error.withValues(alpha: 0.7)),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}
