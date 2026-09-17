import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:i_gen/auth/auth_service.dart';
import 'package:i_gen/controllers/products_controller.dart';
import 'package:i_gen/models/product.dart';
import 'package:i_gen/repos/sync_trigger.dart';
import 'package:i_gen/utils/context_extensions.dart';
import 'package:i_gen/widgets/size_multi_select.dart';
import 'package:i_gen/widgets/sync_button.dart';

class ProductsScreeMobile extends StatefulWidget {
  const ProductsScreeMobile({
    super.key,
    required this.unsavedProductCountNotifier,
  });
  final ValueNotifier<int> unsavedProductCountNotifier;

  @override
  State<ProductsScreeMobile> createState() => _ProductsScreeMobileState();
}

class _ProductsScreeMobileState extends State<ProductsScreeMobile> {
  final ProductsController _productsController = GetIt.I.get();
  late List<Product> _products;
  List<Product> _filteredProducts = [];
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _products = _productsController.products.values.toList();
    _filteredProducts = _products;
    _searchController.addListener(_filterProducts);
  }

  void _filterProducts() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredProducts = _products.where((product) {
        return product.name.toLowerCase().contains(query) ||
            product.model.toLowerCase().contains(query);
      }).toList();
    });
  }

  /// Manual refresh (pull-to-refresh): sync, then reload below.
  Future<void> _refresh() async {
    await SyncTrigger.instance.syncNow();
    await _reload();
  }

  /// Post-sync reload hook for the header SyncButton: refill the list.
  /// Plain setState refill is safe here (no grid state to lose).
  Future<void> _reload() async {
    await _productsController.reload();
    if (!mounted) return;
    setState(() {
      _products = _productsController.products.values.toList();
    });
    _filterProducts();
  }

  void _showEditDialog({Product? product}) async {
    final result = await showDialog<Product>(
      context: context,
      builder: (context) => _ProductEditDialog(product: product),
    );

    if (result != null) {
      _saveProduct(result);
    }
  }

  Future<void> _confirmDelete(Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.dialog),
        ),
        title: Text(context.l10n.deleteConfirmTitle),
        content: Text(context.l10n.deleteConfirmMessage),
        actions: [
          TextButton(
            style: const ButtonStyle(
              minimumSize: WidgetStatePropertyAll(Size(64, 48)),
            ),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.cancelButton),
          ),
          FilledButton(
            style: const ButtonStyle(
              minimumSize: WidgetStatePropertyAll(Size(64, 48)),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.deleteButton),
          ),
        ],
      ),
    );
    if (confirmed == true) _deleteProduct(product);
  }

  void _deleteProduct(Product product) async {
    if (product.id != -1) {
      await _productsController.deleteProduct(product);
    }
    if (!mounted) return;
    _products.remove(product);
    _filterProducts();
  }

  void _saveProduct(Product product) async {
    await _productsController.save(
      model: product.model,
      name: product.name,
      sizes: product.sizes,
    );
    // Refresh list from db
    _products = _productsController.products.values.toList();
    _filterProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthService.instance;
    return StreamBuilder<UserRole?>(
      stream: auth.currentRoleStream,
      initialData: auth.currentRole,
      builder: (context, snapshot) {
        // Fail-open while signed out: local editing keeps working offline;
        // the database remains the enforcer for signed-in roles.
        final readOnly = auth.isSignedIn && !auth.canEditCatalog;
        return Scaffold(
          appBar: AppBar(
            title: Text(context.l10n.navProducts),
            backgroundColor: context.colorScheme.surface,
            surfaceTintColor: context.colorScheme.surface,
            actions: [SyncButton(onSynced: _reload)],
          ),
          floatingActionButton: readOnly
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => _showEditDialog(),
                  icon: const Icon(Icons.add),
                  label: Text(context.l10n.newProduct),
                ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1024),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppGaps.sm),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        labelText: context.l10n.searchLabel,
                        prefixIcon: const Icon(Icons.search_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadii.control),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: _filteredProducts.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.inventory_2_outlined,
                                  size: 48,
                                  color: context.colorScheme.outline,
                                ),
                                const SizedBox(height: AppGaps.sm),
                                Text(
                                  context.l10n.noProductsFound,
                                  textAlign: TextAlign.center,
                                  style: context.textTheme.bodyLarge,
                                ),
                                if (!readOnly) ...[
                                  const SizedBox(height: AppGaps.md),
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      minimumSize: const Size(64, 48),
                                    ),
                                    onPressed: () => _showEditDialog(),
                                    icon: const Icon(Icons.add),
                                    label: Text(context.l10n.newProduct),
                                  ),
                                ],
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _refresh,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(AppGaps.sm),
                              itemCount: _filteredProducts.length,
                              itemBuilder: (context, index) {
                                final product = _filteredProducts[index];
                                return ProductListItem(
                                  product: product,
                                  showActions: !readOnly,
                                  onDelete: () => _confirmDelete(product),
                                  onEdit: () =>
                                      _showEditDialog(product: product),
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class ProductListItem extends StatelessWidget {
  final Product product;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  /// When false the edit/delete buttons are hidden (role read-only).
  final bool showActions;

  const ProductListItem({
    super.key,
    required this.product,
    required this.onDelete,
    required this.onEdit,
    this.showActions = true,
  });

  @override
  Widget build(BuildContext context) {
    final titleStyle = context.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.bold,
    );

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: AppGaps.xs),
      color: context.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(
        side: BorderSide(width: 0.5, color: context.colorScheme.outline),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppGaps.md,
          vertical: AppGaps.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${product.model} ${product.name}', style: titleStyle),
                  if (product.sizes.isNotEmpty)
                    Text(
                      product.sizes.join(', '),
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (showActions) ...[
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: onEdit,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: onDelete,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProductEditDialog extends StatefulWidget {
  final Product? product;

  const _ProductEditDialog({this.product});

  @override
  _ProductEditDialogState createState() => _ProductEditDialogState();
}

class _ProductEditDialogState extends State<_ProductEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _modelController;
  late TextEditingController _nameController;
  late TextEditingController _sizesController;

  @override
  void initState() {
    super.initState();
    _modelController = TextEditingController(text: widget.product?.model ?? '');
    _nameController = TextEditingController(text: widget.product?.name ?? '');
    _sizesController = TextEditingController(
      text: widget.product?.sizes.join(', ') ?? '',
    );
  }

  @override
  void dispose() {
    _modelController.dispose();
    _nameController.dispose();
    _sizesController.dispose();
    super.dispose();
  }

  void _save() {
    if (_formKey.currentState!.validate()) {
      final newProduct = Product(
        id: widget.product?.id ?? -1,
        model: _modelController.text,
        name: _nameController.text,
        sizes: Product.parseSizeList(_sizesController.text),
      );
      Navigator.of(context).pop(newProduct);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = context.textTheme.titleLarge;
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.dialog),
      ),
      title: Text(
        widget.product == null
            ? context.l10n.addProduct
            : context.l10n.editProduct,
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              style: textStyle,
              controller: _modelController,
              decoration: InputDecoration(
                labelText: context.l10n.productModel,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.control),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return context.l10n.productModelRequired;
                }
                return null;
              },
            ),
            const SizedBox(height: AppGaps.sm),
            TextFormField(
              style: textStyle,
              controller: _nameController,
              decoration: InputDecoration(
                labelText: context.l10n.productNameColumn,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.control),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return context.l10n.productNameRequired;
                }
                return null;
              },
            ),
            const SizedBox(height: AppGaps.sm),
            TextFormField(
              style: textStyle,
              controller: _sizesController,
              readOnly: true,
              onTap: () async {
                final picked = await showSizeMultiSelect(
                  context,
                  initial: Product.parseSizeList(_sizesController.text),
                  title: '${_modelController.text} · ${_nameController.text}',
                );
                if (picked == null) return;
                setState(() {
                  _sizesController.text = picked.join(', ');
                });
              },
              decoration: InputDecoration(
                labelText: context.l10n.sizesColumn,
                hintText: 'S, M, L',
                suffixIcon: const Icon(Icons.arrow_drop_down),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.control),
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
          child: Text(context.l10n.cancelButton),
        ),
        FilledButton(
          style: const ButtonStyle(
            minimumSize: WidgetStatePropertyAll(Size(64, 48)),
          ),
          onPressed: _save,
          child: Text(context.l10n.save),
        ),
      ],
    );
  }
}
