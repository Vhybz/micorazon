import 'package:flutter/material.dart';
import '../core/constants.dart';

class ProductCard extends StatelessWidget {
  final String name;
  final String category;
  final String price;
  final String? originalPrice;
  final double? stockQuantity;
  final double? lowStockThreshold;
  final String? unit;
  final String imageUrl;
  final String? promoLabel;
  final bool isInTransit;
  final VoidCallback onTap;

  const ProductCard({
    super.key,
    required this.name,
    required this.category,
    required this.price,
    this.originalPrice,
    this.stockQuantity,
    this.lowStockThreshold,
    this.unit,
    this.promoLabel,
    this.isInTransit = false,
    required this.imageUrl,
    required this.onTap,
  });

  Widget _buildErrorIcon(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(Icons.image, color: Theme.of(context).dividerColor),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    BorderSide borderSide = isDark ? BorderSide(color: theme.dividerColor) : BorderSide.none;
    
    if (stockQuantity != null) {
      if (stockQuantity! <= 0) {
        borderSide = const BorderSide(color: Colors.red, width: 2);
      } else if (stockQuantity! <= (lowStockThreshold ?? 5.0)) {
        borderSide = const BorderSide(color: Colors.orange, width: 2);
      }
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: isDark ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.m),
        side: borderSide,
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  imageUrl.isEmpty 
                    ? _buildErrorIcon(context)
                    : imageUrl.startsWith('assets/') 
                      ? Image.asset(
                          imageUrl,
                          key: ValueKey(imageUrl),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          errorBuilder: (context, error, stackTrace) => _buildErrorIcon(context),
                        )
                      : Image.network(
                          imageUrl,
                          key: ValueKey(imageUrl),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Center(
                              child: CircularProgressIndicator(
                                value: loadingProgress.expectedTotalBytes != null
                                    ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                    : null,
                                strokeWidth: 2,
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            debugPrint('Product Image Load Error ($name): $error');
                            return _buildErrorIcon(context);
                          },
                        ),
                  if (promoLabel != null)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          promoLabel!,
                          style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  if (stockQuantity != null)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: (stockQuantity! > 0 ? Colors.green : Colors.red).withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${stockQuantity!.toStringAsFixed(1)}${unit ?? "kg"}',
                          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  if (isInTransit)
                    Container(
                      color: Colors.black.withValues(alpha: 0.4),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade700,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 4)],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.local_shipping, color: Colors.white, size: 14),
                              SizedBox(width: 6),
                              Text(
                                'IN TRANSIT',
                                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.toUpperCase(),
                    style: TextStyle(
                      color: isDark ? theme.colorScheme.primary : AppColors.primaryMaroon,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold, 
                      fontSize: 13,
                      color: theme.colorScheme.onSurface,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        Text(
                          price,
                          style: TextStyle(
                            color: promoLabel != null 
                              ? Colors.orange.shade800 
                              : theme.colorScheme.onSurface.withValues(alpha: 0.8),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (originalPrice != null) ...[
                          const SizedBox(width: 4),
                          Text(
                            originalPrice!,
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 9,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
