import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class NavListener extends ChangeNotifier {
  final void Function(int oldIndex, int newIndex)? onChange;
  final Stream<bool> navigationConfirmedStream;

  NavListener(this.navigationConfirmedStream, {this.onChange}) {
    navigationConfirmedStream.listen((confirmed) {
      if (confirmed) {
        notifyListeners();
      } else {
        _value = _prevValue;
      }
    });
  }
  int _value = 0;
  int _prevValue = 0;
  int get value => _value;

  void updateIndex(int value, {bool confirmBeforeNavigation = false}) {
    if (onChange != null) {
      onChange!(_value, value);
    }
    _prevValue = _value;
    _value = value;
  }

  bool get isProductsScreen => _value == 1;
  bool get isNewInvoiceScreen => _value == 2;
}
