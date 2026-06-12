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
  String get selectContact => isArabic ? 'اختر جهة اتصال' : 'Select a contact';
  String get searchContacts =>
      isArabic ? 'بحث في جهات الاتصال' : 'Search contacts';
  String get onMoona => isArabic ? 'على مونة' : 'On Moona';
  String get notOnMoona => isArabic ? 'ليسوا على مونة' : 'Not on Moona';
  String get invite => isArabic ? 'دعوة' : 'Invite';
  String get invited => isArabic ? 'تم إرسال الدعوة' : 'Invite sent';
  String get enterPhoneManually =>
      isArabic ? 'أو أدخل رقماً يدوياً' : 'Or enter a number manually';
  String get contactsDeniedHint => isArabic
      ? 'الوصول لجهات الاتصال مرفوض. فعّله من الإعدادات أو أدخل رقماً يدوياً.'
      : 'Contacts access is off. Turn it on in Settings, or enter a number '
            'manually.';
  String get openContactsSettings =>
      isArabic ? 'فتح الإعدادات' : 'Open settings';
  String get pickFromContacts =>
      isArabic ? 'اختر من جهات الاتصال' : 'Pick from contacts';
  String get noContactsFound => isArabic
      ? 'لم نجد أي جهات اتصال على هذا الجهاز. أدخل رقماً يدوياً.'
      : 'No contacts were found on this device. Enter a number manually.';
  String contactsNoPhones(int count) => isArabic
      ? 'وجدنا $count جهة اتصال لكن بلا أرقام هاتف يمكن قراءتها. أدخل رقماً يدوياً.'
      : 'Found $count contacts, but none had a readable phone number. Enter a '
            'number manually.';
  String get contactsLoadError => isArabic
      ? 'تعذّر قراءة جهات الاتصال. أدخل رقماً يدوياً.'
      : "Couldn't read your contacts. Enter a number manually.";

  String get relNow => isArabic ? 'الآن' : 'just now';
  String get relMin => isArabic ? 'د' : 'm';
  String get relHour => isArabic ? 'س' : 'h';
  String get relDay => isArabic ? 'ي' : 'd';
  String get relAgo => isArabic ? 'منذ' : 'ago';

  // main
  String get myList => isArabic ? 'قائمتي' : 'My list';
  String get sharedListOf => isArabic ? 'قائمة' : 'list';
  String get allItems => isArabic ? 'كل الأصناف' : 'All items';
  String get allStores => isArabic ? 'كل المتاجر' : 'All stores';
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

  // presence ("someone is shopping now")
  String someoneShoppingNow(String who) =>
      isArabic ? '$who يتسوّق الآن' : '$who is shopping now';
  String peopleShoppingNow(int n) =>
      isArabic ? '$n أشخاص يتسوّقون الآن' : '$n people shopping now';

  // store / shopping mode
  String get storeMode => isArabic ? 'وضع التسوّق' : 'Shopping mode';
  String storeModeOf(int done, int total) =>
      isArabic ? '$done من $total' : '$done of $total';
  String get storeModeTapHint =>
      isArabic ? 'اضغط على الصنف عند وضعه في السلة' : 'Tap an item as you grab it';
  String get storeModeDone => isArabic ? 'تم كل شيء!' : 'All done!';
  String get storeModeDoneSub =>
      isArabic ? 'كل الأصناف في السلة' : "Everything's in the cart";
  String get storeModePickTitle =>
      isArabic ? 'ماذا تتسوّق؟' : 'What are you shopping?';
  String get storeModePickSub => isArabic
      ? 'اختر متجراً أو قسماً، أو تسوّق كل شيء'
      : 'Pick a store or category, or shop everything';
  String get storeModeByStore => isArabic ? 'حسب المتجر' : 'By store';
  String get storeModeByCategory => isArabic ? 'حسب القسم' : 'By category';
  String get storeModeCollected => isArabic ? 'في السلة' : 'Collected';
  String get storeModeFinish => isArabic ? 'إنهاء التسوّق' : 'Finish shopping';
  String get syncContacts => isArabic ? 'تحديث جهات الاتصال' : 'Refresh contacts';
  String storeModeFinishCount(int n) =>
      isArabic ? 'إنهاء · $n في السلة' : 'Finish · $n collected';

  // bulk paste
  String get pasteList => isArabic ? 'لصق قائمة' : 'Paste a list';
  String get pasteListTitle => isArabic ? 'لصق قائمة' : 'Paste a list';
  String get pasteListHint =>
      isArabic ? 'صنف واحد في كل سطر.' : 'One item per line.';
  String get pasteListPlaceholder =>
      isArabic ? 'حليب\nخبز\nبيض' : 'Milk\nBread\nEggs';
  String get addAll => isArabic ? 'إضافة الكل' : 'Add all';
  String addAllN(int n) => isArabic ? 'إضافة الكل ($n)' : 'Add all ($n)';
  String itemsAdded(int n) =>
      isArabic ? 'تمت إضافة $n صنف' : 'Added $n items';
  String get nothingAdded => isArabic ? 'لا شيء لإضافته' : 'Nothing to add';

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
  String get changeDisplayName =>
      isArabic ? 'تغيير الاسم' : 'Change display name';
  String get changeDisplayNameBody => isArabic
      ? 'هذا الاسم يظهر لمن تشاركهم قائمتك.'
      : 'This name is shown to people you share your list with.';
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

  // item attribution (shared lists)
  String addedBy(String who) => isArabic ? 'أضافه $who' : 'Added by $who';
  String editedBy(String who) =>
      isArabic ? 'آخر تعديل: $who' : 'Last edited by $who';

  // buy again (Phase 2)
  String get buyAgain => isArabic ? 'اشترِ مجدداً' : 'Buy again';
  String get dueBadge => isArabic ? 'حان وقتها' : 'Due';

  // activity feed (Phase 2)
  String get activity => isArabic ? 'النشاط الأخير' : 'Recent activity';
  String get activityEmpty => isArabic ? 'لا يوجد نشاط بعد' : 'No activity yet';
  String get activityEmptySub => isArabic
      ? 'ستظهر هنا تغييرات قائمتك وما يشطبه شركاؤك'
      : 'Changes to your list and what your partners check off show up here';
  String get loadMore => isArabic ? 'تحميل المزيد' : 'Load more';
  String get retry => isArabic ? 'إعادة المحاولة' : 'Retry';

  String actAdded(String who, String what) =>
      isArabic ? '$who أضاف $what' : '$who added $what';
  String actEdited(String who, String what) =>
      isArabic ? '$who عدّل $what' : '$who edited $what';
  String actScratched(String who, String what) =>
      isArabic ? '$who شطب $what' : '$who checked off $what';
  String actDeleted(String who, String what) =>
      isArabic ? '$who حذف $what' : '$who removed $what';
  String actRestored(String who, String what) =>
      isArabic ? '$who استرجع $what' : '$who restored $what';
  String actCleared(String who, int n) =>
      isArabic ? '$who مسح $n من الأصناف' : '$who cleared $n items';
  String actShareAccepted(String who) =>
      isArabic ? '$who انضم إلى القائمة' : '$who joined the list';
  String actShareRevoked(String who) =>
      isArabic ? '$who غادر القائمة' : '$who left the list';

  // insights (Phase 2)
  String get insights => isArabic ? 'إحصاءات' : 'Insights';
  String insLastDays(int n) => isArabic ? 'آخر $n يوم' : 'Last $n days';
  String get insChecked => isArabic ? 'تم شطبها' : 'Checked off';
  String get insDistinct => isArabic ? 'أصناف مختلفة' : 'Products';
  String get insTopProducts => isArabic ? 'الأكثر شراءً' : 'Most bought';
  String get insByCategory => isArabic ? 'حسب التصنيف' : 'By category';
  String get insByDay => isArabic ? 'حسب أيام الأسبوع' : 'By day of week';
  String get insEmpty =>
      isArabic ? 'لا يوجد سجل كافٍ بعد' : 'Not enough history yet';
  String get insEmptySub => isArabic
      ? 'اشطب الأصناف عند شرائها لبناء إحصاءات تسوّقك'
      : 'Check items off as you buy them to build your shopping insights';
  String insTimes(int n) => isArabic ? '$n×' : '$n×';

  /// Short weekday labels, Sunday-first (matches `Insights.byDayOfWeek`).
  List<String> get daysOfWeekShort => isArabic
      ? const ['أحد', 'إثنين', 'ثلاثاء', 'أربعاء', 'خميس', 'جمعة', 'سبت']
      : const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  // push notifications (foreground toast; the backend's `data.type` drives these
  // so the message is localized client-side rather than relying on the body)
  String get pushShareRequested =>
      isArabic ? 'لديك طلب مشاركة جديد' : 'New share request';
  String get pushShareAccepted =>
      isArabic ? 'تم قبول طلب المشاركة' : 'Your share was accepted';
  String get pushItemAdded => isArabic
      ? 'تمت إضافة صنف إلى قائمة مشتركة'
      : 'An item was added to a shared list';
  String get pushItemEdited => isArabic
      ? 'تم تعديل صنف في قائمة مشتركة'
      : 'An item was updated on a shared list';
  String get pushShoppingStarted =>
      isArabic ? 'بدأ أحدهم التسوّق الآن' : 'Someone started shopping';

  // PWA install prompt (web only)
  String get installPwa => isArabic ? 'تثبيت' : 'Install';
  String get installPwaTitle =>
      isArabic ? 'ثبّت مونة على جهازك' : 'Install Moona on your device';
  String get installPwaBody => isArabic
      ? 'أضف مونة إلى شاشتك الرئيسية لفتحٍ أسرع وتجربة بملء الشاشة.'
      : 'Add Moona to your home screen for faster, full-screen access.';
  String get notNow => isArabic ? 'ليس الآن' : 'Not now';

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
