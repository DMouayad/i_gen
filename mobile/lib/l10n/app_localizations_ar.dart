// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get productModel => 'الموديل';

  @override
  String get productDescription => 'الوصف';

  @override
  String get quantity => 'الكمية';

  @override
  String get price => 'السعر';

  @override
  String get lineTotal => 'إجمالي السطر';

  @override
  String get total => 'الإجمالي';

  @override
  String get addItem => 'إضافة صنف';

  @override
  String get sortLabel => 'فرز';

  @override
  String get sortAz => 'من أ إلى ي';

  @override
  String get sortZa => 'من ي إلى أ';

  @override
  String get sortNewest => 'من الأحدث';

  @override
  String get sortOldest => 'من الأقدم';

  @override
  String get sortNone => 'بدون';

  @override
  String get noInvoicesFound => 'لم يتم العثور على فواتير';

  @override
  String get archiveEmptyHint => 'ستظهر الفواتير المحفوظة هنا.';

  @override
  String get delete => 'حذف';

  @override
  String get deleteConfirmTitle => 'حذف؟';

  @override
  String get deleteConfirmMessage => 'لا يمكن التراجع عن هذا الإجراء.';

  @override
  String get invoiceUnsavedTitle => 'لم يتم حفظ الفاتورة';

  @override
  String get invoiceUnsavedMessage =>
      'تحتوي الفاتورة على تغييرات غير محفوظة، هل تريد المتابعة؟';

  @override
  String get unsavedProductsTitle => 'منتجات غير محفوظة';

  @override
  String get unsavedProductsMessage =>
      'لديك منتجات غير محفوظة، هل تريد المتابعة؟';

  @override
  String get unsavedPricingCategoryTitle => 'فئة تسعير غير محفوظة';

  @override
  String get unsavedPricingCategoryMessage =>
      'لديك فئة تسعير غير محفوظة، هل تريد المتابعة؟';

  @override
  String get unsavedProductPricingTitle => 'تسعير منتج غير محفوظ';

  @override
  String get unsavedProductPricingMessage =>
      'لديك تسعير منتج غير محفوظ، هل تريد المتابعة؟';

  @override
  String get navInvoices => 'الفواتير';

  @override
  String get navProducts => 'المنتجات';

  @override
  String get navPricing => 'الأسعار';

  @override
  String get navOrders => 'الطلبات';

  @override
  String get navSettings => 'الإعدادات';

  @override
  String get notFoundLabel => '404';

  @override
  String get dialogYes => 'نعم';

  @override
  String get dialogNo => 'لا';

  @override
  String get inviteLinkAcceptedChoosePassword =>
      'تم قبول الرابط — اختر كلمة مرور للمتابعة.';

  @override
  String get inviteLinkAcceptedSignIn =>
      'تم قبول الرابط — سجّل الدخول بكلمة المرور الجديدة.';

  @override
  String get inviteLinkAcceptFailed => 'تعذّر قبول الرابط — حاول مرة أخرى.';

  @override
  String get invitePasswordSetDone =>
      'تم تعيين كلمة المرور — سجّل الدخول بريدك الإلكتروني وكلمة المرور.';

  @override
  String get acceptInvitationTitle => 'قبول الدعوة';

  @override
  String get choosePasswordLabel => 'اختر كلمة المرور';

  @override
  String get setPasswordButton => 'تعيين كلمة المرور';

  @override
  String get done => 'تم';

  @override
  String get save => 'حفظ';

  @override
  String get edit => 'تعديل';

  @override
  String get saveAsImage => 'حفظ كصورة';

  @override
  String get saveAsPdf => 'حفظ كـ PDF';

  @override
  String get shareAsImage => 'مشاركة كصورة';

  @override
  String get shareAsPdf => 'مشاركة كـ PDF';

  @override
  String get invoiceTitle => 'فاتورة';

  @override
  String get ordersNeedSyncConfig =>
      'الطلبات بحاجة لإعداد المزامنة — يعمل التطبيق دون اتصال.';

  @override
  String get ordersSignInPrompt => 'سجّل الدخول من الإعدادات لعرض الطلبات.';

  @override
  String get ordersDistributorGuidance =>
      'يقوم الموزّعون بتقديم ومتابعة الطلبات في تطبيق الويب — افتح رابط الترحيب للمتابعة هناك.';

  @override
  String get distributors => 'الموزّعون';

  @override
  String get noConnectionOrders => 'لا يوجد اتصال — اتصل لعرض الطلبات الحية.';

  @override
  String couldNotLoadOrders(String error) {
    return 'تعذّر تحميل الطلبات: $error';
  }

  @override
  String get retry => 'إعادة المحاولة';

  @override
  String get refresh => 'تحديث';

  @override
  String get noOrdersYet => 'لا توجد طلبات بعد.';

  @override
  String orderAmountTitle(String total, String currency) {
    return '$total $currency';
  }

  @override
  String get newOrderChannelName => 'طلبات جديدة';

  @override
  String get newOrderChannelDescription => 'تنبيهات عند تقديم موزع لطلب.';

  @override
  String get newOrderTitle => 'طلب جديد';

  @override
  String newOrderBody(String total, String currency) {
    return '$total $currency';
  }

  @override
  String orderSubtitle(String status, String date) {
    return '$status · $date';
  }

  @override
  String get filterAll => 'الكل';

  @override
  String get orderStatusPending => 'قيد الانتظار';

  @override
  String get orderStatusConfirmed => 'مؤكد';

  @override
  String get orderStatusDelivered => 'تم التسليم';

  @override
  String get orderStatusCancelled => 'ملغي';

  @override
  String get noConnectionShort => 'لا يوجد اتصال.';

  @override
  String unexpectedError(String error) {
    return '$error';
  }

  @override
  String orderDetailTitle(String status) {
    return 'طلب · $status';
  }

  @override
  String get orderNoLines => 'لا توجد أصناف في هذا الطلب.';

  @override
  String orderItemAmount(String amount) {
    return '×$amount';
  }

  @override
  String get close => 'إغلاق';

  @override
  String get noConnectionDistributors => 'لا يوجد اتصال — اتصل لعرض الموزّعين.';

  @override
  String couldNotLoadDistributors(String error) {
    return 'تعذّر تحميل الموزّعين: $error';
  }

  @override
  String get noDistributorsYet =>
      'لا يوجد موزّعون بعد — ادعُ أحدهم من الإعدادات.';

  @override
  String get productIdColumn => 'المعرّف';

  @override
  String productAlreadyExists(String model) {
    return 'يوجد منتج بالنموذج $model مسبقًا';
  }

  @override
  String get productNameColumn => 'الاسم';

  @override
  String get productActionsColumn => 'الإجراءات';

  @override
  String get addProduct => 'إضافة منتج';

  @override
  String unsavedProductsCount(int count) {
    return 'لديك $count من المنتجات غير المحفوظة';
  }

  @override
  String get catalogReadOnly =>
      'الكتالوج للقراءة فقط لدورك — اطلب التعديلات من المسؤول.';

  @override
  String get newProduct => 'منتج جديد';

  @override
  String get editProduct => 'تعديل المنتج';

  @override
  String get searchLabel => 'بحث';

  @override
  String get productModelRequired => 'يرجى إدخال النموذج';

  @override
  String get productNameRequired => 'يرجى إدخال الاسم';

  @override
  String get cancelButton => 'إلغاء';

  @override
  String get settingsOfflineFirstNote =>
      'تُحفظ تعديلاتك على هذا الجهاز أولًا وتُزامَن عندما تكون متصلًا ومسجّلًا الدخول.';

  @override
  String get settingsStagingNote =>
      'تُحفظ تعديلاتك على هذا الجهاز. تُفعَّل المزامنة بعد اجتياز قائمة التحقق التجريبية.';

  @override
  String get syncNotConfigured => 'المزامنة غير مُعدّة';

  @override
  String get syncNotConfiguredHint =>
      'عمل التطبيق دون اتصال بالكامل. أضف بيانات Supabase لتفعيل تسجيل الدخول.';

  @override
  String get signedInFallback => 'مسجّل الدخول';

  @override
  String get syncAccountNote => 'تُزامَن تعديلاتك مع هذا الحساب.';

  @override
  String syncAccountRoleNote(String role) {
    return 'تُزامَن تعديلاتك مع هذا الحساب. الدور: $role.';
  }

  @override
  String get signOut => 'تسجيل الخروج';

  @override
  String get signInToSync => 'سجّل الدخول للمزامنة';

  @override
  String get signInInviteHint =>
      'تُنشأ الحسابات بواسطة المسؤول — اطلب رابط دعوة عبر واتساب.';

  @override
  String get emailLabel => 'البريد الإلكتروني';

  @override
  String get passwordLabel => 'كلمة المرور';

  @override
  String get signInAction => 'تسجيل الدخول';

  @override
  String get haveInviteLinkTitle =>
      'هل لديك رابط دعوة؟ الصقه لتعيين كلمة المرور.';

  @override
  String get inviteLinkFieldLabel => 'رابط دعوة واتساب';

  @override
  String get inviteLinkFieldHint => 'الصق الرابط الكامل هنا';

  @override
  String get acceptInviteLink => 'قبول رابط الدعوة';

  @override
  String loginPreview(String slug) {
    return 'معاينة الدخول: $slug@';
  }

  @override
  String get inviteUsersTitle => 'دعوة المستخدمين';

  @override
  String get inviteUsersHint =>
      'أرسل الرابط المُنشأ عبر واتساب. يحدّد المستخدم كلمة المرور بنفسه — لا يبقى أي سرّ في المحادثة.';

  @override
  String get nameArabicLabel => 'الاسم (بالعربية)';

  @override
  String get nameEnglishLabel => 'الاسم (بالإنجليزية)';

  @override
  String get phoneWhatsappLabel => 'الهاتف (واتساب)';

  @override
  String get roleFieldLabel => 'الدور';

  @override
  String get roleEmployee => 'موظف';

  @override
  String get roleDistributor => 'موزّع';

  @override
  String get inviteActionLabel => 'الإجراء';

  @override
  String get inviteModeNew => 'دعوة جديدة';

  @override
  String get inviteModeResend => 'إعادة إرسال الرابط';

  @override
  String get inviteModeRecovery => 'إعادة تعيين كلمة المرور';

  @override
  String loginEmailLabel(String email) {
    return 'الدخول: $email';
  }

  @override
  String inviteShareText(String email, String link) {
    return 'حسابك: $email\\nافتح هذا الرابط لتعيين كلمة المرور:\\n$link';
  }

  @override
  String get inviteCopiedHint => 'تم النسخ — أرسله عبر واتساب.';

  @override
  String get copyForWhatsapp => 'نسخ لواتساب';

  @override
  String get createInviteLink => 'إنشاء رابط دعوة';

  @override
  String get resendInviteLink => 'إعادة إرسال رابط الدعوة';

  @override
  String get sendPasswordResetLink => 'إرسال رابط إعادة تعيين كلمة المرور';

  @override
  String get newInvoice => 'فاتورة جديدة';

  @override
  String get saveButton => 'حفظ';

  @override
  String get previewButton => 'معاينة';

  @override
  String grandTotal(num value) {
    return 'الإجمالي الكلي: $value';
  }

  @override
  String invoiceSaved(num value) {
    return 'تم حفظ الفاتورة · $value';
  }

  @override
  String get customerNameHint => 'اسم العميل';

  @override
  String get discount => 'الخصم';

  @override
  String itemsCount(int count) {
    return 'الأصناف ($count)';
  }

  @override
  String customPriceList(String currency) {
    return 'مخصص ($currency)';
  }

  @override
  String priceCategoryOption(String name, String currency) {
    return '$name ($currency)';
  }

  @override
  String get removeButton => 'إزالة';

  @override
  String get searchProductHint => 'ابحث عن منتج...';

  @override
  String productSuggestion(String model, String name) {
    return '$model: $name';
  }

  @override
  String get noProductsFound => 'لا توجد منتجات مطابقة';

  @override
  String get goBack => 'رجوع';

  @override
  String textSizeLabel(int size) {
    return 'حجم النص $size';
  }

  @override
  String get editButton => 'تعديل';

  @override
  String get exportAsImage => 'تصدير كصورة';

  @override
  String get exportAsPdf => 'تصدير كـ PDF';

  @override
  String get billTo => 'فاتورة إلى';

  @override
  String get thankYouNote => 'شكراً لتعاملكم معنا';

  @override
  String get unitPrice => 'سعر الوحدة';

  @override
  String get subtotal => 'المجموع الفرعي';

  @override
  String get selectPriceList => 'اختر قائمة الأسعار';

  @override
  String get discardChangesTitle => 'تجاهل التغييرات؟';

  @override
  String get discardChangesMessage =>
      'لديك تغييرات غير محفوظة. هل أنت متأكد من تجاهلها؟';

  @override
  String get keepEditing => 'متابعة التحرير';

  @override
  String get discardButton => 'تجاهل';

  @override
  String priceCategoryColumnTitle(String title, String currency) {
    return '$title ($currency)';
  }

  @override
  String get saveAllButton => 'حفظ الكل';

  @override
  String get newPriceList => 'قائمة جديدة';

  @override
  String get pricingReadOnlyMessage =>
      'الأسعار للعرض فقط حسب دورك — اطلب من مدير إجراء التعديلات.';

  @override
  String get editOrDeleteList => 'تعديل هذه القائمة أو حذفها';

  @override
  String get deleteButton => 'حذف';

  @override
  String get priceCategoryNameLabel => 'الاسم';

  @override
  String get priceCategoryNameHint => 'أدخل الاسم';

  @override
  String get nameRequiredError => 'الاسم مطلوب';

  @override
  String get nameAlreadyExistsError => 'الاسم موجود مسبقاً';

  @override
  String get currencyLabel => 'العملة';

  @override
  String get currencyHint => 'أدخل العملة';

  @override
  String get syncCompleted => 'تمت المزامنة.';

  @override
  String syncFailed(String error) {
    return 'فشلت المزامنة: $error';
  }

  @override
  String get syncUnavailable => 'المزامنة غير متاحة';

  @override
  String get syncNow => 'مزامنة الآن';

  @override
  String lastSyncLabel(String time) {
    return 'آخر مزامنة: $time';
  }

  @override
  String queuedChanges(int count, String breakdown) {
    return 'تغييرات معلقة: $count$breakdown';
  }

  @override
  String lastDownloadLabel(String counters) {
    return 'آخر تنزيل: $counters';
  }

  @override
  String skippedRowsLabel(String counters) {
    return 'مؤجل للمحاولة: $counters';
  }

  @override
  String syncNeedsAttentionDetail(String error) {
    return 'المزامنة تحتاج انتباه:\\n$error';
  }

  @override
  String parkedEvictedWarning(int count) {
    return 'تحذير: تم إسقاط $count عملية متوقفة هذه الجلسة (تم بلوغ الحد).';
  }

  @override
  String get syncingStatus => 'جارٍ المزامنة…';

  @override
  String get syncErrorStatus => 'خطأ في المزامنة';

  @override
  String get unknownError => 'خطأ غير معروف.';

  @override
  String get syncedStatus => 'تمت المزامنة';

  @override
  String syncedWithPending(int count) {
    return 'تمت المزامنة • $count تغيير معلق';
  }

  @override
  String get syncNeedsAttention => 'المزامنة تحتاج انتباه';

  @override
  String waitingToSync(int count) {
    return 'بانتظار المزامنة • $count تغيير معلق';
  }

  @override
  String get upToDateStatus => 'محدّث';

  @override
  String get neverSynced => 'أبداً';

  @override
  String get sizesColumn => 'المقاسات';

  @override
  String get customSizesHint => 'مقاسات مخصصة';

  @override
  String get shareButton => 'مشاركة';

  @override
  String get invoiceSavedToGallery => 'تم حفظ الفاتورة في المعرض';

  @override
  String get invoiceSavedToDocuments => 'تم حفظ الفاتورة في المستندات';

  @override
  String get invoiceShared => 'تمت مشاركة الفاتورة';

  @override
  String get backupSectionTitle => 'النسخ الاحتياطي';

  @override
  String get backupNow => 'نسخ احتياطي الآن';

  @override
  String get backupRestore => 'استعادة من نسخة';

  @override
  String get backupInProgress => 'جارٍ النسخ الاحتياطي…';

  @override
  String get backupRestoreInProgress => 'جارٍ الاستعادة…';

  @override
  String backupLastAuto(String time) {
    return 'آخر نسخة تلقائية: $time';
  }

  @override
  String get backupShared => 'النسخة جاهزة — احفظها من نافذة المشاركة.';

  @override
  String backupFailed(String error) {
    return 'فشل النسخ الاحتياطي: $error';
  }

  @override
  String restoreFailed(String error) {
    return 'فشلت الاستعادة: $error';
  }

  @override
  String get restoreConfirmTitle => 'استبدال البيانات المحلية؟';

  @override
  String restoreConfirmMessage(int count) {
    return 'سيؤدي هذا إلى استبدال كل البيانات على هذا الجهاز بملف النسخة الاحتياطية. سيتم فقدان $count من التغييرات غير المُزامَنة.';
  }

  @override
  String get restoreSuccess => 'تمت استعادة النسخة الاحتياطية.';

  @override
  String get backupInterval => 'نسخ احتياطي تلقائي';

  @override
  String get backupIntervalOff => 'متوقف';

  @override
  String get backupIntervalDaily => 'يومي';

  @override
  String get backupIntervalWeekly => 'أسبوعي';

  @override
  String get backupIntervalMonthly => 'شهري';

  @override
  String get backupLocation => 'مجلد النسخ الاحتياطي';

  @override
  String get backupNoLocation => 'غير محدد — يُسأل في كل مرة';

  @override
  String get backupPickFolder => 'اختيار';

  @override
  String get backupClearFolder => 'إزالة';

  @override
  String backupSaved(String path) {
    return 'تم حفظ النسخة الاحتياطية في $path';
  }

  @override
  String get settingsTabGeneral => 'عام';

  @override
  String get settingsTabAccount => 'الحساب';

  @override
  String get settingsTabSync => 'المزامنة';
}
