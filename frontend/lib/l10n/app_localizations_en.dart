// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'ymatch';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get save => 'Save';

  @override
  String get create => 'Create';

  @override
  String get set => 'Set';

  @override
  String get remove => 'Remove';

  @override
  String get retry => 'Retry';

  @override
  String get refresh => 'Refresh';

  @override
  String get confirm => 'Confirm';

  @override
  String get masterKeyUuid => 'Master Key (UUID)';

  @override
  String get unknown => 'Unknown';

  @override
  String errorPrefix(String error) {
    return 'Error: $error';
  }

  @override
  String get loginTagline => 'Trade merch seamlessly.';

  @override
  String get loginBackendErrorTitle => 'Cannot connect to backend';

  @override
  String get loginBackendErrorBody =>
      'The service may be temporarily down.\nPlease try again in a little while.';

  @override
  String get loggingIn => 'Logging in...';

  @override
  String get restoreAccount => 'Restore Account';

  @override
  String get startAsNewUser => 'Start as New User';

  @override
  String get restoreExistingAccount => 'Restore Existing Account';

  @override
  String get navItems => 'Items';

  @override
  String get navMatches => 'Matches';

  @override
  String get navProfile => 'Profile';

  @override
  String get navAdmin => 'Admin';

  @override
  String get backendUnreachableBanner => 'Cannot connect to backend service';

  @override
  String get searchEventsHint => 'Search events, groups...';

  @override
  String get sortEvents => 'Sort Events';

  @override
  String get sortNewestFirst => 'Newest First';

  @override
  String get sortMostPopular => 'Most Popular';

  @override
  String get sortAlphabetical => 'Alphabetical';

  @override
  String get newEvent => 'New Event';

  @override
  String get filterAllEvents => 'All Events';

  @override
  String get filterFavorites => 'Favorites';

  @override
  String get filterMyItems => 'My Items';

  @override
  String get noEventsMatchFilter => 'No events match this filter.';

  @override
  String tradersCount(int count) {
    return '$count traders';
  }

  @override
  String viewsCount(int count) {
    return '$count views';
  }

  @override
  String get draftBadge => 'DRAFT';

  @override
  String get unknownDate => 'Unknown date';

  @override
  String get invalidDate => 'Invalid date';

  @override
  String get editName => 'Edit Name';

  @override
  String get editEventName => 'Edit Event Name';

  @override
  String get eventNameHint => 'Event name';

  @override
  String get deleteEvent => 'Delete Event';

  @override
  String deleteEventConfirm(String name) {
    return 'Are you sure you want to delete \"$name\"?';
  }

  @override
  String get noEventsFound => 'No events found';

  @override
  String get createEventPrompt => 'Create an event to start trading.';

  @override
  String get createEvent => 'Create Event';

  @override
  String get eventNameLabel => 'Event Name';

  @override
  String newEventNameHint(int number) {
    return 'Event $number';
  }

  @override
  String favPrefix(String name) {
    return 'Fav: $name';
  }

  @override
  String get groupFallback => 'Group';

  @override
  String groupChipLabel(String event, String group) {
    return '$event: $group';
  }

  @override
  String get username => 'Username';

  @override
  String get editUsername => 'Edit username';

  @override
  String get usernameUpdated => 'Username updated';

  @override
  String failedToUpdateUsername(String error) {
    return 'Failed to update username: $error';
  }

  @override
  String get masterKeyCopied => 'Master Key copied to clipboard';

  @override
  String get saveKeyWarning =>
      'Save this key to restore your account on another device!';

  @override
  String get howToTrade => 'How to Trade';

  @override
  String get tradeStep1 => 'Go to the Events tab and find your event.';

  @override
  String get tradeStep2 => 'Use + and - to set your HAVE and WANT items.';

  @override
  String get tradeStep3 => 'Go to Matches to see who wants to trade with you.';

  @override
  String get logOut => 'Log Out';

  @override
  String revisionInfo(String frontend, String backend) {
    return 'frontend: $frontend  /  backend: $backend';
  }

  @override
  String get selectImageSource => 'Select Image Source';

  @override
  String get gallery => 'Gallery';

  @override
  String get camera => 'Camera';

  @override
  String failedToPickImage(String error) {
    return 'Failed to pick image: $error';
  }

  @override
  String get selectGroupFirst => 'Please select or create an item group first.';

  @override
  String addedSuccessfully(String name) {
    return 'Added \"$name\" successfully.';
  }

  @override
  String failedToAdd(String name, String error) {
    return 'Failed to add \"$name\": $error';
  }

  @override
  String get selectGroup => 'Select Group';

  @override
  String get newGroup => 'New Group';

  @override
  String get itemName => 'Item Name';

  @override
  String get itemNameHint => 'e.g., Rare Holo Card #1';

  @override
  String get photo => 'Photo';

  @override
  String get changeImage => 'Change Image';

  @override
  String get chooseImage => 'Choose Image';

  @override
  String get adding => 'Adding...';

  @override
  String get addItem => 'Add Item';

  @override
  String existingItemsInGroup(String group) {
    return 'Existing items in \"$group\"';
  }

  @override
  String get uncategorized => 'Uncategorized';

  @override
  String get noItemsInGroup => 'No items in this group yet.';

  @override
  String get newGroupName => 'New Group Name';

  @override
  String get newGroupHint => 'e.g., Keychains';

  @override
  String failedToSend(String error) {
    return 'Failed to send: $error';
  }

  @override
  String get noMessagesYet => 'No messages yet. Say hello!';

  @override
  String get typeMessage => 'Type a message...';

  @override
  String get openInMaps => 'Open in Maps';

  @override
  String get openLink => 'Open Link';

  @override
  String get have => 'Own';

  @override
  String get want => 'Wish';

  @override
  String get trade => 'For Trade';

  @override
  String get haveShort => 'O';

  @override
  String get wantShort => 'W';

  @override
  String get tradeShort => 'F';

  @override
  String get merchFilterAll => 'All';

  @override
  String get merchFilterMissing => 'Missing';

  @override
  String get invModeJustHave => 'Just Own';

  @override
  String get invModeWantTrade => 'Wish & For Trade';

  @override
  String get invModeAll => 'All';
}
