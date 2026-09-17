import 'dart:async';

import 'package:flutter/material.dart';

import 'package:i_gen/controllers/invoice_details_controller.dart';
import 'package:i_gen/screens/archive_screen.dart';
import 'package:i_gen/screens/invoice_screen.dart';
import 'package:i_gen/screens/orders_screen.dart';
import 'package:i_gen/screens/products_screen.dart';
import 'package:i_gen/screens/products_screen_mobile.dart';
import 'package:i_gen/screens/settings_screen.dart';
import 'package:i_gen/utils/context_extensions.dart';
import 'package:i_gen/utils/nav_listener.dart';
import 'package:i_gen/widgets/invoice_details_mobile.dart';
import 'package:i_gen/widgets/product_pricing_table.dart';

const _productsPageIndex = 1;
const _pricingPageIndex = 2;

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
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
        title: context.l10n.invoiceUnsavedTitle,
        content: context.l10n.invoiceUnsavedMessage,
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
          title: context.l10n.unsavedProductsTitle,
          content: context.l10n.unsavedProductsMessage,
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
          title: context.l10n.unsavedPricingCategoryTitle,
          content: context.l10n.unsavedPricingCategoryMessage,
        ).then((confirmed) {
          if (confirmed ?? false) {
            unsavedPricingCategoryCountNotifier.value = 0;
          }
        });
        return;
      } else if (unsavedProductPricingCountNotifier.value > 0) {
        _showNavConfirmationDialog(
          context,
          title: context.l10n.unsavedProductPricingTitle,
          content: context.l10n.unsavedProductPricingMessage,
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
        builder: (context) {
          return context.isMobile
              ? InvoiceDetailsMobile(
                  controller: currentInvoiceDetailsController!,
                )
              : InvoiceDetails(
                  invoiceController: currentInvoiceDetailsController!,
                );
        },
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
                  items: [
                    BottomNavigationBarItem(
                      icon: Icon(Icons.inventory_2_outlined),
                      activeIcon: Icon(Icons.inventory_2),
                      label: context.l10n.navInvoices,
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.list_alt_outlined),
                      activeIcon: Icon(Icons.list_alt),
                      label: context.l10n.navProducts,
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.currency_exchange_outlined),
                      activeIcon: Icon(Icons.currency_exchange),
                      label: context.l10n.navPricing,
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.receipt_long_outlined),
                      activeIcon: Icon(Icons.receipt_long),
                      label: context.l10n.navOrders,
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.settings_outlined),
                      activeIcon: Icon(Icons.settings),
                      label: context.l10n.navSettings,
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
                    unselectedLabelTextStyle: context.textTheme.labelLarge,
                    selectedLabelTextStyle: context.textTheme.labelLarge
                        ?.copyWith(color: context.colorScheme.primary),
                    groupAlignment: 0,
                    extended: true,
                    onDestinationSelected: navListener!.updateIndex,
                    useIndicator: true,

                    trailing: Padding(
                      padding: const EdgeInsets.only(top: AppGaps.lg),
                      child: FilledButton.icon(
                        style: const ButtonStyle(
                          minimumSize: WidgetStatePropertyAll(Size(200, 56)),
                        ),
                        onPressed: _onCreateNew,
                        icon: const Icon(Icons.add),
                        label: Text(context.l10n.addItem),
                      ),
                    ),
                    backgroundColor: context.colorScheme.surface,
                    leading: SizedBox(
                      width: 208,
                      child: Text(
                        'IGen',
                        style: context.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.start,
                      ),
                    ),
                    destinations: <NavigationRailDestination>[
                      NavigationRailDestination(
                        icon: Icon(Icons.inventory_2_outlined),
                        selectedIcon: Icon(Icons.inventory_2),
                        label: Text(context.l10n.navInvoices),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.list_alt_outlined),
                        selectedIcon: Icon(Icons.list_alt),
                        label: Text(context.l10n.navProducts),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.currency_exchange_outlined),
                        selectedIcon: Icon(Icons.currency_exchange),
                        label: Text(context.l10n.navPricing),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.receipt_long_outlined),
                        selectedIcon: Icon(Icons.receipt_long),
                        label: Text(context.l10n.navOrders),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.settings_outlined),
                        selectedIcon: Icon(Icons.settings),
                        label: Text(context.l10n.navSettings),
                      ),
                    ],
                  ),
                Flexible(
                  child: Container(
                    alignment: Alignment.center,
                    padding: context.isMobile
                        ? EdgeInsets.zero
                        : EdgeInsets.symmetric(
                            vertical: navListener!.value == 0
                                ? AppGaps.lg
                                : AppGaps.xl,
                            horizontal: AppGaps.lg,
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
                      3 => const OrdersScreen(),
                      4 => const SettingsScreen(),
                      _ => Center(child: Text(context.l10n.notFoundLabel)),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.dialog),
          ),
          title: Text(
            title,
            style: context.textTheme.titleLarge?.copyWith(
              color: context.colorScheme.error,
            ),
          ),
          content: Text(content, style: context.textTheme.bodyLarge),
          actions: [
            TextButton(
              style: const ButtonStyle(
                minimumSize: WidgetStatePropertyAll(Size(64, 48)),
              ),
              onPressed: () {
                navigationConfirmedStreamController.add(false);

                Navigator.of(context).pop(false);
              },
              child: Text(context.l10n.dialogNo),
            ),
            TextButton(
              style: const ButtonStyle(
                minimumSize: WidgetStatePropertyAll(Size(64, 48)),
              ),
              onPressed: () {
                navigationConfirmedStreamController.add(true);
                Navigator.of(context).pop(true);
              },
              child: Text(context.l10n.dialogYes),
            ),
          ],
        );
      },
    );
  }
}
