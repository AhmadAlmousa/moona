import 'package:flutter/widgets.dart';

/// UI strings for Moona, ported from the mockup `i18n.js`.
///
/// A few keys at the end are new (incoming share request, trash attribution):
/// the prototype skipped the accept/decline flow and the "who scratched it off"
/// label that `project.md` requires.
@immutable
class AppStrings {
  const AppStrings._(this.lang);

  final String lang;
  bool get isArabic => lang == 'ar';
  TextDirection get direction =>
      isArabic ? TextDirection.rtl : TextDirection.ltr;

  factory AppStrings.of(String lang) => lang == 'ar' ? _ar : _en;

  static const AppStrings _ar = AppStrings._('ar');
  static const AppStrings _en = AppStrings._('en');

  String get appName => isArabic ? 'مونة' : 'Moona';
  String get tagline =>
      isArabic ? 'قائمة التسوّق المشتركة' : 'Shared shopping list';

  // login
  String get loginTitle => isArabic ? 'أهلاً بك في مونة' : 'Welcome to Moona';
  String get loginSub => isArabic
      ? 'سجّل دخولك أو أنشئ حساباً جديداً للبدء'
      : 'Sign in or create a new account to get started';
  String get password => isArabic ? 'كلمة المرور' : 'Password';
  String get signIn => isArabic ? 'تسجيل الدخول' : 'Sign in';
  String get signingIn => isArabic ? 'جارٍ تسجيل الدخول…' : 'Signing in…';
  String get newAccountNote => isArabic
      ? 'أول مرة؟ سيتم إنشاء حسابك تلقائياً.'
      : 'First time? Your account is created automatically.';
  String get wrongPass =>
      isArabic ? 'كلمة المرور غير صحيحة' : 'Incorrect password';
  String get phone => isArabic ? 'رقم الجوال' : 'Mobile number';
  String get phoneHint => isArabic ? 'مثال: 0501112233' : 'e.g. 0501112233';
  String get enterPhone =>
      isArabic ? 'أدخل رقم جوال صحيح' : 'Enter a valid mobile number';

  // important + note + collapsible
  String get important => isArabic ? 'مهم' : 'Important';
  String get importantDesc => isArabic
      ? 'يُثبَّت بأعلى القائمة بلون مميّز'
      : 'Pinned to the top with a highlight';
  String get note => isArabic ? 'ملاحظة' : 'Note';
  String get noteHint =>
      isArabic ? 'أضف ملاحظة (اختياري)' : 'Add a note (optional)';
  String get moreDetails => isArabic ? 'تفاصيل إضافية' : 'More details';

  // trash (mockup called this "Completed")
  String get completed => isArabic ? 'المحذوفة' : 'Trash';
  String get completedTitle => isArabic ? 'الأصناف المحذوفة' : 'Trashed items';
  String get noCompleted =>
      isArabic ? 'لا توجد أصناف محذوفة بعد' : 'No trashed items yet';
  String get noCompletedSub => isArabic
      ? 'الأصناف التي تشطبها ستظهر هنا'
      : 'Items you scratch off will show up here';
  String get restore => isArabic ? 'استرجاع' : 'Restore';
  String get clearAll => isArabic ? 'مسح الكل' : 'Clear all';
  String get completedAgo => isArabic ? 'حُذف' : 'Removed';

  // contacts
  String get shareViaContacts =>
      isArabic ? 'مشاركة مع جهة اتصال' : 'Share with a contact';
  String get contactsPermTitle =>
      isArabic ? 'السماح بالوصول لجهات الاتصال' : 'Allow access to contacts';
  String get contactsPermBody => isArabic
      ? 'يحتاج مونة للوصول إلى جهات اتصالك حتى تتمكّن من اختيار من تشارك معه القائمة.'
      : 'Moona needs access to your contacts so you can choose who to share '
            'the list with.';
  String get allow => isArabic ? 'السماح' : 'Allow';
  String get dontAllow => isArabic ? 'ليس الآن' : 'Not now';
  String get selectContact => isArabic ? 'اختر جهة اتصال' : 'Select a contact';
  String get searchContacts =>
      isArabic ? 'بحث في جهات الاتصال' : 'Search contacts';
  String get onMoona => isArabic ? 'على مونة' : 'On Moona';
  String get notOnMoona => isArabic ? 'ليسوا على مونة' : 'Not on Moona';
  String get invite => isArabic ? 'دعوة' : 'Invite';
  String get invited => isArabic ? 'تم إرسال الدعوة' : 'Invite sent';
  String get enterPhoneManually =>
      isArabic ? 'أو أدخل رقماً يدوياً' : 'Or enter a number manually';

  String get relNow => isArabic ? 'الآن' : 'just now';
  String get relMin => isArabic ? 'د' : 'm';
  String get relHour => isArabic ? 'س' : 'h';
  String get relDay => isArabic ? 'ي' : 'd';
  String get relAgo => isArabic ? 'منذ' : 'ago';

  // main
  String get myList => isArabic ? 'قائمتي' : 'My list';
  String get sharedListOf => isArabic ? 'قائمة' : 'list';
  String get allItems => isArabic ? 'كل الأصناف' : 'All items';
  String get addItem => isArabic ? 'إضافة صنف' : 'Add item';
  String get emptyTitle => isArabic ? 'القائمة فارغة' : 'Your list is empty';
  String get emptySub => isArabic
      ? 'اضغط زر الإضافة لبدء قائمة تسوّقك'
      : 'Tap the add button to start your shopping list';
  String get emptyCatTitle => isArabic ? 'لا أصناف هنا' : 'Nothing here';
  String get emptyCatSub =>
      isArabic ? 'لا توجد أصناف في هذا التصنيف' : 'No items in this category';
  String get undo => isArabic ? 'تراجع' : 'Undo';
  String get removed => isArabic ? 'تم الحذف' : 'Removed';
  String get itemAdded => isArabic ? 'تمت الإضافة' : 'Item added';
  String get itemUpdated => isArabic ? 'تم التحديث' : 'Item updated';
  String get duplicate => isArabic
      ? 'هذا الصنف موجود في القائمة'
      : 'That item is already on the list';
  String get longPressHint =>
      isArabic ? 'اضغط مطولاً للتعديل' : 'Long-press to edit';

  // sorting + grouping
  String get sortBy => isArabic ? 'ترتيب حسب' : 'Sort by';
  String get sortName => isArabic ? 'الاسم' : 'Name';
  String get grouped => isArabic ? 'تجميع' : 'Grouped';
  String get groupedDesc => isArabic
      ? 'تقسيم القائمة بعنوان لكل مجموعة'
      : 'Split the list with a header per group';
  String get ungrouped => isArabic ? 'أخرى' : 'Other';

  // item / form
  String get addTitle => isArabic ? 'إضافة صنف' : 'Add item';
  String get editTitle => isArabic ? 'تعديل الصنف' : 'Edit item';
  String get productName => isArabic ? 'اسم المنتج' : 'Product name';
  String get productHint =>
      isArabic ? 'ابدأ الكتابة للبحث…' : 'Start typing to search…';
  String get count => isArabic ? 'الكمية' : 'Count';
  String get unit => isArabic ? 'الوحدة' : 'Unit';
  String get none => isArabic ? 'بدون' : 'None';
  String get brand => isArabic ? 'العلامة التجارية' : 'Brand';
  String get brandHint => isArabic ? 'اختياري' : 'Optional';
  String get seller => isArabic ? 'المتجر' : 'Store';
  String get sellerHint => isArabic ? 'اختياري' : 'Optional';
  String get category => isArabic ? 'التصنيف' : 'Category';
  String get image => isArabic ? 'الصورة' : 'Image';
  String get addPhoto => isArabic ? 'إضافة صورة' : 'Add photo';
  String get takePhoto => isArabic ? 'التقاط صورة' : 'Take photo';
  String get removePhoto => isArabic ? 'إزالة الصورة' : 'Remove photo';
  String get save => isArabic ? 'حفظ' : 'Save';
  String get cancel => isArabic ? 'إلغاء' : 'Cancel';
  String get deleteItem => isArabic ? 'حذف الصنف' : 'Delete item';
  String get nameRequired =>
      isArabic ? 'اسم المنتج مطلوب' : 'Product name is required';

  // settings / sharing
  String get settings => isArabic ? 'الإعدادات' : 'Settings';
  String get account => isArabic ? 'الحساب' : 'Account';
  String get language => isArabic ? 'اللغة' : 'Language';
  String get theme => isArabic ? 'المظهر' : 'Theme';
  String get dark => isArabic ? 'داكن' : 'Dark';
  String get light => isArabic ? 'فاتح' : 'Light';
  String get arabic => isArabic ? 'العربية' : 'Arabic';
  String get english => isArabic ? 'الإنجليزية' : 'English';
  String get sharing => isArabic ? 'المشاركة' : 'Sharing';
  String get shareDesc => isArabic
      ? 'شارك قائمتك مع مستخدم آخر للتسوّق معاً'
      : 'Share your list with another user to shop together';
  String get sharingWith =>
      isArabic ? 'تتم مشاركة قائمتك مع' : 'Your list is shared with';
  String get receivingFrom =>
      isArabic ? 'تشاهد قائمة' : "You're viewing the list of";
  String get unlink => isArabic ? 'إلغاء المشاركة' : 'Unlink';
  String get shareSelf =>
      isArabic ? 'لا يمكنك المشاركة مع نفسك' : "You can't share with yourself";
  String get userNotFound => isArabic ? 'المستخدم غير موجود' : 'User not found';
  String get shared => isArabic ? 'تمت المشاركة' : 'List shared';
  String get shareRequested =>
      isArabic ? 'تم إرسال طلب المشاركة' : 'Share request sent';
  String get unlinked => isArabic ? 'تم إلغاء المشاركة' : 'Unlinked';
  String get logout => isArabic ? 'تسجيل الخروج' : 'Log out';
  String get bothEdit => isArabic
      ? 'كلاكما يمكنه الإضافة والتعديل في نفس القائمة'
      : 'You both can add and edit the same list';
  String get shareList => isArabic ? 'مشاركة القائمة' : 'Share list';

  // display-name prompt before sharing (new)
  String get nameYourselfTitle => isArabic ? 'أضف اسمك' : 'Add your name';
  String get nameYourselfBody => isArabic
      ? 'أدخل اسماً يظهر لمن تشاركهم القائمة بدلاً من رقم جوالك.'
      : 'Enter a name so the people you share with see it instead of your '
            'phone number.';
  String get yourName => isArabic ? 'الاسم' : 'Name';
  String get yourNameHint => isArabic ? 'مثال: نور' : 'e.g. Noor';
  String get continueLabel => isArabic ? 'متابعة' : 'Continue';

  // incoming share request (new)
  String get shareRequestTitle =>
      isArabic ? 'طلب مشاركة قائمة' : 'List share request';
  String shareRequestBody(String who) => isArabic
      ? 'يريد $who مشاركة قائمته معك. عند الموافقة سترى قائمته وتستطيع تعديلها.'
      : '$who wants to share their list with you. If you accept you will see '
            'and can edit their list.';
  String get accept => isArabic ? 'موافقة' : 'Accept';
  String get decline => isArabic ? 'رفض' : 'Decline';
  String get shareAccepted => isArabic ? 'تمت الموافقة' : 'Share accepted';
  String get shareDeclined => isArabic ? 'تم الرفض' : 'Share declined';
  String get alreadyReceiving => isArabic
      ? 'أنت تستقبل قائمة مشتركة بالفعل'
      : "You're already receiving a shared list";

  // trash attribution (new)
  String scratchedBy(String who) =>
      isArabic ? 'شطبها $who' : 'Scratched by $who';

  // generic errors
  String get genericError =>
      isArabic ? 'حدث خطأ، حاول مرة أخرى' : 'Something went wrong, try again';
  String get networkError => isArabic
      ? 'تعذّر الاتصال بالخادم. تحقّق من اتصالك بالإنترنت'
      : 'Could not reach the server. Check your internet connection';

  /// Relative time label, ported from `i18n.js` `relTime`.
  String relTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    final ms = diff.inMilliseconds < 0 ? 0 : diff.inMilliseconds;
    final minutes = ms ~/ 60000;
    final hours = ms ~/ 3600000;
    final days = ms ~/ 86400000;
    if (minutes < 1) return relNow;
    final int n;
    final String u;
    if (hours < 1) {
      n = minutes;
      u = relMin;
    } else if (days < 1) {
      n = hours;
      u = relHour;
    } else {
      n = days;
      u = relDay;
    }
    return isArabic ? '$relAgo $n $u' : '$n$u $relAgo';
  }
}
