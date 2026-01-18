import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:i_gen/controllers/products_controller.dart';
import 'package:i_gen/models/product.dart';
import 'package:i_gen/utils/context_extensions.dart';

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

  void _showEditDialog({Product? product}) async {
    final result = await showDialog<Product>(
      context: context,
      builder: (context) => _ProductEditDialog(product: product),
    );

    if (result != null) {
      _saveProduct(result);
    }
  }

  void _deleteProduct(Product product) async {
    if (product.id != -1) {
      await _productsController.deleteProduct(product);
    }
    setState(() {
      _products.remove(product);
      _filterProducts();
    });
  }

  void _saveProduct(Product product) async {
    await _productsController.save(model: product.model, name: product.name);
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
    final textStyle = context.isMobile
        ? context.textTheme.titleMedium
        : context.textTheme.titleLarge;
    return Scaffold(
      appBar: AppBar(
        title: Text('Products'),
        backgroundColor: context.theme.scaffoldBackgroundColor,
        surfaceTintColor: context.colorScheme.surface,
        actionsPadding: EdgeInsets.symmetric(horizontal: 4),
        actions: [
          TextButton.icon(
            style: ButtonStyle(
              minimumSize: context.isMobile
                  ? null
                  : WidgetStatePropertyAll(Size(200, 55)),
            ),
            label: Text('New Product', style: textStyle),
            icon: Icon(Icons.add),
            onPressed: _showEditDialog,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 1020),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: 'Search',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.only(bottom: 80, left: 8, right: 8),
                  itemCount: _filteredProducts.length,
                  itemBuilder: (context, index) {
                    final product = _filteredProducts[index];
                    return ProductListItem(
                      product: product,
                      onDelete: () => _deleteProduct(product),
                      onEdit: () => _showEditDialog(product: product),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProductListItem extends StatelessWidget {
  final Product product;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const ProductListItem({
    super.key,
    required this.product,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final titleStyle = context.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.bold,
    );

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 2.0),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey.shade400, width: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${product.model} ${product.name}',
                style: titleStyle,
              ),
            ),
            IconButton(icon: Icon(Icons.edit), onPressed: onEdit),
            IconButton(icon: Icon(Icons.delete), onPressed: onDelete),
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

  @override
  void initState() {
    super.initState();
    _modelController = TextEditingController(text: widget.product?.model ?? '');
    _nameController = TextEditingController(text: widget.product?.name ?? '');
  }

  @override
  void dispose() {
    _modelController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _save() {
    if (_formKey.currentState!.validate()) {
      final newProduct = Product(
        id: widget.product?.id ?? -1,
        model: _modelController.text,
        name: _nameController.text,
      );
      Navigator.of(context).pop(newProduct);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = context.textTheme.titleLarge;
    return AlertDialog(
      title: Text(widget.product == null ? 'Add Product' : 'Edit Product'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              style: textStyle,
              controller: _modelController,
              decoration: InputDecoration(labelText: 'Model'),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a model';
                }
                return null;
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              style: textStyle,
              controller: _nameController,
              decoration: InputDecoration(labelText: 'Name'),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a name';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: Text('Save')),
      ],
    );
  }
}
