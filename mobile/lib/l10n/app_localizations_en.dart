// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get productModel => 'Model';

  @override
  String get productDescription => 'Description';

  @override
  String get quantity => 'Quantity';

  @override
  String get price => 'Price';

  @override
  String get lineTotal => 'Line Total';

  @override
  String get total => 'Total';

  @override
  String get addItem => 'Add Item';

  @override
  String get createInvoiceBtn => 'Create invoice';

  @override
  String get sortLabel => 'SORT';

  @override
  String get sortAz => 'From A-Z';

  @override
  String get sortZa => 'From Z-A';

  @override
  String get sortNewest => 'From Newest';

  @override
  String get sortOldest => 'From Oldest';

  @override
  String get sortNone => 'None';

  @override
  String get noInvoicesFound => 'No invoices found';

  @override
  String get archiveEmptyHint => 'Saved invoices will appear here.';

  @override
  String get delete => 'Delete';

  @override
  String get deleteConfirmTitle => 'Delete?';

  @override
  String get deleteConfirmMessage => 'This cannot be undone.';

  @override
  String get invoiceUnsavedTitle => 'Invoice was not saved';

  @override
  String get invoiceUnsavedMessage =>
      'Your invoice has unsaved changes, do you want to continue?';

  @override
  String get unsavedProductsTitle => 'Unsaved Products';

  @override
  String get unsavedProductsMessage =>
      'You have unsaved products, do you want to continue?';

  @override
  String get unsavedPricingCategoryTitle => 'Unsaved Pricing Category';

  @override
  String get unsavedPricingCategoryMessage =>
      'You have unsaved pricing category, do you want to continue?';

  @override
  String get unsavedProductPricingTitle => 'Unsaved Product Pricing';

  @override
  String get unsavedProductPricingMessage =>
      'You have unsaved product pricing, do you want to continue?';

  @override
  String get navInvoices => 'Invoices';

  @override
  String get navProducts => 'Products';

  @override
  String get navPricing => 'Pricing';

  @override
  String get navOrders => 'Orders';

  @override
  String get navSettings => 'Settings';

  @override
  String get notFoundLabel => '404';

  @override
  String get dialogYes => 'Yes';

  @override
  String get dialogNo => 'No';

  @override
  String get inviteLinkAcceptedChoosePassword =>
      'Link accepted — choose a password to finish.';

  @override
  String get inviteLinkAcceptedSignIn =>
      'Link accepted — now sign in with your new password.';

  @override
  String get inviteLinkAcceptFailed => 'Could not accept the link — try again.';

  @override
  String get invitePasswordSetDone =>
      'Password set — sign in with your email and password.';

  @override
  String get acceptInvitationTitle => 'Accept invitation';

  @override
  String get choosePasswordLabel => 'Choose password';

  @override
  String get setPasswordButton => 'Set password';

  @override
  String get done => 'Done';

  @override
  String get save => 'Save';

  @override
  String get edit => 'Edit';

  @override
  String get saveAsImage => 'Save as image';

  @override
  String get saveAsPdf => 'Save as PDF';

  @override
  String get shareAsImage => 'Share as image';

  @override
  String get shareAsPdf => 'Share as PDF';

  @override
  String get invoiceTitle => 'INVOICE';

  @override
  String get ordersNeedSyncConfig =>
      'Orders need sync configuration — the app works offline.';

  @override
  String get ordersSignInPrompt => 'Sign in from Settings to view orders.';

  @override
  String get ordersCustomerGuidance =>
      'Customers place and follow orders in the web app — open your welcome link to continue there.';

  @override
  String get customers => 'Customers';

  @override
  String get noConnectionOrders =>
      'No connection — connect to view live orders.';

  @override
  String couldNotLoadOrders(String error) {
    return 'Could not load orders: $error';
  }

  @override
  String get retry => 'Retry';

  @override
  String get refresh => 'Refresh';

  @override
  String get noOrdersYet => 'No orders yet.';

  @override
  String get newOrderChannelName => 'New orders';

  @override
  String get newOrderChannelDescription =>
      'Alerts when a customer places an order.';

  @override
  String get newOrderTitle => 'New order';

  @override
  String newOrderBody(String total, String currency) {
    return '$total $currency';
  }

  @override
  String orderSubtitle(String status, String date) {
    return '$status · $date';
  }

  @override
  String get filterAll => 'All';

  @override
  String get orderStatusPending => 'pending';

  @override
  String get orderStatusCompleted => 'completed';

  @override
  String unexpectedError(String error) {
    return '$error';
  }

  @override
  String get orderNoLines => 'No lines on this order.';

  @override
  String get orderInvoiced => 'Invoiced';

  @override
  String get createInvoice => 'Create invoice';

  @override
  String get goToInvoice => 'Go to invoice';

  @override
  String orderSkippedLines(int count) {
    return '$count lines skipped (product missing)';
  }

  @override
  String get close => 'Close';

  @override
  String get noConnectionCustomers =>
      'No connection — connect to view customers.';

  @override
  String couldNotLoadCustomers(String error) {
    return 'Could not load customers: $error';
  }

  @override
  String get noCustomersYet => 'No customers yet — invite one from Settings.';

  @override
  String get productIdColumn => 'ID';

  @override
  String productAlreadyExists(String model) {
    return 'A product with model $model already exists';
  }

  @override
  String get productNameColumn => 'Name';

  @override
  String get productActionsColumn => 'Actions';

  @override
  String get addProduct => 'Add Product';

  @override
  String unsavedProductsCount(int count) {
    return 'You have $count unsaved products';
  }

  @override
  String get catalogReadOnly =>
      'Catalog is read-only for your role — ask an admin for changes.';

  @override
  String get newProduct => 'New Product';

  @override
  String get editProduct => 'Edit Product';

  @override
  String get searchLabel => 'Search';

  @override
  String get productModelRequired => 'Please enter a model';

  @override
  String get productNameRequired => 'Please enter a name';

  @override
  String get cancelButton => 'Cancel';

  @override
  String get settingsOfflineFirstNote =>
      'Your edits are saved on this device first and sync when you are online and signed in.';

  @override
  String get settingsStagingNote =>
      'Your edits are saved on this device. Sync activates after the staging checklist passes.';

  @override
  String get syncNotConfigured => 'Sync not configured';

  @override
  String get syncNotConfiguredHint =>
      'The app works fully offline. Add Supabase credentials to enable sign-in.';

  @override
  String get signedInFallback => 'Signed in';

  @override
  String get syncAccountNote => 'Your edits sync to this account.';

  @override
  String syncAccountRoleNote(String role) {
    return 'Your edits sync to this account. Role: $role.';
  }

  @override
  String get signOut => 'Sign out';

  @override
  String get signInToSync => 'Sign in to sync';

  @override
  String get signInInviteHint =>
      'Accounts are created by your admin — ask for a WhatsApp invite link.';

  @override
  String get emailLabel => 'Email';

  @override
  String get passwordLabel => 'Password';

  @override
  String get signInAction => 'Sign in';

  @override
  String get haveInviteLinkTitle =>
      'Have an invite link? Paste it to set your password.';

  @override
  String get inviteLinkFieldLabel => 'WhatsApp invite link';

  @override
  String get inviteLinkFieldHint => 'Paste the full link here';

  @override
  String get acceptInviteLink => 'Accept invite link';

  @override
  String loginPreview(String slug) {
    return 'Login preview: $slug@';
  }

  @override
  String get inviteUsersTitle => 'Invite users';

  @override
  String get inviteUsersHint =>
      'Send the generated link over WhatsApp. The user sets their own password — nothing secret stays in chat.';

  @override
  String get nameArabicLabel => 'Name (Arabic)';

  @override
  String get nameEnglishLabel => 'Name (English)';

  @override
  String get phoneWhatsappLabel => 'Phone (WhatsApp)';

  @override
  String get roleFieldLabel => 'Role';

  @override
  String get roleEmployee => 'Employee';

  @override
  String get roleCustomer => 'Customer';

  @override
  String get inviteActionLabel => 'Action';

  @override
  String get inviteModeNew => 'New invite';

  @override
  String get inviteModeResend => 'Resend link';

  @override
  String get inviteModeRecovery => 'Reset password';

  @override
  String loginEmailLabel(String email) {
    return 'Login: $email';
  }

  @override
  String inviteShareText(String email, String link) {
    return 'Your account: $email\\nOpen this link to set your password:\\n$link';
  }

  @override
  String get inviteCopiedHint => 'Copied — forward it over WhatsApp.';

  @override
  String get copyForWhatsapp => 'Copy for WhatsApp';

  @override
  String get createInviteLink => 'Create invite link';

  @override
  String get resendInviteLink => 'Resend invite link';

  @override
  String get sendPasswordResetLink => 'Send password-reset link';

  @override
  String get newInvoice => 'New invoice';

  @override
  String get saveButton => 'Save';

  @override
  String get previewButton => 'Preview';

  @override
  String grandTotal(num value) {
    return 'Grand total: $value';
  }

  @override
  String invoiceSaved(num value) {
    return 'Invoice saved · $value';
  }

  @override
  String get customerNameHint => 'Customer name';

  @override
  String get discount => 'Discount';

  @override
  String itemsCount(int count) {
    return 'Items ($count)';
  }

  @override
  String customPriceList(String currency) {
    return 'Custom ($currency)';
  }

  @override
  String priceCategoryOption(String name, String currency) {
    return '$name ($currency)';
  }

  @override
  String get removeButton => 'Remove';

  @override
  String get searchProductHint => 'Search product...';

  @override
  String productSuggestion(String model, String name) {
    return '$model: $name';
  }

  @override
  String get noProductsFound => 'No products found';

  @override
  String get goBack => 'Go back';

  @override
  String textSizeLabel(int size) {
    return 'Text Size is $size';
  }

  @override
  String get editButton => 'Edit';

  @override
  String get exportAsImage => 'Export As Image';

  @override
  String get exportAsPdf => 'Export As PDF';

  @override
  String get billTo => 'BILL TO';

  @override
  String get thankYouNote => 'Thank you for your business';

  @override
  String get unitPrice => 'Unit Price';

  @override
  String get subtotal => 'Subtotal';

  @override
  String get selectPriceList => 'Select price list';

  @override
  String get discardChangesTitle => 'Discard Changes?';

  @override
  String get discardChangesMessage =>
      'You have unsaved changes. Are you sure you want to discard them?';

  @override
  String get keepEditing => 'Keep Editing';

  @override
  String get discardButton => 'Discard';

  @override
  String priceCategoryColumnTitle(String title, String currency) {
    return '$title ($currency)';
  }

  @override
  String get saveAllButton => 'Save All';

  @override
  String get newPriceList => 'New List';

  @override
  String get pricingReadOnlyMessage =>
      'Pricing is read-only for your role — ask an admin for changes.';

  @override
  String get editOrDeleteList => 'Edit or Delete this list';

  @override
  String get deleteButton => 'Delete';

  @override
  String get priceCategoryNameLabel => 'Name';

  @override
  String get priceCategoryNameHint => 'Enter name';

  @override
  String get nameRequiredError => 'Name is required';

  @override
  String get nameAlreadyExistsError => 'Name already exists';

  @override
  String get currencyLabel => 'Currency';

  @override
  String get currencyHint => 'Enter currency';

  @override
  String get syncCompleted => 'Sync completed.';

  @override
  String syncFailed(String error) {
    return 'Sync failed: $error';
  }

  @override
  String get syncUnavailable => 'Sync unavailable';

  @override
  String get syncNow => 'Sync now';

  @override
  String lastSyncLabel(String time) {
    return 'Last sync: $time';
  }

  @override
  String queuedChanges(int count, String breakdown) {
    return 'Queued changes: $count$breakdown';
  }

  @override
  String lastDownloadLabel(String counters) {
    return 'Last download: $counters';
  }

  @override
  String skippedRowsLabel(String counters) {
    return 'Held for retry: $counters';
  }

  @override
  String syncNeedsAttentionDetail(String error) {
    return 'Sync needs attention:\\n$error';
  }

  @override
  String parkedEvictedWarning(int count) {
    return 'Warning: $count parked op(s) evicted this session (cap reached).';
  }

  @override
  String get syncingStatus => 'Syncing…';

  @override
  String get syncErrorStatus => 'Sync error';

  @override
  String get unknownError => 'Unknown error.';

  @override
  String get syncedStatus => 'Synced';

  @override
  String syncedWithPending(int count) {
    return 'Synced • $count change(s) queued';
  }

  @override
  String get syncNeedsAttention => 'Sync needs attention';

  @override
  String waitingToSync(int count) {
    return 'Waiting to sync • $count change(s) queued';
  }

  @override
  String get upToDateStatus => 'Up to date';

  @override
  String get neverSynced => 'Never';

  @override
  String get sizesColumn => 'Sizes';

  @override
  String get customSizesHint => 'Custom sizes';

  @override
  String get shareButton => 'Share';

  @override
  String get invoiceSavedToGallery => 'Invoice saved to gallery';

  @override
  String get invoiceSavedToDocuments => 'Invoice saved to Documents';

  @override
  String get invoiceShared => 'Invoice shared';

  @override
  String get backupSectionTitle => 'Backup';

  @override
  String get backupNow => 'Back up now';

  @override
  String get backupRestore => 'Restore from backup';

  @override
  String get backupInProgress => 'Backing up…';

  @override
  String get backupRestoreInProgress => 'Restoring…';

  @override
  String backupLastAuto(String time) {
    return 'Last auto-backup: $time';
  }

  @override
  String get backupShared => 'Backup ready — save it from the share sheet.';

  @override
  String backupFailed(String error) {
    return 'Backup failed: $error';
  }

  @override
  String restoreFailed(String error) {
    return 'Restore failed: $error';
  }

  @override
  String get restoreConfirmTitle => 'Replace local data?';

  @override
  String restoreConfirmMessage(int count) {
    return 'This will replace everything on this device with the backup file. $count unsynced change(s) will be lost.';
  }

  @override
  String get restoreSuccess => 'Backup restored.';

  @override
  String get backupInterval => 'Auto-backup';

  @override
  String get backupIntervalOff => 'Off';

  @override
  String get backupIntervalDaily => 'Daily';

  @override
  String get backupIntervalWeekly => 'Weekly';

  @override
  String get backupIntervalMonthly => 'Monthly';

  @override
  String get backupLocation => 'Backup folder';

  @override
  String get backupNoLocation => 'Not set — ask every time';

  @override
  String get backupPickFolder => 'Choose';

  @override
  String get backupClearFolder => 'Clear';

  @override
  String backupSaved(String path) {
    return 'Backup saved to $path';
  }

  @override
  String get settingsTabGeneral => 'General';

  @override
  String get settingsTabAccount => 'Account';

  @override
  String get settingsTabSync => 'Sync';
}
