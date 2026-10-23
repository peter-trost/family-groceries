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

  /// No description provided for @dictationStart.
  ///
  /// In de, this message translates to:
  /// **'Diktieren'**
  String get dictationStart;

  /// No description provided for @dictationStop.
  ///
  /// In de, this message translates to:
  /// **'Diktat beenden'**
  String get dictationStop;

  /// No description provided for @dictationListening.
  ///
  /// In de, this message translates to:
  /// **'Ich höre zu …'**
  String get dictationListening;

  /// No description provided for @dictationUnavailable.
  ///
  /// In de, this message translates to:
  /// **'Spracheingabe ist nicht verfügbar. Erlaube Mikrofon und Spracherkennung in den Einstellungen.'**
  String get dictationUnavailable;

  /// No description provided for @dictationNoOfflineGerman.
  ///
  /// In de, this message translates to:
  /// **'Diktieren geht nur offline, damit deine Stimme auf dem Gerät bleibt. Dafür fehlt hier die deutsche Offline-Spracherkennung. Lade sie in den Systemeinstellungen herunter oder tippe den Eintrag ein.'**
  String get dictationNoOfflineGerman;

  /// No description provided for @dictationNothingHeard.
  ///
  /// In de, this message translates to:
  /// **'Ich habe nichts gehört.'**
  String get dictationNothingHeard;

  /// No description provided for @dictationNothingUnderstood.
  ///
  /// In de, this message translates to:
  /// **'Ich habe nichts verstanden, was auf die Liste soll.'**
  String get dictationNothingUnderstood;

  /// No description provided for @dictationSplitFailed.
  ///
  /// In de, this message translates to:
  /// **'Keine Verbindung. Der Text steht im Feld; prüfe ihn und tippe auf Hinzufügen.'**
  String get dictationSplitFailed;

  /// No description provided for @dictationAdded.
  ///
  /// In de, this message translates to:
  /// **'Hinzugefügt: {items}.'**
  String dictationAdded(String items);

  /// No description provided for @dictationAlreadyOnList.
  ///
  /// In de, this message translates to:
  /// **'Schon auf der Liste: {items}.'**
  String dictationAlreadyOnList(String items);

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

  /// No description provided for @signInWithGoogle.
  ///
  /// In de, this message translates to:
  /// **'Mit Google anmelden'**
  String get signInWithGoogle;

  /// No description provided for @signInWithApple.
  ///
  /// In de, this message translates to:
  /// **'Mit Apple anmelden'**
  String get signInWithApple;

  /// No description provided for @signInCanceled.
  ///
  /// In de, this message translates to:
  /// **'Anmeldung abgebrochen'**
  String get signInCanceled;

  /// No description provided for @orWithEmail.
  ///
  /// In de, this message translates to:
  /// **'oder mit E-Mail'**
  String get orWithEmail;

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

  /// No description provided for @consentTitle.
  ///
  /// In de, this message translates to:
  /// **'Zugriff erlauben?'**
  String get consentTitle;

  /// No description provided for @consentSignedInAs.
  ///
  /// In de, this message translates to:
  /// **'Angemeldet als {email}'**
  String consentSignedInAs(String email);

  /// No description provided for @consentHousehold.
  ///
  /// In de, this message translates to:
  /// **'Haushalt: {name}'**
  String consentHousehold(String name);

  /// No description provided for @consentWants.
  ///
  /// In de, this message translates to:
  /// **'{client} möchte:'**
  String consentWants(String client);

  /// No description provided for @consentListAccess.
  ///
  /// In de, this message translates to:
  /// **'Einträge deiner Einkaufsliste lesen, hinzufügen, abhaken und verschieben'**
  String get consentListAccess;

  /// No description provided for @scopeOpenid.
  ///
  /// In de, this message translates to:
  /// **'Deine Anmeldung bestätigen'**
  String get scopeOpenid;

  /// No description provided for @scopeEmail.
  ///
  /// In de, this message translates to:
  /// **'Deine E-Mail-Adresse'**
  String get scopeEmail;

  /// No description provided for @scopeProfile.
  ///
  /// In de, this message translates to:
  /// **'Dein Name und Profil'**
  String get scopeProfile;

  /// No description provided for @scopePhone.
  ///
  /// In de, this message translates to:
  /// **'Deine Telefonnummer'**
  String get scopePhone;

  /// No description provided for @scopeOfflineAccess.
  ///
  /// In de, this message translates to:
  /// **'Dauerhaft angemeldet bleiben'**
  String get scopeOfflineAccess;

  /// No description provided for @consentAllow.
  ///
  /// In de, this message translates to:
  /// **'Erlauben'**
  String get consentAllow;

  /// No description provided for @consentDeny.
  ///
  /// In de, this message translates to:
  /// **'Ablehnen'**
  String get consentDeny;

  /// No description provided for @redirecting.
  ///
  /// In de, this message translates to:
  /// **'Weiterleitung …'**
  String get redirecting;

  /// No description provided for @consentInvalid.
  ///
  /// In de, this message translates to:
  /// **'Diese Anfrage ist ungültig oder abgelaufen. Starte die Verbindung in deiner App neu.'**
  String get consentInvalid;

  /// No description provided for @accessTitle.
  ///
  /// In de, this message translates to:
  /// **'Zugänge'**
  String get accessTitle;

  /// No description provided for @mcpServer.
  ///
  /// In de, this message translates to:
  /// **'MCP-Server'**
  String get mcpServer;

  /// No description provided for @mcpServerBody.
  ///
  /// In de, this message translates to:
  /// **'Für Claude, ChatGPT und andere KI-Assistenten. Verbinde per Anmeldung (OAuth) oder mit einem Zugriffstoken.'**
  String get mcpServerBody;

  /// No description provided for @accessTokens.
  ///
  /// In de, this message translates to:
  /// **'Zugriffstoken'**
  String get accessTokens;

  /// No description provided for @noTokens.
  ///
  /// In de, this message translates to:
  /// **'Kein aktiver Token.'**
  String get noTokens;

  /// No description provided for @tokenHint.
  ///
  /// In de, this message translates to:
  /// **'…{hint}'**
  String tokenHint(String hint);

  /// No description provided for @createdOn.
  ///
  /// In de, this message translates to:
  /// **'Erstellt am {date}'**
  String createdOn(DateTime date);

  /// No description provided for @lastUsedOn.
  ///
  /// In de, this message translates to:
  /// **'Zuletzt benutzt {date}'**
  String lastUsedOn(DateTime date);

  /// No description provided for @neverUsed.
  ///
  /// In de, this message translates to:
  /// **'Noch nie benutzt'**
  String get neverUsed;

  /// No description provided for @createToken.
  ///
  /// In de, this message translates to:
  /// **'Token erstellen'**
  String get createToken;

  /// No description provided for @create.
  ///
  /// In de, this message translates to:
  /// **'Erstellen'**
  String get create;

  /// No description provided for @tokenName.
  ///
  /// In de, this message translates to:
  /// **'Name'**
  String get tokenName;

  /// No description provided for @tokenNameHint.
  ///
  /// In de, this message translates to:
  /// **'z. B. Claude oder Siri'**
  String get tokenNameHint;

  /// No description provided for @tokenCreated.
  ///
  /// In de, this message translates to:
  /// **'Token erstellt'**
  String get tokenCreated;

  /// No description provided for @tokenShownOnce.
  ///
  /// In de, this message translates to:
  /// **'Kopiere den Token jetzt. Er wird nicht noch einmal angezeigt.'**
  String get tokenShownOnce;

  /// No description provided for @done.
  ///
  /// In de, this message translates to:
  /// **'Fertig'**
  String get done;

  /// No description provided for @revokeToken.
  ///
  /// In de, this message translates to:
  /// **'{name} widerrufen'**
  String revokeToken(String name);

  /// No description provided for @revokeTokenTitle.
  ///
  /// In de, this message translates to:
  /// **'Token widerrufen?'**
  String get revokeTokenTitle;

  /// No description provided for @revokeTokenBody.
  ///
  /// In de, this message translates to:
  /// **'Apps, die ihn benutzen, verlieren sofort den Zugriff.'**
  String get revokeTokenBody;

  /// No description provided for @revoke.
  ///
  /// In de, this message translates to:
  /// **'Widerrufen'**
  String get revoke;

  /// No description provided for @tooManyTokens.
  ///
  /// In de, this message translates to:
  /// **'Höchstens 20 aktive Tokens.'**
  String get tooManyTokens;

  /// No description provided for @connectedApps.
  ///
  /// In de, this message translates to:
  /// **'Verbundene Apps'**
  String get connectedApps;

  /// No description provided for @noConnectedApps.
  ///
  /// In de, this message translates to:
  /// **'Noch keine App verbunden.'**
  String get noConnectedApps;

  /// No description provided for @connectedOn.
  ///
  /// In de, this message translates to:
  /// **'Verbunden am {date}'**
  String connectedOn(DateTime date);

  /// No description provided for @disconnect.
  ///
  /// In de, this message translates to:
  /// **'Trennen'**
  String get disconnect;

  /// No description provided for @disconnectApp.
  ///
  /// In de, this message translates to:
  /// **'{name} trennen'**
  String disconnectApp(String name);

  /// No description provided for @disconnectTitle.
  ///
  /// In de, this message translates to:
  /// **'{name} trennen?'**
  String disconnectTitle(String name);

  /// No description provided for @disconnectBody.
  ///
  /// In de, this message translates to:
  /// **'Die App verliert sofort den Zugriff auf deine Liste.'**
  String get disconnectBody;

  /// No description provided for @allStores.
  ///
  /// In de, this message translates to:
  /// **'Alle'**
  String get allStores;

  /// No description provided for @editStoreLayout.
  ///
  /// In de, this message translates to:
  /// **'Reihenfolge bearbeiten'**
  String get editStoreLayout;

  /// No description provided for @showHiddenItems.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Artikel, den es bei {store} meist nicht gibt, anzeigen} other{{count} Artikel, die es bei {store} meist nicht gibt, anzeigen}}'**
  String showHiddenItems(int count, String store);

  /// No description provided for @hideHiddenItems.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Artikel, den es bei {store} meist nicht gibt, ausblenden} other{{count} Artikel, die es bei {store} meist nicht gibt, ausblenden}}'**
  String hideHiddenItems(int count, String store);

  /// No description provided for @emptyAtStore.
  ///
  /// In de, this message translates to:
  /// **'Für {store} steht nichts auf der Liste.'**
  String emptyAtStore(String store);

  /// No description provided for @itemStore.
  ///
  /// In de, this message translates to:
  /// **'Geschäft'**
  String get itemStore;

  /// No description provided for @anyStore.
  ///
  /// In de, this message translates to:
  /// **'Alle Geschäfte'**
  String get anyStore;

  /// No description provided for @manageCategories.
  ///
  /// In de, this message translates to:
  /// **'Kategorien verwalten'**
  String get manageCategories;

  /// No description provided for @categoriesTitle.
  ///
  /// In de, this message translates to:
  /// **'Kategorien'**
  String get categoriesTitle;

  /// No description provided for @categoriesHint.
  ///
  /// In de, this message translates to:
  /// **'In dieser Reihenfolge sortiert „Alle“ die Liste. Tippe auf eine Kategorie, um sie umzubenennen.'**
  String get categoriesHint;

  /// No description provided for @categoryName.
  ///
  /// In de, this message translates to:
  /// **'Name'**
  String get categoryName;

  /// No description provided for @renameCategory.
  ///
  /// In de, this message translates to:
  /// **'Kategorie umbenennen'**
  String get renameCategory;

  /// No description provided for @addCategory.
  ///
  /// In de, this message translates to:
  /// **'Kategorie hinzufügen'**
  String get addCategory;

  /// No description provided for @deleteCategory.
  ///
  /// In de, this message translates to:
  /// **'{name} löschen'**
  String deleteCategory(String name);

  /// No description provided for @moveItemsTo.
  ///
  /// In de, this message translates to:
  /// **'Artikel verschieben nach'**
  String get moveItemsTo;

  /// No description provided for @dragCategory.
  ///
  /// In de, this message translates to:
  /// **'{name} verschieben'**
  String dragCategory(String name);

  /// No description provided for @categoryNameTaken.
  ///
  /// In de, this message translates to:
  /// **'Eine Kategorie „{name}“ gibt es schon.'**
  String categoryNameTaken(String name);

  /// No description provided for @catalogSaveFailed.
  ///
  /// In de, this message translates to:
  /// **'Die Änderung konnte nicht gespeichert werden.'**
  String get catalogSaveFailed;

  /// No description provided for @storeLayoutTitle.
  ///
  /// In de, this message translates to:
  /// **'{store}: Reihenfolge'**
  String storeLayoutTitle(String store);

  /// No description provided for @storeLayoutHint.
  ///
  /// In de, this message translates to:
  /// **'Ordne die Kategorien so, wie du durch den Laden gehst. Schalte aus, was es dort nicht gibt.'**
  String get storeLayoutHint;

  /// No description provided for @storeCarries.
  ///
  /// In de, this message translates to:
  /// **'{category} gibt es bei {store}'**
  String storeCarries(String category, String store);
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
