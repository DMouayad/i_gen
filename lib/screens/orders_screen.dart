import 'dart:io';

import 'package:flutter/material.dart';
import 'package:i_gen/auth/auth_service.dart';
import 'package:i_gen/auth/supabase_config.dart';
import 'package:i_gen/models/order.dart';
import 'package:i_gen/repos/orders_repo.dart';
import 'package:i_gen/utils/context_extensions.dart';

/// Staff orders surface (Phase 10): read-only, online-first.
///
/// Employees and admins browse live orders and the distributor directory;
/// there is no create/edit path here — distributors order through the web
/// app. Signed-in distributors see guidance toward the web app instead.
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
        if (snapshot.data == UserRole.distributor) {
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
                    context.l10n.ordersDistributorGuidance,
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
                  Tab(text: context.l10n.distributors),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _OrdersList(repo: _repo),
                    _DistributorsList(repo: _repo),
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
  late Future<List<Order>> _future;
  String? _statusFilter;

  static const _statuses = ['pending', 'confirmed', 'delivered', 'cancelled'];

  @override
  void initState() {
    super.initState();
    _repo = widget._repo ?? OrdersRepo();
    _future = _repo.getOrders();
  }

  void _retry() => setState(() => _future = _repo.getOrders());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Order>>(
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
        final orders = (snapshot.data ?? const <Order>[])
            .where((o) => _statusFilter == null || o.status == _statusFilter)
            .toList();
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
                        title: Text(
                          context.l10n.orderAmountTitle(
                            order.total.toString(),
                            order.currency,
                          ),
                        ),
                        subtitle: Text(
                          context.l10n.orderSubtitle(
                            order.status,
                            order.createdAt
                                    ?.toLocal()
                                    .toString()
                                    .split('.')
                                    .first ??
                                '',
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showDetail(order),
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
                  'confirmed' => context.l10n.orderStatusConfirmed,
                  'delivered' => context.l10n.orderStatusDelivered,
                  'cancelled' => context.l10n.orderStatusCancelled,
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

  Future<void> _showDetail(Order order) async {
    List<OrderItem> items = const [];
    String? error;
    try {
      items = await _repo.getOrderItems(order.id);
    } catch (e) {
      error = e is SocketException
          ? context.l10n.noConnectionShort
          : context.l10n.unexpectedError('$e');
    }
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.dialog),
        ),
        title: Text(context.l10n.orderDetailTitle(order.status)),
        content: SizedBox(
          width: 400,
          child: error != null
              ? Text(error)
              : items.isEmpty
              ? Text(context.l10n.orderNoLines)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final item in items)
                      ListTile(
                        dense: true,
                        title: Text(
                          context.l10n.orderItemAmount(item.amount.toString()),
                        ),
                        trailing: Text('${item.price}'),
                      ),
                    const Divider(),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${context.l10n.total}: ${order.total} ${order.currency}',
                        style: context.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        actions: [
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
}

class _DistributorsList extends StatefulWidget {
  const _DistributorsList({this._repo});

  final OrdersRepo? _repo;

  @override
  State<_DistributorsList> createState() => _DistributorsListState();
}

class _DistributorsListState extends State<_DistributorsList> {
  late final OrdersRepo _repo;
  late Future<List<Distributor>> _future;

  @override
  void initState() {
    super.initState();
    _repo = widget._repo ?? OrdersRepo();
    _future = _repo.getDistributors();
  }

  void _retry() => setState(() => _future = _repo.getDistributors());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Distributor>>(
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
                      ? context.l10n.noConnectionDistributors
                      : context.l10n.couldNotLoadDistributors(
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
        final items = snapshot.data ?? const <Distributor>[];
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
                    context.l10n.noDistributorsYet,
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
