import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:i_gen/auth/auth_service.dart';
import 'package:i_gen/auth/supabase_config.dart';
import 'package:i_gen/controllers/invoice_details_controller.dart';
import 'package:i_gen/controllers/products_controller.dart';
import 'package:i_gen/models/invoice.dart';
import 'package:i_gen/models/order.dart';
import 'package:i_gen/repos/invoice_repo.dart';
import 'package:i_gen/repos/orders_repo.dart';
import 'package:i_gen/screens/invoice_screen.dart';
import 'package:i_gen/utils/context_extensions.dart';
import 'package:i_gen/widgets/invoice_details_mobile.dart';

/// Staff orders surface (Phase 10): read-only, online-first.
///
/// Employees and admins browse live orders and the customer directory;
/// there is no create/edit path here — customers order through the web
/// app. Signed-in customers see guidance toward the web app instead.
class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key, this._repo});

  final OrdersRepo? _repo;

  @override
  Widget build(BuildContext context) {
    if (!SupabaseConfig.isConfigured) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppGaps.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 48,
                color: context.colorScheme.outline,
              ),
              const SizedBox(height: AppGaps.sm),
              Text(
                context.l10n.ordersNeedSyncConfig,
                textAlign: TextAlign.center,
                style: context.textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      );
    }
    final auth = AuthService.instance;
    return StreamBuilder<UserRole?>(
      stream: auth.currentRoleStream,
      initialData: auth.currentRole,
      builder: (context, snapshot) {
        if (!auth.isSignedIn) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppGaps.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.login_outlined,
                    size: 48,
                    color: context.colorScheme.outline,
                  ),
                  const SizedBox(height: AppGaps.sm),
                  Text(
                    context.l10n.ordersSignInPrompt,
                    textAlign: TextAlign.center,
                    style: context.textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          );
        }
        if (snapshot.data == UserRole.customer) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppGaps.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.language_outlined,
                    size: 48,
                    color: context.colorScheme.outline,
                  ),
                  const SizedBox(height: AppGaps.sm),
                  Text(
                    context.l10n.ordersCustomerGuidance,
                    textAlign: TextAlign.center,
                    style: context.textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          );
        }
        return DefaultTabController(
          length: 2,
          child: Column(
            children: [
              TabBar(
                tabs: [
                  Tab(text: context.l10n.navOrders),
                  Tab(text: context.l10n.customers),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _OrdersList(repo: _repo),
                    _CustomersList(repo: _repo),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OrdersList extends StatefulWidget {
  const _OrdersList({this._repo});

  final OrdersRepo? _repo;

  @override
  State<_OrdersList> createState() => _OrdersListState();
}

class _OrdersListState extends State<_OrdersList> {
  late final OrdersRepo _repo;
  late Future<
    ({
      List<Order> orders,
      List<Customer> customers,
      Map<String, int> orderInvoices,
    })
  >
  _future;
  String? _statusFilter;

  static const _statuses = ['pending', 'completed'];

  @override
  void initState() {
    super.initState();
    _repo = widget._repo ?? OrdersRepo();
    _future = _load();
  }

  Future<
    ({
      List<Order> orders,
      List<Customer> customers,
      Map<String, int> orderInvoices,
    })
  >
  _load() async {
    final results = await Future.wait([
      _repo.getOrders(),
      _safeCustomers(),
      _orderInvoiceMap(),
    ]);
    return (
      orders: results[0] as List<Order>,
      customers: results[1] as List<Customer>,
      orderInvoices: results[2] as Map<String, int>,
    );
  }

  /// Customers are enrichment (names on cards): a failure degrades to
  /// `#id` titles via [_customerName] instead of hiding loaded orders.
  Future<List<Customer>> _safeCustomers() async {
    try {
      return await _repo.getCustomers();
    } catch (_) {
      return const [];
    }
  }

  /// Local invoices linked to server orders. Best-effort: the marker simply
  /// hides if the local db is unreachable.
  Future<Map<String, int>> _orderInvoiceMap() async {
    try {
      return await GetIt.I.get<InvoiceRepo>().getOrderInvoiceMap();
    } catch (_) {
      return const {};
    }
  }

  void _retry() => setState(() => _future = _load());

  String _customerName(
    BuildContext context,
    Map<String, Customer> byId,
    Order order,
  ) {
    final d = byId[order.customerId];
    if (d == null) {
      final id = order.customerId;
      return '#${id.length > 8 ? id.substring(0, 8) : id}';
    }
    return Localizations.localeOf(context).languageCode == 'ar'
        ? d.nameAr
        : d.nameEn;
  }

  String _statusLabel(BuildContext context, String status) {
    return switch (status) {
      'pending' => context.l10n.orderStatusPending,
      'completed' => context.l10n.orderStatusCompleted,
      // Legacy rows from before the pending/completed shrink.
      _ => status,
    };
  }

  String _linesSummary(Order order) {
    return order.items
        .map((i) => '${i.productModel ?? '—'}:${i.amount}')
        .join(' - ');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<
      ({
        List<Order> orders,
        List<Customer> customers,
        Map<String, int> orderInvoices,
      })
    >(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          final offline = snapshot.error is SocketException;
          final String message = offline
              ? context.l10n.noConnectionOrders
              : context.l10n.couldNotLoadOrders('${snapshot.error}');
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(message),
                const SizedBox(height: AppGaps.sm),
                OutlinedButton(
                  style: const ButtonStyle(
                    minimumSize: WidgetStatePropertyAll(Size(64, 48)),
                  ),
                  onPressed: _retry,
                  child: Text(context.l10n.retry),
                ),
              ],
            ),
          );
        }
        final data = snapshot.data;
        final byId = {
          for (final d in (data?.customers ?? const <Customer>[]))
            d.id: d,
        };
        final orders = (data?.orders ?? const <Order>[])
            .where((o) => _statusFilter == null || o.status == _statusFilter)
            .toList();
        final orderInvoices = data?.orderInvoices ?? const <String, int>{};
        if (orders.isEmpty) {
          return Column(
            children: [
              _filterRow(),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppGaps.lg),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.receipt_long_outlined,
                          size: 48,
                          color: context.colorScheme.outline,
                        ),
                        const SizedBox(height: AppGaps.sm),
                        Text(
                          context.l10n.noOrdersYet,
                          textAlign: TextAlign.center,
                          style: context.textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        }
        return Column(
          children: [
            _filterRow(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => _retry(),
                child: ListView.builder(
                  padding: const EdgeInsets.all(AppGaps.sm),
                  itemCount: orders.length,
                  itemBuilder: (context, index) {
                    final order = orders[index];
                    return Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.card),
                      ),
                      child: ListTile(
                        leading: const Icon(Icons.receipt_long_outlined),
                        title: Text(_customerName(context, byId, order)),
                        subtitle: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _linesSummary(order),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              context.l10n.orderSubtitle(
                                _statusLabel(context, order.status) +
                                    (orderInvoices.containsKey(order.id)
                                        ? ' · ${context.l10n.orderInvoiced}'
                                        : ''),
                                order.createdAt
                                        ?.toLocal()
                                        .toString()
                                        .split('.')
                                        .first ??
                                    '',
                              ),
                            ),
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showDetail(
                          order,
                          _customerName(context, byId, order),
                          orderInvoices[order.id],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _filterRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppGaps.sm),
      child: Row(
        children: [
          ChoiceChip(
            label: Text(context.l10n.filterAll),
            selected: _statusFilter == null,
            materialTapTargetSize: MaterialTapTargetSize.padded,
            onSelected: (_) => setState(() => _statusFilter = null),
          ),
          for (final status in _statuses)
            Padding(
              padding: const EdgeInsets.only(left: AppGaps.sm),
              child: ChoiceChip(
                label: Text(switch (status) {
                  'pending' => context.l10n.orderStatusPending,
                  'completed' => context.l10n.orderStatusCompleted,
                  _ => status,
                }),
                selected: _statusFilter == status,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onSelected: (_) => setState(
                  () => _statusFilter = _statusFilter == status ? null : status,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, String text, {bool header = false}) {
    final style = header
        ? context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)
        : context.textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Text(text, style: style),
    );
  }

  Future<void> _showDetail(
    Order order,
    String customerName,
    int? invoiceId,
  ) async {
    // Lines arrive embedded with the list query — no second fetch, so the
    // dialog never spins or fails on its own.
    final items = order.items;
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.dialog),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(customerName),
            const SizedBox(height: 2),
            Text(
              _statusLabel(context, order.status),
              style: context.textTheme.bodyMedium?.copyWith(
                color: context.colorScheme.outline,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: items.isEmpty
              ? Text(context.l10n.orderNoLines)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Table(
                      border: TableBorder.all(
                        color: context.colorScheme.surfaceDim,
                      ),
                      columnWidths: const {
                        0: FlexColumnWidth(2),
                        1: FlexColumnWidth(1),
                      },
                      children: [
                        TableRow(
                          decoration: BoxDecoration(
                            color: context.colorScheme.surfaceContainerLowest,
                          ),
                          children: [
                            _cell(
                              context,
                              context.l10n.productModel,
                              header: true,
                            ),
                            _cell(context, context.l10n.quantity, header: true),
                          ],
                        ),
                        for (final item in items)
                          TableRow(
                            children: [
                              _cell(
                                context,
                                item.productModel ?? item.productId ?? '—',
                              ),
                              _cell(context, '${item.amount}'),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
        ),
        actions: [
          if (items.isNotEmpty || invoiceId != null)
            FilledButton.tonal(
              style: const ButtonStyle(
                minimumSize: WidgetStatePropertyAll(Size(64, 48)),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                if (invoiceId != null) {
                  _openExistingInvoice(invoiceId);
                } else {
                  _openOrderInvoice(order, items, customerName);
                }
              },
              child: Text(
                invoiceId != null
                    ? context.l10n.goToInvoice
                    : context.l10n.createInvoice,
              ),
            ),
          TextButton(
            style: const ButtonStyle(
              minimumSize: WidgetStatePropertyAll(Size(64, 48)),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.close),
          ),
        ],
      ),
    );
  }

  /// Opens the linked invoice in the existing editor. Falls back to a
  /// reload (the invoice may have been deleted elsewhere) instead of
  /// pushing a dead editor.
  Future<void> _openExistingInvoice(int invoiceId) async {
    Invoice? invoice;
    try {
      invoice = await GetIt.I.get<InvoiceRepo>().getInvoiceById(invoiceId);
    } catch (_) {
      invoice = null;
    }
    if (!mounted) return;
    if (invoice == null) {
      _retry();
      return;
    }
    final controller = InvoiceDetailsController(invoice);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => context.isMobile
            ? InvoiceDetailsMobile(controller: controller)
            : InvoiceDetails(invoiceController: controller),
      ),
    );
    if (mounted) _retry();
  }

  /// Builds a prefilled invoice from the order and opens it in the existing
  /// editor (mobile grid / desktop table by platform). Unmatched lines are
  /// reported, never silently dropped; the order itself is untouched.
  void _openOrderInvoice(
    Order order,
    List<OrderItem> items,
    String customerName,
  ) async {
    final products = GetIt.I.get<ProductsController>().products;
    final matched = InvoiceDetailsController.matchOrderLines(items, products);
    if (!mounted) return;
    final controller = InvoiceDetailsController.fromCustomerOrder(
      customerName: customerName,
      currency: order.currency,
      lines: matched.rows,
      orderId: order.id,
    );
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => context.isMobile
            ? InvoiceDetailsMobile(
                controller: controller,
                orderSkipped: matched.skipped,
              )
            : InvoiceDetails(
                invoiceController: controller,
                orderSkipped: matched.skipped,
              ),
      ),
    );
    // The new invoice may now link this order: reload so the marker appears.
    if (mounted) _retry();
  }
}

class _CustomersList extends StatefulWidget {
  const _CustomersList({this._repo});

  final OrdersRepo? _repo;

  @override
  State<_CustomersList> createState() => _CustomersListState();
}

class _CustomersListState extends State<_CustomersList> {
  late final OrdersRepo _repo;
  late Future<List<Customer>> _future;

  @override
  void initState() {
    super.initState();
    _repo = widget._repo ?? OrdersRepo();
    _future = _repo.getCustomers();
  }

  void _retry() => setState(() => _future = _repo.getCustomers());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Customer>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          final offline = snapshot.error is SocketException;
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  offline
                      ? context.l10n.noConnectionCustomers
                      : context.l10n.couldNotLoadCustomers(
                          '${snapshot.error}',
                        ),
                ),
                const SizedBox(height: AppGaps.sm),
                OutlinedButton(
                  style: const ButtonStyle(
                    minimumSize: WidgetStatePropertyAll(Size(64, 48)),
                  ),
                  onPressed: _retry,
                  child: Text(context.l10n.retry),
                ),
              ],
            ),
          );
        }
        final items = snapshot.data ?? const <Customer>[];
        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppGaps.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.storefront_outlined,
                    size: 48,
                    color: context.colorScheme.outline,
                  ),
                  const SizedBox(height: AppGaps.sm),
                  Text(
                    context.l10n.noCustomersYet,
                    textAlign: TextAlign.center,
                    style: context.textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => _retry(),
          child: ListView.builder(
            padding: const EdgeInsets.all(AppGaps.sm),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final d = items[index];
              return Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.card),
                ),
                child: ListTile(
                  leading: const Icon(Icons.storefront_outlined),
                  title: Text('${d.nameEn} · ${d.nameAr}'),
                  subtitle: Text(d.phone),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
