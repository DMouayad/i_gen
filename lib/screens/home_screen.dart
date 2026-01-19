import 'dart:async';

import 'package:flutter/material.dart';

import 'package:i_gen/controllers/invoice_details_controller.dart';
import 'package:i_gen/screens/archive_screen.dart';
import 'package:i_gen/screens/invoice_screen.dart';
import 'package:i_gen/screens/products_screen.dart';
import 'package:i_gen/screens/products_screen_mobile.dart';
import 'package:i_gen/utils/context_extensions.dart';
import 'package:i_gen/utils/nav_listener.dart';
import 'package:i_gen/widgets/product_pricing_table.dart';

const _productsPageIndex = 1;
const _pricingPageIndex = 2;

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final textStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.bold,
    color: Colors.black,
  );
  InvoiceDetailsController? currentInvoiceDetailsController;
  final unsavedProductCountNotifier = ValueNotifier<int>(0);
  final navigationConfirmedStreamController = StreamController<bool>();
  final unsavedPricingCategoryCountNotifier = ValueNotifier<int>(0);
  final unsavedProductPricingCountNotifier = ValueNotifier<int>(0);

  Future<void> onIndexChange(
    int oldIndex,
    int newIndex,
    BuildContext context,
  ) async {
    if (currentInvoiceDetailsController?.hasUnsavedChanges == true) {
      _showNavConfirmationDialog(
        context,
        title: 'Invoice was not saved',
        content: 'Your invoice has unsaved changes, do you want to continue?',
      ).then((confirmed) {
        if (confirmed ?? false) {
          currentInvoiceDetailsController?.hasUnsavedChanges = false;
        }
      });
      return;
    } else if (oldIndex == _productsPageIndex) {
      if (unsavedProductCountNotifier.value > 0) {
        _showNavConfirmationDialog(
          context,
          title: 'Unsaved Products',
          content: 'You have unsaved products, do you want to continue?',
        ).then((confirmed) {
          if (confirmed ?? false) {
            unsavedProductCountNotifier.value = 0;
          }
        });
        return;
      }
    } else if (oldIndex == _pricingPageIndex) {
      if (unsavedPricingCategoryCountNotifier.value > 0) {
        _showNavConfirmationDialog(
          context,
          title: 'Unsaved Pricing Category',
          content:
              'You have unsaved pricing category, do you want to continue?',
        ).then((confirmed) {
          if (confirmed ?? false) {
            unsavedPricingCategoryCountNotifier.value = 0;
          }
        });
        return;
      } else if (unsavedProductPricingCountNotifier.value > 0) {
        _showNavConfirmationDialog(
          context,
          title: 'Unsaved Product Pricing',
          content: 'You have unsaved product pricing, do you want to continue?',
        ).then((confirmed) {
          if (confirmed ?? false) {
            unsavedProductPricingCountNotifier.value = 0;
          }
        });
        return;
      }
    }
    navigationConfirmedStreamController.add(true);
  }

  NavListener? navListener;
  @override
  void dispose() {
    unsavedProductPricingCountNotifier.dispose();
    unsavedProductCountNotifier.dispose();
    unsavedPricingCategoryCountNotifier.dispose();
    navigationConfirmedStreamController.close();
    super.dispose();
  }

  void _onCreateNew() {
    currentInvoiceDetailsController = InvoiceDetailsController(null);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            InvoiceDetails(invoiceController: currentInvoiceDetailsController!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    navListener ??= NavListener(
      navigationConfirmedStreamController.stream,
      onChange: (oldIndex, newIndex) =>
          onIndexChange(oldIndex, newIndex, context),
    );
    return ListenableBuilder(
      listenable: navListener!,
      builder: (context, _) {
        return Scaffold(
          floatingActionButton: !context.isMobile || navListener!.value != 0
              ? null
              : FloatingActionButton(
                  onPressed: _onCreateNew,
                  child: const Icon(Icons.add),
                ),
          bottomNavigationBar: context.showNavigationRail
              ? null
              : BottomNavigationBar(
                  currentIndex: navListener!.value,
                  items: const [
                    BottomNavigationBarItem(
                      icon: Icon(Icons.inventory),
                      label: 'Invoices',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.list_alt),
                      label: 'Products',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.currency_exchange),
                      label: 'Pricing',
                    ),
                  ],
                  onTap: navListener!.updateIndex,
                ),
          body: SafeArea(
            child: Row(
              children: [
                if (context.showNavigationRail)
                  NavigationRail(
                    selectedIndex: navListener!.value,
                    unselectedLabelTextStyle: textStyle,
                    selectedLabelTextStyle: textStyle.copyWith(
                      color: context.colorScheme.primary,
                    ),
                    groupAlignment: 0,
                    extended: true,
                    onDestinationSelected: navListener!.updateIndex,
                    useIndicator: true,

                    trailing: Padding(
                      padding: const EdgeInsets.only(top: 24.0),
                      child: FilledButton.icon(
                        style: ButtonStyle(
                          minimumSize: WidgetStatePropertyAll(Size(200, 55)),
                          textStyle: WidgetStatePropertyAll(
                            TextStyle(fontSize: 18),
                          ),
                        ),
                        onPressed: _onCreateNew,
                        icon: const Icon(Icons.add),
                        label: const Text('Add'),
                      ),
                    ),
                    backgroundColor: context.colorScheme.surface,
                    leading: const SizedBox(
                      width: 210,
                      child: Text(
                        'IGen',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.start,
                      ),
                    ),
                    destinations: const <NavigationRailDestination>[
                      NavigationRailDestination(
                        icon: Icon(Icons.inventory),
                        label: Text('Invoices'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.list_alt_outlined),
                        selectedIcon: Icon(Icons.list_alt),
                        label: Text('Products'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.currency_exchange),
                        selectedIcon: Icon(Icons.currency_exchange),
                        label: Text('Pricing'),
                      ),
                    ],
                  ),
                Flexible(
                  child: Container(
                    alignment: Alignment.center,
                    padding: context.isMobile
                        ? EdgeInsets.zero
                        : EdgeInsets.symmetric(
                            vertical: navListener!.value == 0 ? 20 : 50,
                            horizontal: 24,
                          ),
                    child: switch (navListener!.value) {
                      0 => Center(
                        child: ArchiveScreen(
                          onLoaded: (invoiceController) =>
                              currentInvoiceDetailsController =
                                  invoiceController,
                        ),
                      ),
                      1 =>
                        context.isMobile
                            ? ProductsScreeMobile(
                                unsavedProductCountNotifier:
                                    unsavedProductCountNotifier,
                              )
                            : ProductsScreen2(
                                unsavedProductCountNotifier:
                                    unsavedProductCountNotifier,
                              ),
                      2 => ProductPricingTable(
                        unsavedProductPricingCountNotifier,
                        unsavedPricingCategoryCountNotifier,
                      ),
                      _ => const Center(child: Text('404')),
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool?> _showNavConfirmationDialog(
    BuildContext context, {
    required String title,
    required String content,
  }) async {
    return await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            title,
            style: textStyle.copyWith(
              fontSize: 20,
              color: context.colorScheme.error,
            ),
          ),
          content: Text(content, style: textStyle),
          actions: [
            TextButton(
              onPressed: () {
                navigationConfirmedStreamController.add(true);
                Navigator.of(context).pop(true);
              },
              child: const Text('Yes'),
            ),
            TextButton(
              onPressed: () {
                navigationConfirmedStreamController.add(false);

                Navigator.of(context).pop(false);
              },
              child: const Text('No'),
            ),
          ],
        );
      },
    );
  }
}
