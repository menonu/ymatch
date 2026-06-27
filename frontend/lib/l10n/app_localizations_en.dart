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
  String get tradeStep1 => 'Go to the Items tab and find your event.';

  @override
  String get tradeStep2 =>
      'Use + and - to enter the quantities of items you want to exchange. Matching is performed within an item group based on your Wish / For Trade quantities.';

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
  String failedToUpdateItem(String name, String error) {
    return 'Failed to update \"$name\": $error';
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
  String get messageAction => 'Message';

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

  @override
  String get addMerch => 'Add Merch';

  @override
  String get otherItems => 'Other Items';

  @override
  String get searchItemsHint => 'Search items...';

  @override
  String get showControls => 'Show Controls';

  @override
  String get changeViewMode => 'Change View Mode';

  @override
  String get detailedView => 'Detailed View';

  @override
  String get gridView => 'Grid View';

  @override
  String get compactList => 'Compact List';

  @override
  String addedToWantPartial(int added, int failed) {
    return 'Added $added to Wish; could not add $failed';
  }

  @override
  String addedMissingToWant(int count) {
    return 'Added $count missing items to Wish';
  }

  @override
  String get couldNotAddToWant => 'Could not add some items to Wish';

  @override
  String get noMissingItems => 'No missing items found';

  @override
  String get wantAllMissing => 'Want All Missing';

  @override
  String get jumpToGroup => 'Jump to group';

  @override
  String get noItemsMatchFilter => 'No items match this filter.';

  @override
  String get youCreatedThisItem => 'You created this item';

  @override
  String get editItemName => 'Edit Item Name';

  @override
  String get editItemNameHint => 'Item name';

  @override
  String get deleteItem => 'Delete Item';

  @override
  String get noMerchandiseYet => 'No merchandise yet';

  @override
  String get buildInventoryPrompt =>
      'Add items to start building your inventory.';

  @override
  String get trades => 'Trades';

  @override
  String get tabMatch => 'Match';

  @override
  String get tabOfferOut => 'Offer Out';

  @override
  String get tabOfferIn => 'Offer In';

  @override
  String get tabActive => 'Active';

  @override
  String get tabDone => 'Done';

  @override
  String get unknownUser => '???';

  @override
  String get statusPending => 'PENDING';

  @override
  String get statusOffered => 'OFFERED';

  @override
  String get statusAccepted => 'ACCEPTED';

  @override
  String get statusCompleted => 'COMPLETED';

  @override
  String get youGive => 'You give:';

  @override
  String get youReceive => 'You receive:';

  @override
  String get giveLabel => 'Give:';

  @override
  String get receiveLabel => 'Receive:';

  @override
  String get reject => 'Reject';

  @override
  String get makeOffer => 'Make Offer';

  @override
  String get accept => 'Accept';

  @override
  String get cancelOffer => 'Cancel Offer';

  @override
  String get waitingForResponse => 'Waiting for response...';

  @override
  String get markComplete => 'Mark Complete';

  @override
  String get updateInventory => 'Update Inventory';

  @override
  String get inventoryUpdated => 'Inventory Updated';

  @override
  String get inventoryUpdatedSnack => 'Inventory updated!';

  @override
  String get makeTradeOffer => 'Make Trade Offer';

  @override
  String get itemsYouGive => 'Items you give:';

  @override
  String get itemsYouReceive => 'Items you receive:';

  @override
  String get counterOffer => 'Counter-offer';

  @override
  String get balanced => 'Balanced';

  @override
  String get unbalanced => 'Unbalanced';

  @override
  String get acceptBalanceHint => 'Accept requires a balanced offer';

  @override
  String balanceSummary(int give, int recv) {
    return 'You give $give / receive $recv';
  }

  @override
  String get balanceExplanation =>
      'A trade can be completed when the number of items you give and receive are balanced.';

  @override
  String qtyLabel(int count) {
    return 'Qty: $count';
  }

  @override
  String sendOfferItems(int count) {
    return 'Send Offer ($count items)';
  }

  @override
  String get noPendingMatches => 'No pending matches. Keep adding items!';

  @override
  String get noOutgoingOffers => 'No outgoing offers.';

  @override
  String get noIncomingOffers => 'No incoming offers.';

  @override
  String get noActiveTrades => 'No active trades.';

  @override
  String get noCompletedTrades => 'No completed trades yet.';
}
