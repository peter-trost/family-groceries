// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'Einkauf';

  @override
  String get addFieldHint => 'Was fehlt?';

  @override
  String get addButton => 'Hinzufügen';

  @override
  String get emptyList => 'Die Liste ist leer. Tippe oben ein, was fehlt.';

  @override
  String get sortingItem => 'Wird einsortiert …';

  @override
  String get recentlyBought => 'Zuletzt gekauft';

  @override
  String get readd => 'Wieder auf die Liste';

  @override
  String tickItem(String name) {
    return '$name abhaken';
  }

  @override
  String itemTicked(String name) {
    return '$name abgehakt';
  }

  @override
  String itemDeleted(String name) {
    return '$name gelöscht';
  }

  @override
  String itemReadded(String name) {
    return '$name steht wieder auf der Liste';
  }

  @override
  String alreadyOnList(String name) {
    return '$name steht schon auf der Liste';
  }

  @override
  String get undo => 'Rückgängig';

  @override
  String get editItem => 'Eintrag bearbeiten';

  @override
  String get itemName => 'Name';

  @override
  String get itemQuantity => 'Menge';

  @override
  String get itemQuantityHint => 'z. B. 2 oder 500 g';

  @override
  String get itemCategory => 'Kategorie';

  @override
  String get save => 'Speichern';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get delete => 'Löschen';

  @override
  String get offline =>
      'Offline: Änderungen werden synchronisiert, sobald die Verbindung zurück ist';

  @override
  String pendingChanges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Änderungen werden synchronisiert',
      one: '1 Änderung wird synchronisiert',
    );
    return '$_temp0';
  }

  @override
  String syncFailed(String name) {
    return 'Änderung abgelehnt: $name';
  }

  @override
  String get menu => 'Menü';

  @override
  String get inviteMember => 'Mitglied einladen';

  @override
  String get joinOtherHousehold => 'Anderem Haushalt beitreten';

  @override
  String get signOut => 'Abmelden';

  @override
  String get inviteTitle => 'Mitglied einladen';

  @override
  String get inviteBody =>
      'Gib diesen Code in der App ein oder teile den Link. Er ist 14 Tage gültig.';

  @override
  String get inviteCodeLabel => 'Code';

  @override
  String get inviteLinkLabel => 'Link';

  @override
  String get copy => 'Kopieren';

  @override
  String get copied => 'Kopiert';

  @override
  String get close => 'Schließen';

  @override
  String get signInTitle => 'Anmelden';

  @override
  String get email => 'E-Mail';

  @override
  String get password => 'Passwort';

  @override
  String get signIn => 'Anmelden';

  @override
  String get signUp => 'Registrieren';

  @override
  String get sendMagicLink => 'Anmeldelink per E-Mail senden';

  @override
  String get magicLinkSent =>
      'Wir haben dir einen Anmeldelink geschickt. Öffne ihn auf diesem Gerät.';

  @override
  String get signUpCheckEmail =>
      'Bitte bestätige deine E-Mail-Adresse über den Link, den wir dir geschickt haben.';

  @override
  String get invalidEmail => 'Bitte eine gültige E-Mail-Adresse eingeben';

  @override
  String get passwordTooShort => 'Mindestens 6 Zeichen';

  @override
  String authFailed(String message) {
    return 'Anmeldung fehlgeschlagen: $message';
  }

  @override
  String get signInWithGoogle => 'Mit Google anmelden';

  @override
  String get signInWithApple => 'Mit Apple anmelden';

  @override
  String get signInCanceled => 'Anmeldung abgebrochen';

  @override
  String get orWithEmail => 'oder mit E-Mail';

  @override
  String get onboardingTitle => 'Willkommen';

  @override
  String get onboardingBody =>
      'Lege einen Haushalt an oder tritt mit einem Einladungscode bei.';

  @override
  String get householdName => 'Name des Haushalts';

  @override
  String get householdNameDefault => 'Unser Haushalt';

  @override
  String get createHousehold => 'Haushalt anlegen';

  @override
  String get inviteCode => 'Einladungscode';

  @override
  String get joinHousehold => 'Beitreten';

  @override
  String get invalidInvite => 'Dieser Code ist ungültig oder abgelaufen.';

  @override
  String get switchHouseholdWarning =>
      'Du verlässt deinen aktuellen Haushalt. Bist du der letzte, wird er mit seiner Liste gelöscht.';

  @override
  String genericError(String message) {
    return 'Etwas ist schiefgelaufen: $message';
  }

  @override
  String get loading => 'Lädt …';

  @override
  String get consentTitle => 'Zugriff erlauben?';

  @override
  String consentSignedInAs(String email) {
    return 'Angemeldet als $email';
  }

  @override
  String consentHousehold(String name) {
    return 'Haushalt: $name';
  }

  @override
  String consentWants(String client) {
    return '$client möchte:';
  }

  @override
  String get consentListAccess =>
      'Einträge deiner Einkaufsliste lesen, hinzufügen, abhaken und verschieben';

  @override
  String get scopeOpenid => 'Deine Anmeldung bestätigen';

  @override
  String get scopeEmail => 'Deine E-Mail-Adresse';

  @override
  String get scopeProfile => 'Dein Name und Profil';

  @override
  String get scopePhone => 'Deine Telefonnummer';

  @override
  String get scopeOfflineAccess => 'Dauerhaft angemeldet bleiben';

  @override
  String get consentAllow => 'Erlauben';

  @override
  String get consentDeny => 'Ablehnen';

  @override
  String get redirecting => 'Weiterleitung …';

  @override
  String get consentInvalid =>
      'Diese Anfrage ist ungültig oder abgelaufen. Starte die Verbindung in deiner App neu.';

  @override
  String get accessTitle => 'Zugänge';

  @override
  String get mcpServer => 'MCP-Server';

  @override
  String get mcpServerBody =>
      'Für Claude, ChatGPT und andere KI-Assistenten. Verbinde per Anmeldung (OAuth) oder mit einem Zugriffstoken.';

  @override
  String get accessTokens => 'Zugriffstoken';

  @override
  String get noTokens => 'Kein aktiver Token.';

  @override
  String tokenHint(String hint) {
    return '…$hint';
  }

  @override
  String createdOn(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Erstellt am $dateString';
  }

  @override
  String lastUsedOn(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Zuletzt benutzt $dateString';
  }

  @override
  String get neverUsed => 'Noch nie benutzt';

  @override
  String get createToken => 'Token erstellen';

  @override
  String get create => 'Erstellen';

  @override
  String get tokenName => 'Name';

  @override
  String get tokenNameHint => 'z. B. Claude oder Siri';

  @override
  String get tokenCreated => 'Token erstellt';

  @override
  String get tokenShownOnce =>
      'Kopiere den Token jetzt. Er wird nicht noch einmal angezeigt.';

  @override
  String get done => 'Fertig';

  @override
  String revokeToken(String name) {
    return '$name widerrufen';
  }

  @override
  String get revokeTokenTitle => 'Token widerrufen?';

  @override
  String get revokeTokenBody =>
      'Apps, die ihn benutzen, verlieren sofort den Zugriff.';

  @override
  String get revoke => 'Widerrufen';

  @override
  String get tooManyTokens => 'Höchstens 20 aktive Tokens.';

  @override
  String get connectedApps => 'Verbundene Apps';

  @override
  String get noConnectedApps => 'Noch keine App verbunden.';

  @override
  String connectedOn(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Verbunden am $dateString';
  }

  @override
  String get disconnect => 'Trennen';

  @override
  String disconnectApp(String name) {
    return '$name trennen';
  }

  @override
  String disconnectTitle(String name) {
    return '$name trennen?';
  }

  @override
  String get disconnectBody =>
      'Die App verliert sofort den Zugriff auf deine Liste.';
}
