import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:i_gen/repos/pricing_category_repo.dart';
import 'package:i_gen/utils/context_extensions.dart';
import 'package:i_gen/utils/futuristic.dart';

/// Price-list picker: `('SP', null)` / `('USD', null)` customs plus every
/// stored category. Shared by the mobile meta row (and the desktop editor).
class PriceCategoryDropdown extends StatelessWidget {
  const PriceCategoryDropdown({
    super.key,
    required this.priceCategory,
    required this.onCategoryChanged,
  });

  final ({String currency, String? name}) priceCategory;
  final ValueChanged<(String, String?)?> onCategoryChanged;

  @override
  Widget build(BuildContext context) {
    return Futuristic(
      autoStart: true,
      futureBuilder: () => GetIt.I.get<PricingCategoryRepo>().getAll(),
      busyBuilder: (_) => const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      dataBuilder: (_, categories) {
        return DropdownButtonHideUnderline(
          child: DropdownButton<(String, String?)>(
            value: (priceCategory.currency, priceCategory.name),
            style: context.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: context.colorScheme.primary,
            ),
            items: [
              DropdownMenuItem(
                value: ('SP', null),
                child: Text(context.l10n.customPriceList('ل.س')),
              ),
              DropdownMenuItem(
                value: ('USD', null),
                child: Text(context.l10n.customPriceList('\$')),
              ),
              ...categories.map(
                (e) => DropdownMenuItem(
                  value: (e.currency, e.name),
                  child: Text(
                    context.l10n.priceCategoryOption(e.name, e.currency),
                  ),
                ),
              ),
            ],
            onChanged: onCategoryChanged,
          ),
        );
      },
    );
  }
}
