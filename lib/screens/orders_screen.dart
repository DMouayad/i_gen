import 'dart:io';

import 'package:flutter/material.dart';
import 'package:i_gen/auth/auth_service.dart';
import 'package:i_gen/auth/supabase_config.dart';
import 'package:i_gen/models/order.dart';
import 'package:i_gen/repos/orders_repo.dart';

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
      return const Center(
        child: Text('Orders need sync configuration — the app works offline.'),
      );
    }
    final auth = AuthService.instance;
    return StreamBuilder<UserRole?>(
      stream: auth.currentRoleStream,
      initialData: auth.currentRole,
      builder: (context, snapshot) {
        if (!auth.isSignedIn) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Sign in from Settings to view orders.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (snapshot.data == UserRole.distributor) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Distributors place and follow orders in the web app — '
                'open your welcome link to continue there.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return DefaultTabController(
          length: 2,
          child: Column(
            children: [
              const TabBar(
                tabs: [
                  Tab(text: 'Orders'),
                  Tab(text: 'Distributors'),
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
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  offline
                      ? 'No connection — connect to view live orders.'
                      : 'Could not load orders: ${snapshot.error}',
                ),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: _retry, child: const Text('Retry')),
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
              const Expanded(child: Center(child: Text('No orders yet.'))),
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
                  itemCount: orders.length,
                  itemBuilder: (context, index) {
                    final order = orders[index];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.receipt_long_outlined),
                        title: Text('${order.total} ${order.currency}'),
                        subtitle: Text(
                          '${order.status} · ${order.createdAt?.toLocal().toString().split('.').first ?? ''}',
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
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('All'),
            selected: _statusFilter == null,
            onSelected: (_) => setState(() => _statusFilter = null),
          ),
          for (final status in _statuses)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: ChoiceChip(
                label: Text(status),
                selected: _statusFilter == status,
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
      error = e is SocketException ? 'No connection.' : '$e';
    }
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Order · ${order.status}'),
        content: SizedBox(
          width: 400,
          child: error != null
              ? Text(error)
              : items.isEmpty
              ? const Text('No lines on this order.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final item in items)
                      ListTile(
                        dense: true,
                        title: Text('×${item.amount}'),
                        trailing: Text('${item.price}'),
                      ),
                    const Divider(),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'Total: ${order.total} ${order.currency}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
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
                      ? 'No connection — connect to view distributors.'
                      : 'Could not load distributors: ${snapshot.error}',
                ),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: _retry, child: const Text('Retry')),
              ],
            ),
          );
        }
        final items = snapshot.data ?? const <Distributor>[];
        if (items.isEmpty) {
          return const Center(
            child: Text('No distributors yet — invite one from Settings.'),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => _retry(),
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final d = items[index];
              return Card(
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
