import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_gen/controllers/invoice_details_controller.dart';
import 'package:i_gen/l10n/app_localizations.dart';
import 'package:i_gen/widgets/invoice_discount_footer.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('typing a discount reaches controller.discount', (tester) async {
    final controller = InvoiceDetailsController(null);
    await tester.pumpWidget(
      _wrap(InvoiceDiscountFooter(controller: controller)),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), '10');
    await tester.pump();

    expect(controller.discount, 10);
    expect(controller.hasUnsavedChanges, isTrue);
  });

  testWidgets('saved discount redisplays on reopen', (tester) async {
    final controller = InvoiceDetailsController(null);
    controller.discount = 7.5;
    await tester.pumpWidget(
      _wrap(InvoiceDiscountFooter(controller: controller)),
    );
    await tester.pump();

    expect(find.text('7.5'), findsOneWidget);
  });
}
