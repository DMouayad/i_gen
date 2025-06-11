import 'package:flutter/material.dart';
import 'package:i_gen/utils/context_extensions.dart';
import 'package:i_gen/widgets/product_pricing_table.dart';

class PricingScreen extends StatelessWidget {
  const PricingScreen(
    this.unsavedPricingCategoryCountNotifier,
    this.unsavedProductPricingCountNotifier, {
    super.key,
  });
  final ValueNotifier<int> unsavedPricingCategoryCountNotifier;
  final ValueNotifier<int> unsavedProductPricingCountNotifier;
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: SingleChildScrollView(
            child: Container(
              width: 1024,
              height: context.height * .9,
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: ProductPricingTable(
                unsavedProductPricingCountNotifier,
                unsavedPricingCategoryCountNotifier,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
