import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';

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

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
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
  static const List<Locale> supportedLocales = <Locale>[Locale('de')];

  /// No description provided for @appTitle.
  ///
  /// In de, this message translates to:
  /// **'Einkauf'**
  String get appTitle;

  /// No description provided for @addFieldHint.
  ///
  /// In de, this message translates to:
  /// **'Was fehlt?'**
  String get addFieldHint;

  /// No description provided for @addButton.
  ///
  /// In de, this message translates to:
  /// **'Hinzufügen'**
  String get addButton;

  /// No description provided for @emptyList.
  ///
  /// In de, this message translates to:
  /// **'Die Liste ist leer. Tippe oben ein, was fehlt.'**
  String get emptyList;

  /// No description provided for @sortingItem.
  ///
  /// In de, this message translates to:
  /// **'Wird einsortiert …'**
  String get sortingItem;

  /// No description provided for @recentlyBought.
  ///
  /// In de, this message translates to:
  /// **'Zuletzt gekauft'**
  String get recentlyBought;

  /// No description provided for @readd.
  ///
  /// In de, this message translates to:
  /// **'Wieder auf die Liste'**
  String get readd;

  /// No description provided for @tickItem.
  ///
  /// In de, this message translates to:
  /// **'{name} abhaken'**
  String tickItem(String name);

  /// No description provided for @itemTicked.
  ///
  /// In de, this message translates to:
  /// **'{name} abgehakt'**
  String itemTicked(String name);

  /// No description provided for @itemDeleted.
  ///
  /// In de, this message translates to:
  /// **'{name} gelöscht'**
  String itemDeleted(String name);

  /// No description provided for @itemReadded.
  ///
  /// In de, this message translates to:
  /// **'{name} steht wieder auf der Liste'**
  String itemReadded(String name);

  /// No description provided for @alreadyOnList.
  ///
  /// In de, this message translates to:
  /// **'{name} steht schon auf der Liste'**
  String alreadyOnList(String name);

  /// No description provided for @undo.
  ///
  /// In de, this message translates to:
  /// **'Rückgängig'**
  String get undo;

  /// No description provided for @editItem.
  ///
  /// In de, this message translates to:
  /// **'Eintrag bearbeiten'**
  String get editItem;

  /// No description provided for @itemName.
  ///
  /// In de, this message translates to:
  /// **'Name'**
  String get itemName;

  /// No description provided for @itemQuantity.
  ///
  /// In de, this message translates to:
  /// **'Menge'**
  String get itemQuantity;

  /// No description provided for @itemQuantityHint.
  ///
  /// In de, this message translates to:
  /// **'z. B. 2 oder 500 g'**
  String get itemQuantityHint;

  /// No description provided for @itemCategory.
  ///
  /// In de, this message translates to:
  /// **'Kategorie'**
  String get itemCategory;

  /// No description provided for @save.
  ///
  /// In de, this message translates to:
  /// **'Speichern'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In de, this message translates to:
  /// **'Abbrechen'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In de, this message translates to:
  /// **'Löschen'**
  String get delete;

  /// No description provided for @offline.
  ///
  /// In de, this message translates to:
  /// **'Offline: Änderungen werden synchronisiert, sobald die Verbindung zurück ist'**
  String get offline;

  /// No description provided for @pendingChanges.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Änderung wird synchronisiert} other{{count} Änderungen werden synchronisiert}}'**
  String pendingChanges(int count);

  /// No description provided for @syncFailed.
  ///
  /// In de, this message translates to:
  /// **'Änderung abgelehnt: {name}'**
  String syncFailed(String name);

  /// No description provided for @menu.
  ///
  /// In de, this message translates to:
  /// **'Menü'**
  String get menu;

  /// No description provided for @inviteMember.
  ///
  /// In de, this message translates to:
  /// **'Mitglied einladen'**
  String get inviteMember;

  /// No description provided for @joinOtherHousehold.
  ///
  /// In de, this message translates to:
  /// **'Anderem Haushalt beitreten'**
  String get joinOtherHousehold;

  /// No description provided for @signOut.
  ///
  /// In de, this message translates to:
  /// **'Abmelden'**
  String get signOut;

  /// No description provided for @inviteTitle.
  ///
  /// In de, this message translates to:
  /// **'Mitglied einladen'**
  String get inviteTitle;

  /// No description provided for @inviteBody.
  ///
  /// In de, this message translates to:
  /// **'Gib diesen Code in der App ein oder teile den Link. Er ist 14 Tage gültig.'**
  String get inviteBody;

  /// No description provided for @inviteCodeLabel.
  ///
  /// In de, this message translates to:
  /// **'Code'**
  String get inviteCodeLabel;

  /// No description provided for @inviteLinkLabel.
  ///
  /// In de, this message translates to:
  /// **'Link'**
  String get inviteLinkLabel;

  /// No description provided for @copy.
  ///
  /// In de, this message translates to:
  /// **'Kopieren'**
  String get copy;

  /// No description provided for @copied.
  ///
  /// In de, this message translates to:
  /// **'Kopiert'**
  String get copied;

  /// No description provided for @close.
  ///
  /// In de, this message translates to:
  /// **'Schließen'**
  String get close;

  /// No description provided for @signInTitle.
  ///
  /// In de, this message translates to:
  /// **'Anmelden'**
  String get signInTitle;

  /// No description provided for @email.
  ///
  /// In de, this message translates to:
  /// **'E-Mail'**
  String get email;

  /// No description provided for @password.
  ///
  /// In de, this message translates to:
  /// **'Passwort'**
  String get password;

  /// No description provided for @signIn.
  ///
  /// In de, this message translates to:
  /// **'Anmelden'**
  String get signIn;

  /// No description provided for @signUp.
  ///
  /// In de, this message translates to:
  /// **'Registrieren'**
  String get signUp;

  /// No description provided for @sendMagicLink.
  ///
  /// In de, this message translates to:
  /// **'Anmeldelink per E-Mail senden'**
  String get sendMagicLink;

  /// No description provided for @magicLinkSent.
  ///
  /// In de, this message translates to:
  /// **'Wir haben dir einen Anmeldelink geschickt. Öffne ihn auf diesem Gerät.'**
  String get magicLinkSent;

  /// No description provided for @signUpCheckEmail.
  ///
  /// In de, this message translates to:
  /// **'Bitte bestätige deine E-Mail-Adresse über den Link, den wir dir geschickt haben.'**
  String get signUpCheckEmail;

  /// No description provided for @invalidEmail.
  ///
  /// In de, this message translates to:
  /// **'Bitte eine gültige E-Mail-Adresse eingeben'**
  String get invalidEmail;

  /// No description provided for @passwordTooShort.
  ///
  /// In de, this message translates to:
  /// **'Mindestens 6 Zeichen'**
  String get passwordTooShort;

  /// No description provided for @authFailed.
  ///
  /// In de, this message translates to:
  /// **'Anmeldung fehlgeschlagen: {message}'**
  String authFailed(String message);

  /// No description provided for @onboardingTitle.
  ///
  /// In de, this message translates to:
  /// **'Willkommen'**
  String get onboardingTitle;

  /// No description provided for @onboardingBody.
  ///
  /// In de, this message translates to:
  /// **'Lege einen Haushalt an oder tritt mit einem Einladungscode bei.'**
  String get onboardingBody;

  /// No description provided for @householdName.
  ///
  /// In de, this message translates to:
  /// **'Name des Haushalts'**
  String get householdName;

  /// No description provided for @householdNameDefault.
  ///
  /// In de, this message translates to:
  /// **'Unser Haushalt'**
  String get householdNameDefault;

  /// No description provided for @createHousehold.
  ///
  /// In de, this message translates to:
  /// **'Haushalt anlegen'**
  String get createHousehold;

  /// No description provided for @inviteCode.
  ///
  /// In de, this message translates to:
  /// **'Einladungscode'**
  String get inviteCode;

  /// No description provided for @joinHousehold.
  ///
  /// In de, this message translates to:
  /// **'Beitreten'**
  String get joinHousehold;

  /// No description provided for @invalidInvite.
  ///
  /// In de, this message translates to:
  /// **'Dieser Code ist ungültig oder abgelaufen.'**
  String get invalidInvite;

  /// No description provided for @switchHouseholdWarning.
  ///
  /// In de, this message translates to:
  /// **'Du verlässt deinen aktuellen Haushalt. Bist du der letzte, wird er mit seiner Liste gelöscht.'**
  String get switchHouseholdWarning;

  /// No description provided for @genericError.
  ///
  /// In de, this message translates to:
  /// **'Etwas ist schiefgelaufen: {message}'**
  String genericError(String message);

  /// No description provided for @loading.
  ///
  /// In de, this message translates to:
  /// **'Lädt …'**
  String get loading;
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
      <String>['de'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
