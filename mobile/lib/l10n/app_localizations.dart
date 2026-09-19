import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// Product model name column header
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get productModel;

  /// Product description column header
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get productDescription;

  /// Quantity column header
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get quantity;

  /// Unit price column header
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get price;

  /// Line total column header
  ///
  /// In en, this message translates to:
  /// **'Line Total'**
  String get lineTotal;

  /// Invoice total label
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get total;

  /// Button to add an invoice line item
  ///
  /// In en, this message translates to:
  /// **'Add Item'**
  String get addItem;

  /// No description provided for @createInvoiceBtn.
  ///
  /// In en, this message translates to:
  /// **'Create invoice'**
  String get createInvoiceBtn;

  /// No description provided for @sortLabel.
  ///
  /// In en, this message translates to:
  /// **'SORT'**
  String get sortLabel;

  /// No description provided for @sortAz.
  ///
  /// In en, this message translates to:
  /// **'From A-Z'**
  String get sortAz;

  /// No description provided for @sortZa.
  ///
  /// In en, this message translates to:
  /// **'From Z-A'**
  String get sortZa;

  /// No description provided for @sortNewest.
  ///
  /// In en, this message translates to:
  /// **'From Newest'**
  String get sortNewest;

  /// No description provided for @sortOldest.
  ///
  /// In en, this message translates to:
  /// **'From Oldest'**
  String get sortOldest;

  /// No description provided for @sortNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get sortNone;

  /// No description provided for @noInvoicesFound.
  ///
  /// In en, this message translates to:
  /// **'No invoices found'**
  String get noInvoicesFound;

  /// No description provided for @archiveEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Saved invoices will appear here.'**
  String get archiveEmptyHint;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @deleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete?'**
  String get deleteConfirmTitle;

  /// No description provided for @deleteConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone.'**
  String get deleteConfirmMessage;

  /// No description provided for @invoiceUnsavedTitle.
  ///
  /// In en, this message translates to:
  /// **'Invoice was not saved'**
  String get invoiceUnsavedTitle;

  /// No description provided for @invoiceUnsavedMessage.
  ///
  /// In en, this message translates to:
  /// **'Your invoice has unsaved changes, do you want to continue?'**
  String get invoiceUnsavedMessage;

  /// No description provided for @unsavedProductsTitle.
  ///
  /// In en, this message translates to:
  /// **'Unsaved Products'**
  String get unsavedProductsTitle;

  /// No description provided for @unsavedProductsMessage.
  ///
  /// In en, this message translates to:
  /// **'You have unsaved products, do you want to continue?'**
  String get unsavedProductsMessage;

  /// No description provided for @unsavedPricingCategoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Unsaved Pricing Category'**
  String get unsavedPricingCategoryTitle;

  /// No description provided for @unsavedPricingCategoryMessage.
  ///
  /// In en, this message translates to:
  /// **'You have unsaved pricing category, do you want to continue?'**
  String get unsavedPricingCategoryMessage;

  /// No description provided for @unsavedProductPricingTitle.
  ///
  /// In en, this message translates to:
  /// **'Unsaved Product Pricing'**
  String get unsavedProductPricingTitle;

  /// No description provided for @unsavedProductPricingMessage.
  ///
  /// In en, this message translates to:
  /// **'You have unsaved product pricing, do you want to continue?'**
  String get unsavedProductPricingMessage;

  /// No description provided for @navInvoices.
  ///
  /// In en, this message translates to:
  /// **'Invoices'**
  String get navInvoices;

  /// No description provided for @navProducts.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get navProducts;

  /// No description provided for @navPricing.
  ///
  /// In en, this message translates to:
  /// **'Pricing'**
  String get navPricing;

  /// No description provided for @navOrders.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get navOrders;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @notFoundLabel.
  ///
  /// In en, this message translates to:
  /// **'404'**
  String get notFoundLabel;

  /// No description provided for @dialogYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get dialogYes;

  /// No description provided for @dialogNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get dialogNo;

  /// No description provided for @inviteLinkAcceptedChoosePassword.
  ///
  /// In en, this message translates to:
  /// **'Link accepted — choose a password to finish.'**
  String get inviteLinkAcceptedChoosePassword;

  /// No description provided for @inviteLinkAcceptedSignIn.
  ///
  /// In en, this message translates to:
  /// **'Link accepted — now sign in with your new password.'**
  String get inviteLinkAcceptedSignIn;

  /// No description provided for @inviteLinkAcceptFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not accept the link — try again.'**
  String get inviteLinkAcceptFailed;

  /// No description provided for @invitePasswordSetDone.
  ///
  /// In en, this message translates to:
  /// **'Password set — sign in with your email and password.'**
  String get invitePasswordSetDone;

  /// No description provided for @acceptInvitationTitle.
  ///
  /// In en, this message translates to:
  /// **'Accept invitation'**
  String get acceptInvitationTitle;

  /// No description provided for @choosePasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Choose password'**
  String get choosePasswordLabel;

  /// No description provided for @setPasswordButton.
  ///
  /// In en, this message translates to:
  /// **'Set password'**
  String get setPasswordButton;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @saveAsImage.
  ///
  /// In en, this message translates to:
  /// **'Save as image'**
  String get saveAsImage;

  /// No description provided for @saveAsPdf.
  ///
  /// In en, this message translates to:
  /// **'Save as PDF'**
  String get saveAsPdf;

  /// No description provided for @shareAsImage.
  ///
  /// In en, this message translates to:
  /// **'Share as image'**
  String get shareAsImage;

  /// No description provided for @shareAsPdf.
  ///
  /// In en, this message translates to:
  /// **'Share as PDF'**
  String get shareAsPdf;

  /// No description provided for @invoiceTitle.
  ///
  /// In en, this message translates to:
  /// **'INVOICE'**
  String get invoiceTitle;

  /// No description provided for @ordersNeedSyncConfig.
  ///
  /// In en, this message translates to:
  /// **'Orders need sync configuration — the app works offline.'**
  String get ordersNeedSyncConfig;

  /// No description provided for @ordersSignInPrompt.
  ///
  /// In en, this message translates to:
  /// **'Sign in from Settings to view orders.'**
  String get ordersSignInPrompt;

  /// No description provided for @ordersCustomerGuidance.
  ///
  /// In en, this message translates to:
  /// **'Customers place and follow orders in the web app — open your welcome link to continue there.'**
  String get ordersCustomerGuidance;

  /// No description provided for @customers.
  ///
  /// In en, this message translates to:
  /// **'Customers'**
  String get customers;

  /// No description provided for @noConnectionOrders.
  ///
  /// In en, this message translates to:
  /// **'No connection — connect to view live orders.'**
  String get noConnectionOrders;

  /// No description provided for @couldNotLoadOrders.
  ///
  /// In en, this message translates to:
  /// **'Could not load orders: {error}'**
  String couldNotLoadOrders(String error);

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @noOrdersYet.
  ///
  /// In en, this message translates to:
  /// **'No orders yet.'**
  String get noOrdersYet;

  /// No description provided for @newOrderChannelName.
  ///
  /// In en, this message translates to:
  /// **'New orders'**
  String get newOrderChannelName;

  /// No description provided for @newOrderChannelDescription.
  ///
  /// In en, this message translates to:
  /// **'Alerts when a customer places an order.'**
  String get newOrderChannelDescription;

  /// No description provided for @newOrderTitle.
  ///
  /// In en, this message translates to:
  /// **'New order'**
  String get newOrderTitle;

  /// No description provided for @newOrderBody.
  ///
  /// In en, this message translates to:
  /// **'{total} {currency}'**
  String newOrderBody(String total, String currency);

  /// No description provided for @orderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{status} · {date}'**
  String orderSubtitle(String status, String date);

  /// No description provided for @filterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get filterAll;

  /// No description provided for @orderStatusPending.
  ///
  /// In en, this message translates to:
  /// **'pending'**
  String get orderStatusPending;

  /// No description provided for @orderStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'completed'**
  String get orderStatusCompleted;

  /// No description provided for @unexpectedError.
  ///
  /// In en, this message translates to:
  /// **'{error}'**
  String unexpectedError(String error);

  /// No description provided for @orderNoLines.
  ///
  /// In en, this message translates to:
  /// **'No lines on this order.'**
  String get orderNoLines;

  /// No description provided for @orderInvoiced.
  ///
  /// In en, this message translates to:
  /// **'Invoiced'**
  String get orderInvoiced;

  /// No description provided for @createInvoice.
  ///
  /// In en, this message translates to:
  /// **'Create invoice'**
  String get createInvoice;

  /// No description provided for @goToInvoice.
  ///
  /// In en, this message translates to:
  /// **'Go to invoice'**
  String get goToInvoice;

  /// No description provided for @orderSkippedLines.
  ///
  /// In en, this message translates to:
  /// **'{count} lines skipped (product missing)'**
  String orderSkippedLines(int count);

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @noConnectionCustomers.
  ///
  /// In en, this message translates to:
  /// **'No connection — connect to view customers.'**
  String get noConnectionCustomers;

  /// No description provided for @couldNotLoadCustomers.
  ///
  /// In en, this message translates to:
  /// **'Could not load customers: {error}'**
  String couldNotLoadCustomers(String error);

  /// No description provided for @noCustomersYet.
  ///
  /// In en, this message translates to:
  /// **'No customers yet — invite one from Settings.'**
  String get noCustomersYet;

  /// No description provided for @productIdColumn.
  ///
  /// In en, this message translates to:
  /// **'ID'**
  String get productIdColumn;

  /// No description provided for @productAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'A product with model {model} already exists'**
  String productAlreadyExists(String model);

  /// No description provided for @productNameColumn.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get productNameColumn;

  /// No description provided for @productActionsColumn.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get productActionsColumn;

  /// No description provided for @addProduct.
  ///
  /// In en, this message translates to:
  /// **'Add Product'**
  String get addProduct;

  /// No description provided for @unsavedProductsCount.
  ///
  /// In en, this message translates to:
  /// **'You have {count} unsaved products'**
  String unsavedProductsCount(int count);

  /// No description provided for @catalogReadOnly.
  ///
  /// In en, this message translates to:
  /// **'Catalog is read-only for your role — ask an admin for changes.'**
  String get catalogReadOnly;

  /// No description provided for @newProduct.
  ///
  /// In en, this message translates to:
  /// **'New Product'**
  String get newProduct;

  /// No description provided for @editProduct.
  ///
  /// In en, this message translates to:
  /// **'Edit Product'**
  String get editProduct;

  /// No description provided for @searchLabel.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchLabel;

  /// No description provided for @productModelRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a model'**
  String get productModelRequired;

  /// No description provided for @productNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a name'**
  String get productNameRequired;

  /// No description provided for @cancelButton.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelButton;

  /// No description provided for @settingsOfflineFirstNote.
  ///
  /// In en, this message translates to:
  /// **'Your edits are saved on this device first and sync when you are online and signed in.'**
  String get settingsOfflineFirstNote;

  /// No description provided for @settingsStagingNote.
  ///
  /// In en, this message translates to:
  /// **'Your edits are saved on this device. Sync activates after the staging checklist passes.'**
  String get settingsStagingNote;

  /// No description provided for @syncNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Sync not configured'**
  String get syncNotConfigured;

  /// No description provided for @syncNotConfiguredHint.
  ///
  /// In en, this message translates to:
  /// **'The app works fully offline. Add Supabase credentials to enable sign-in.'**
  String get syncNotConfiguredHint;

  /// No description provided for @signedInFallback.
  ///
  /// In en, this message translates to:
  /// **'Signed in'**
  String get signedInFallback;

  /// No description provided for @syncAccountNote.
  ///
  /// In en, this message translates to:
  /// **'Your edits sync to this account.'**
  String get syncAccountNote;

  /// No description provided for @syncAccountRoleNote.
  ///
  /// In en, this message translates to:
  /// **'Your edits sync to this account. Role: {role}.'**
  String syncAccountRoleNote(String role);

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @signInToSync.
  ///
  /// In en, this message translates to:
  /// **'Sign in to sync'**
  String get signInToSync;

  /// No description provided for @signInInviteHint.
  ///
  /// In en, this message translates to:
  /// **'Accounts are created by your admin — ask for a WhatsApp invite link.'**
  String get signInInviteHint;

  /// No description provided for @emailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get emailLabel;

  /// No description provided for @passwordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordLabel;

  /// No description provided for @signInAction.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signInAction;

  /// No description provided for @haveInviteLinkTitle.
  ///
  /// In en, this message translates to:
  /// **'Have an invite link? Paste it to set your password.'**
  String get haveInviteLinkTitle;

  /// No description provided for @inviteLinkFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp invite link'**
  String get inviteLinkFieldLabel;

  /// No description provided for @inviteLinkFieldHint.
  ///
  /// In en, this message translates to:
  /// **'Paste the full link here'**
  String get inviteLinkFieldHint;

  /// No description provided for @acceptInviteLink.
  ///
  /// In en, this message translates to:
  /// **'Accept invite link'**
  String get acceptInviteLink;

  /// No description provided for @loginPreview.
  ///
  /// In en, this message translates to:
  /// **'Login preview: {slug}@'**
  String loginPreview(String slug);

  /// No description provided for @inviteUsersTitle.
  ///
  /// In en, this message translates to:
  /// **'Invite users'**
  String get inviteUsersTitle;

  /// No description provided for @inviteUsersHint.
  ///
  /// In en, this message translates to:
  /// **'Send the generated link over WhatsApp. The user sets their own password — nothing secret stays in chat.'**
  String get inviteUsersHint;

  /// No description provided for @nameArabicLabel.
  ///
  /// In en, this message translates to:
  /// **'Name (Arabic)'**
  String get nameArabicLabel;

  /// No description provided for @nameEnglishLabel.
  ///
  /// In en, this message translates to:
  /// **'Name (English)'**
  String get nameEnglishLabel;

  /// No description provided for @phoneWhatsappLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone (WhatsApp)'**
  String get phoneWhatsappLabel;

  /// No description provided for @roleFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get roleFieldLabel;

  /// No description provided for @roleEmployee.
  ///
  /// In en, this message translates to:
  /// **'Employee'**
  String get roleEmployee;

  /// No description provided for @roleCustomer.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get roleCustomer;

  /// No description provided for @inviteActionLabel.
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get inviteActionLabel;

  /// No description provided for @inviteModeNew.
  ///
  /// In en, this message translates to:
  /// **'New invite'**
  String get inviteModeNew;

  /// No description provided for @inviteModeResend.
  ///
  /// In en, this message translates to:
  /// **'Resend link'**
  String get inviteModeResend;

  /// No description provided for @inviteModeRecovery.
  ///
  /// In en, this message translates to:
  /// **'Reset password'**
  String get inviteModeRecovery;

  /// No description provided for @loginEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Login: {email}'**
  String loginEmailLabel(String email);

  /// No description provided for @inviteShareText.
  ///
  /// In en, this message translates to:
  /// **'Your account: {email}\\nOpen this link to set your password:\\n{link}'**
  String inviteShareText(String email, String link);

  /// No description provided for @inviteCopiedHint.
  ///
  /// In en, this message translates to:
  /// **'Copied — forward it over WhatsApp.'**
  String get inviteCopiedHint;

  /// No description provided for @copyForWhatsapp.
  ///
  /// In en, this message translates to:
  /// **'Copy for WhatsApp'**
  String get copyForWhatsapp;

  /// No description provided for @createInviteLink.
  ///
  /// In en, this message translates to:
  /// **'Create invite link'**
  String get createInviteLink;

  /// No description provided for @resendInviteLink.
  ///
  /// In en, this message translates to:
  /// **'Resend invite link'**
  String get resendInviteLink;

  /// No description provided for @sendPasswordResetLink.
  ///
  /// In en, this message translates to:
  /// **'Send password-reset link'**
  String get sendPasswordResetLink;

  /// No description provided for @newInvoice.
  ///
  /// In en, this message translates to:
  /// **'New invoice'**
  String get newInvoice;

  /// No description provided for @saveButton.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveButton;

  /// No description provided for @previewButton.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get previewButton;

  /// No description provided for @grandTotal.
  ///
  /// In en, this message translates to:
  /// **'Grand total: {value}'**
  String grandTotal(num value);

  /// No description provided for @invoiceSaved.
  ///
  /// In en, this message translates to:
  /// **'Invoice saved · {value}'**
  String invoiceSaved(num value);

  /// No description provided for @customerNameHint.
  ///
  /// In en, this message translates to:
  /// **'Customer name'**
  String get customerNameHint;

  /// No description provided for @discount.
  ///
  /// In en, this message translates to:
  /// **'Discount'**
  String get discount;

  /// No description provided for @itemsCount.
  ///
  /// In en, this message translates to:
  /// **'Items ({count})'**
  String itemsCount(int count);

  /// No description provided for @customPriceList.
  ///
  /// In en, this message translates to:
  /// **'Custom ({currency})'**
  String customPriceList(String currency);

  /// No description provided for @priceCategoryOption.
  ///
  /// In en, this message translates to:
  /// **'{name} ({currency})'**
  String priceCategoryOption(String name, String currency);

  /// No description provided for @removeButton.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeButton;

  /// No description provided for @searchProductHint.
  ///
  /// In en, this message translates to:
  /// **'Search product...'**
  String get searchProductHint;

  /// No description provided for @productSuggestion.
  ///
  /// In en, this message translates to:
  /// **'{model}: {name}'**
  String productSuggestion(String model, String name);

  /// No description provided for @noProductsFound.
  ///
  /// In en, this message translates to:
  /// **'No products found'**
  String get noProductsFound;

  /// No description provided for @goBack.
  ///
  /// In en, this message translates to:
  /// **'Go back'**
  String get goBack;

  /// No description provided for @textSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Text Size is {size}'**
  String textSizeLabel(int size);

  /// No description provided for @editButton.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get editButton;

  /// No description provided for @exportAsImage.
  ///
  /// In en, this message translates to:
  /// **'Export As Image'**
  String get exportAsImage;

  /// No description provided for @exportAsPdf.
  ///
  /// In en, this message translates to:
  /// **'Export As PDF'**
  String get exportAsPdf;

  /// No description provided for @billTo.
  ///
  /// In en, this message translates to:
  /// **'BILL TO'**
  String get billTo;

  /// No description provided for @thankYouNote.
  ///
  /// In en, this message translates to:
  /// **'Thank you for your business'**
  String get thankYouNote;

  /// No description provided for @unitPrice.
  ///
  /// In en, this message translates to:
  /// **'Unit Price'**
  String get unitPrice;

  /// No description provided for @subtotal.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get subtotal;

  /// No description provided for @selectPriceList.
  ///
  /// In en, this message translates to:
  /// **'Select price list'**
  String get selectPriceList;

  /// No description provided for @discardChangesTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard Changes?'**
  String get discardChangesTitle;

  /// No description provided for @discardChangesMessage.
  ///
  /// In en, this message translates to:
  /// **'You have unsaved changes. Are you sure you want to discard them?'**
  String get discardChangesMessage;

  /// No description provided for @keepEditing.
  ///
  /// In en, this message translates to:
  /// **'Keep Editing'**
  String get keepEditing;

  /// No description provided for @discardButton.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discardButton;

  /// No description provided for @priceCategoryColumnTitle.
  ///
  /// In en, this message translates to:
  /// **'{title} ({currency})'**
  String priceCategoryColumnTitle(String title, String currency);

  /// No description provided for @saveAllButton.
  ///
  /// In en, this message translates to:
  /// **'Save All'**
  String get saveAllButton;

  /// No description provided for @newPriceList.
  ///
  /// In en, this message translates to:
  /// **'New List'**
  String get newPriceList;

  /// No description provided for @pricingReadOnlyMessage.
  ///
  /// In en, this message translates to:
  /// **'Pricing is read-only for your role — ask an admin for changes.'**
  String get pricingReadOnlyMessage;

  /// No description provided for @editOrDeleteList.
  ///
  /// In en, this message translates to:
  /// **'Edit or Delete this list'**
  String get editOrDeleteList;

  /// No description provided for @deleteButton.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteButton;

  /// No description provided for @priceCategoryNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get priceCategoryNameLabel;

  /// No description provided for @priceCategoryNameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter name'**
  String get priceCategoryNameHint;

  /// No description provided for @nameRequiredError.
  ///
  /// In en, this message translates to:
  /// **'Name is required'**
  String get nameRequiredError;

  /// No description provided for @nameAlreadyExistsError.
  ///
  /// In en, this message translates to:
  /// **'Name already exists'**
  String get nameAlreadyExistsError;

  /// No description provided for @currencyLabel.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get currencyLabel;

  /// No description provided for @currencyHint.
  ///
  /// In en, this message translates to:
  /// **'Enter currency'**
  String get currencyHint;

  /// No description provided for @syncCompleted.
  ///
  /// In en, this message translates to:
  /// **'Sync completed.'**
  String get syncCompleted;

  /// No description provided for @syncFailed.
  ///
  /// In en, this message translates to:
  /// **'Sync failed: {error}'**
  String syncFailed(String error);

  /// No description provided for @syncUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Sync unavailable'**
  String get syncUnavailable;

  /// No description provided for @syncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get syncNow;

  /// No description provided for @lastSyncLabel.
  ///
  /// In en, this message translates to:
  /// **'Last sync: {time}'**
  String lastSyncLabel(String time);

  /// No description provided for @queuedChanges.
  ///
  /// In en, this message translates to:
  /// **'Queued changes: {count}{breakdown}'**
  String queuedChanges(int count, String breakdown);

  /// No description provided for @lastDownloadLabel.
  ///
  /// In en, this message translates to:
  /// **'Last download: {counters}'**
  String lastDownloadLabel(String counters);

  /// No description provided for @skippedRowsLabel.
  ///
  /// In en, this message translates to:
  /// **'Held for retry: {counters}'**
  String skippedRowsLabel(String counters);

  /// No description provided for @syncNeedsAttentionDetail.
  ///
  /// In en, this message translates to:
  /// **'Sync needs attention:\\n{error}'**
  String syncNeedsAttentionDetail(String error);

  /// No description provided for @parkedEvictedWarning.
  ///
  /// In en, this message translates to:
  /// **'Warning: {count} parked op(s) evicted this session (cap reached).'**
  String parkedEvictedWarning(int count);

  /// No description provided for @syncingStatus.
  ///
  /// In en, this message translates to:
  /// **'Syncing…'**
  String get syncingStatus;

  /// No description provided for @syncErrorStatus.
  ///
  /// In en, this message translates to:
  /// **'Sync error'**
  String get syncErrorStatus;

  /// No description provided for @unknownError.
  ///
  /// In en, this message translates to:
  /// **'Unknown error.'**
  String get unknownError;

  /// No description provided for @syncedStatus.
  ///
  /// In en, this message translates to:
  /// **'Synced'**
  String get syncedStatus;

  /// No description provided for @syncedWithPending.
  ///
  /// In en, this message translates to:
  /// **'Synced • {count} change(s) queued'**
  String syncedWithPending(int count);

  /// No description provided for @syncNeedsAttention.
  ///
  /// In en, this message translates to:
  /// **'Sync needs attention'**
  String get syncNeedsAttention;

  /// No description provided for @waitingToSync.
  ///
  /// In en, this message translates to:
  /// **'Waiting to sync • {count} change(s) queued'**
  String waitingToSync(int count);

  /// No description provided for @upToDateStatus.
  ///
  /// In en, this message translates to:
  /// **'Up to date'**
  String get upToDateStatus;

  /// No description provided for @neverSynced.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get neverSynced;

  /// No description provided for @sizesColumn.
  ///
  /// In en, this message translates to:
  /// **'Sizes'**
  String get sizesColumn;

  /// No description provided for @customSizesHint.
  ///
  /// In en, this message translates to:
  /// **'Custom sizes'**
  String get customSizesHint;

  /// No description provided for @shareButton.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get shareButton;

  /// No description provided for @invoiceSavedToGallery.
  ///
  /// In en, this message translates to:
  /// **'Invoice saved to gallery'**
  String get invoiceSavedToGallery;

  /// No description provided for @invoiceSavedToDocuments.
  ///
  /// In en, this message translates to:
  /// **'Invoice saved to Documents'**
  String get invoiceSavedToDocuments;

  /// No description provided for @invoiceShared.
  ///
  /// In en, this message translates to:
  /// **'Invoice shared'**
  String get invoiceShared;

  /// Settings section header for backup and restore
  ///
  /// In en, this message translates to:
  /// **'Backup'**
  String get backupSectionTitle;

  /// Button that saves a database backup to the backup folder
  ///
  /// In en, this message translates to:
  /// **'Back up now'**
  String get backupNow;

  /// Button that picks a backup file and restores it
  ///
  /// In en, this message translates to:
  /// **'Restore from backup'**
  String get backupRestore;

  /// Status shown while a backup is being created
  ///
  /// In en, this message translates to:
  /// **'Backing up…'**
  String get backupInProgress;

  /// Status shown while a backup is being restored
  ///
  /// In en, this message translates to:
  /// **'Restoring…'**
  String get backupRestoreInProgress;

  /// No description provided for @backupLastAuto.
  ///
  /// In en, this message translates to:
  /// **'Last auto-backup: {time}'**
  String backupLastAuto(String time);

  /// Toast after the backup share sheet completes
  ///
  /// In en, this message translates to:
  /// **'Backup ready — save it from the share sheet.'**
  String get backupShared;

  /// No description provided for @backupFailed.
  ///
  /// In en, this message translates to:
  /// **'Backup failed: {error}'**
  String backupFailed(String error);

  /// No description provided for @restoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Restore failed: {error}'**
  String restoreFailed(String error);

  /// Title of the restore confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Replace local data?'**
  String get restoreConfirmTitle;

  /// No description provided for @restoreConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'This will replace everything on this device with the backup file. {count} unsynced change(s) will be lost.'**
  String restoreConfirmMessage(int count);

  /// Toast after a backup is restored successfully
  ///
  /// In en, this message translates to:
  /// **'Backup restored.'**
  String get restoreSuccess;

  /// Label for the auto-backup cadence picker
  ///
  /// In en, this message translates to:
  /// **'Auto-backup'**
  String get backupInterval;

  /// Auto-backup cadence option: disabled
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get backupIntervalOff;

  /// Auto-backup cadence option
  ///
  /// In en, this message translates to:
  /// **'Daily'**
  String get backupIntervalDaily;

  /// Auto-backup cadence option
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get backupIntervalWeekly;

  /// Auto-backup cadence option
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get backupIntervalMonthly;

  /// Label for the default manual-backup folder
  ///
  /// In en, this message translates to:
  /// **'Backup folder'**
  String get backupLocation;

  /// Shown when no default backup folder is set
  ///
  /// In en, this message translates to:
  /// **'Not set — ask every time'**
  String get backupNoLocation;

  /// Button that opens the backup folder picker
  ///
  /// In en, this message translates to:
  /// **'Choose'**
  String get backupPickFolder;

  /// Button that clears the default backup folder
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get backupClearFolder;

  /// Toast after a manual backup is saved
  ///
  /// In en, this message translates to:
  /// **'Backup saved to {path}'**
  String backupSaved(String path);

  /// Settings tab: language and general options
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsTabGeneral;

  /// Settings tab: sign-in and invites
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsTabAccount;

  /// Settings tab: sync status
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get settingsTabSync;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
