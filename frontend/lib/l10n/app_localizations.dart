import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';

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
    Locale('en'),
    Locale('ja'),
  ];

  /// App brand name shown on the login screen
  ///
  /// In en, this message translates to:
  /// **'ymatch'**
  String get appName;

  /// Generic Cancel button label
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Generic Delete button label
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// Generic Save button label
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// Generic Create button label
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// Generic Set/confirm button label
  ///
  /// In en, this message translates to:
  /// **'Set'**
  String get set;

  /// Remove button label
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// Retry button label shown on backend errors
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// Refresh tooltip
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// Confirm button label
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// Label for the master key / UUID field
  ///
  /// In en, this message translates to:
  /// **'Master Key (UUID)'**
  String get masterKeyUuid;

  /// Placeholder shown when a value is missing
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknown;

  /// Generic error message with the underlying error text
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String errorPrefix(String error);

  /// Tagline shown under the app name on the login screen
  ///
  /// In en, this message translates to:
  /// **'Trade merch seamlessly.'**
  String get loginTagline;

  /// Title shown when the backend is unreachable
  ///
  /// In en, this message translates to:
  /// **'Cannot connect to backend'**
  String get loginBackendErrorTitle;

  /// Body text shown when the backend is unreachable
  ///
  /// In en, this message translates to:
  /// **'The service may be temporarily down.\nPlease try again in a little while.'**
  String get loginBackendErrorBody;

  /// Loading text shown while logging in
  ///
  /// In en, this message translates to:
  /// **'Logging in...'**
  String get loggingIn;

  /// Restore account title and button label
  ///
  /// In en, this message translates to:
  /// **'Restore Account'**
  String get restoreAccount;

  /// Button to start a new guest session
  ///
  /// In en, this message translates to:
  /// **'Start as New User'**
  String get startAsNewUser;

  /// Button to reveal the account restore form
  ///
  /// In en, this message translates to:
  /// **'Restore Existing Account'**
  String get restoreExistingAccount;

  /// Bottom navigation bar label for the events/items tab
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get navItems;

  /// Bottom navigation bar label for the matches tab
  ///
  /// In en, this message translates to:
  /// **'Matches'**
  String get navMatches;

  /// Bottom navigation bar label for the profile tab
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get navProfile;

  /// Bottom navigation bar label for the admin tab
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get navAdmin;

  /// Banner text shown when the backend health check fails
  ///
  /// In en, this message translates to:
  /// **'Cannot connect to backend service'**
  String get backendUnreachableBanner;

  /// Hint text in the home screen search bar
  ///
  /// In en, this message translates to:
  /// **'Search events, groups...'**
  String get searchEventsHint;

  /// Tooltip for the event sort menu
  ///
  /// In en, this message translates to:
  /// **'Sort Events'**
  String get sortEvents;

  /// Sort option: newest events first
  ///
  /// In en, this message translates to:
  /// **'Newest First'**
  String get sortNewestFirst;

  /// Sort option: most popular events first
  ///
  /// In en, this message translates to:
  /// **'Most Popular'**
  String get sortMostPopular;

  /// Sort option: alphabetical order
  ///
  /// In en, this message translates to:
  /// **'Alphabetical'**
  String get sortAlphabetical;

  /// Floating action button label to create a new event
  ///
  /// In en, this message translates to:
  /// **'New Event'**
  String get newEvent;

  /// Filter segment label: all events
  ///
  /// In en, this message translates to:
  /// **'All Events'**
  String get filterAllEvents;

  /// Filter segment label: favorite events
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get filterFavorites;

  /// Filter segment label: events the user joined
  ///
  /// In en, this message translates to:
  /// **'My Items'**
  String get filterMyItems;

  /// Empty state when a filter matches no events
  ///
  /// In en, this message translates to:
  /// **'No events match this filter.'**
  String get noEventsMatchFilter;

  /// Number of active traders on an event
  ///
  /// In en, this message translates to:
  /// **'{count} traders'**
  String tradersCount(int count);

  /// Number of unique views on an event
  ///
  /// In en, this message translates to:
  /// **'{count} views'**
  String viewsCount(int count);

  /// Badge text shown on draft events
  ///
  /// In en, this message translates to:
  /// **'DRAFT'**
  String get draftBadge;

  /// Fallback when an event date is empty
  ///
  /// In en, this message translates to:
  /// **'Unknown date'**
  String get unknownDate;

  /// Fallback when an event date cannot be parsed
  ///
  /// In en, this message translates to:
  /// **'Invalid date'**
  String get invalidDate;

  /// Bottom sheet action to edit an event name
  ///
  /// In en, this message translates to:
  /// **'Edit Name'**
  String get editName;

  /// Dialog title for editing an event name
  ///
  /// In en, this message translates to:
  /// **'Edit Event Name'**
  String get editEventName;

  /// Hint text in the edit event name dialog
  ///
  /// In en, this message translates to:
  /// **'Event name'**
  String get eventNameHint;

  /// Dialog title for deleting an event
  ///
  /// In en, this message translates to:
  /// **'Delete Event'**
  String get deleteEvent;

  /// Confirmation message for deleting an event
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{name}\"?'**
  String deleteEventConfirm(String name);

  /// Empty state title when no events exist
  ///
  /// In en, this message translates to:
  /// **'No events found'**
  String get noEventsFound;

  /// Empty state subtitle prompting event creation
  ///
  /// In en, this message translates to:
  /// **'Create an event to start trading.'**
  String get createEventPrompt;

  /// Button label to create an event
  ///
  /// In en, this message translates to:
  /// **'Create Event'**
  String get createEvent;

  /// Label for the event name field in the new event dialog
  ///
  /// In en, this message translates to:
  /// **'Event Name'**
  String get eventNameLabel;

  /// Hint text suggesting a default event name
  ///
  /// In en, this message translates to:
  /// **'Event {number}'**
  String newEventNameHint(int number);

  /// Shortcut chip label for a favorite event
  ///
  /// In en, this message translates to:
  /// **'Fav: {name}'**
  String favPrefix(String name);

  /// Fallback label when a group has no event name
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get groupFallback;

  /// Shortcut chip label for a favorite group
  ///
  /// In en, this message translates to:
  /// **'{event}: {group}'**
  String groupChipLabel(String event, String group);

  /// Label for the username field
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// Tooltip for the edit username button
  ///
  /// In en, this message translates to:
  /// **'Edit username'**
  String get editUsername;

  /// Snackbar message on successful username update
  ///
  /// In en, this message translates to:
  /// **'Username updated'**
  String get usernameUpdated;

  /// Snackbar message when updating the username fails
  ///
  /// In en, this message translates to:
  /// **'Failed to update username: {error}'**
  String failedToUpdateUsername(String error);

  /// Snackbar message after copying the master key
  ///
  /// In en, this message translates to:
  /// **'Master Key copied to clipboard'**
  String get masterKeyCopied;

  /// Warning telling the user to save their master key
  ///
  /// In en, this message translates to:
  /// **'Save this key to restore your account on another device!'**
  String get saveKeyWarning;

  /// Title of the how-to-trade instructions card
  ///
  /// In en, this message translates to:
  /// **'How to Trade'**
  String get howToTrade;

  /// How-to-trade step 1
  ///
  /// In en, this message translates to:
  /// **'Go to the Items tab and find your event.'**
  String get tradeStep1;

  /// How-to-trade step 2
  ///
  /// In en, this message translates to:
  /// **'Use + and - to enter the quantities of items you want to exchange. Matching is performed within an item group based on your Wish / For Trade quantities.'**
  String get tradeStep2;

  /// How-to-trade step 3
  ///
  /// In en, this message translates to:
  /// **'Go to Matches to see who wants to trade with you.'**
  String get tradeStep3;

  /// Log out button label
  ///
  /// In en, this message translates to:
  /// **'Log Out'**
  String get logOut;

  /// Footer showing frontend and backend revision hashes
  ///
  /// In en, this message translates to:
  /// **'frontend: {frontend}  /  backend: {backend}'**
  String revisionInfo(String frontend, String backend);

  /// Dialog title for choosing image source
  ///
  /// In en, this message translates to:
  /// **'Select Image Source'**
  String get selectImageSource;

  /// Image source option: gallery
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get gallery;

  /// Image source option: camera
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get camera;

  /// Snackbar message when picking an image fails
  ///
  /// In en, this message translates to:
  /// **'Failed to pick image: {error}'**
  String failedToPickImage(String error);

  /// Snackbar message when no group is selected
  ///
  /// In en, this message translates to:
  /// **'Please select or create an item group first.'**
  String get selectGroupFirst;

  /// Snackbar message after an item is added
  ///
  /// In en, this message translates to:
  /// **'Added \"{name}\" successfully.'**
  String addedSuccessfully(String name);

  /// Snackbar message when adding an item fails
  ///
  /// In en, this message translates to:
  /// **'Failed to add \"{name}\": {error}'**
  String failedToAdd(String name, String error);

  /// Snackbar message when updating an item (e.g. renaming) fails, such as a duplicate-name 400 from #299
  ///
  /// In en, this message translates to:
  /// **'Failed to update \"{name}\": {error}'**
  String failedToUpdateItem(String name, String error);

  /// Section title for group selection
  ///
  /// In en, this message translates to:
  /// **'Select Group'**
  String get selectGroup;

  /// Action chip label to create a new group
  ///
  /// In en, this message translates to:
  /// **'New Group'**
  String get newGroup;

  /// Label for the item name field
  ///
  /// In en, this message translates to:
  /// **'Item Name'**
  String get itemName;

  /// Hint text for the item name field
  ///
  /// In en, this message translates to:
  /// **'e.g., Rare Holo Card #1'**
  String get itemNameHint;

  /// Caption under the photo placeholder
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get photo;

  /// Button label to change the picked image
  ///
  /// In en, this message translates to:
  /// **'Change Image'**
  String get changeImage;

  /// Button label to pick an image
  ///
  /// In en, this message translates to:
  /// **'Choose Image'**
  String get chooseImage;

  /// Button label while an item is being added
  ///
  /// In en, this message translates to:
  /// **'Adding...'**
  String get adding;

  /// Button label to add an item
  ///
  /// In en, this message translates to:
  /// **'Add Item'**
  String get addItem;

  /// Header above the list of existing items in a group
  ///
  /// In en, this message translates to:
  /// **'Existing items in \"{group}\"'**
  String existingItemsInGroup(String group);

  /// Fallback group name when none is selected
  ///
  /// In en, this message translates to:
  /// **'Uncategorized'**
  String get uncategorized;

  /// Empty state when a group has no items
  ///
  /// In en, this message translates to:
  /// **'No items in this group yet.'**
  String get noItemsInGroup;

  /// Dialog title for creating a new group
  ///
  /// In en, this message translates to:
  /// **'New Group Name'**
  String get newGroupName;

  /// Hint text for the new group name field
  ///
  /// In en, this message translates to:
  /// **'e.g., Keychains'**
  String get newGroupHint;

  /// Read-only label for the group name in the edit dialog
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get groupNameLabel;

  /// Label for the optional group description field
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get groupDescription;

  /// Hint text for the group description field
  ///
  /// In en, this message translates to:
  /// **'Optional notes about this group'**
  String get groupDescriptionHint;

  /// Dialog title for editing a group description
  ///
  /// In en, this message translates to:
  /// **'Edit Group'**
  String get editGroup;

  /// Tooltip / accessibility label for the group info button
  ///
  /// In en, this message translates to:
  /// **'Group info'**
  String get groupInfo;

  /// Placeholder when a group has no description
  ///
  /// In en, this message translates to:
  /// **'No description yet.'**
  String get noGroupDescription;

  /// Snackbar when creating or updating a group fails
  ///
  /// In en, this message translates to:
  /// **'Failed to save group: {error}'**
  String failedToSaveGroup(String error);

  /// Snackbar after a group is created or updated successfully
  ///
  /// In en, this message translates to:
  /// **'Group saved'**
  String get groupSaved;

  /// Tooltip on the shield icon shown to group creators
  ///
  /// In en, this message translates to:
  /// **'You can edit this group'**
  String get youCanEditGroup;

  /// Label for the optional group description image
  ///
  /// In en, this message translates to:
  /// **'Description image'**
  String get groupPhoto;

  /// Placeholder when the group has no description image
  ///
  /// In en, this message translates to:
  /// **'No image attached'**
  String get noGroupPhoto;

  /// Snackbar message when sending a chat message fails
  ///
  /// In en, this message translates to:
  /// **'Failed to send: {error}'**
  String failedToSend(String error);

  /// Empty state when a chat has no messages
  ///
  /// In en, this message translates to:
  /// **'No messages yet. Say hello!'**
  String get noMessagesYet;

  /// Hint text in the chat message input
  ///
  /// In en, this message translates to:
  /// **'Type a message...'**
  String get typeMessage;

  /// Button label on a match card to open the chat thread
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get messageAction;

  /// Link label for opening a map URL
  ///
  /// In en, this message translates to:
  /// **'Open in Maps'**
  String get openInMaps;

  /// Link label for opening a non-map URL
  ///
  /// In en, this message translates to:
  /// **'Open Link'**
  String get openLink;

  /// Inventory status: items the user owns (formerly HAVE)
  ///
  /// In en, this message translates to:
  /// **'Own'**
  String get have;

  /// Inventory status: items the user is looking for (formerly WANT)
  ///
  /// In en, this message translates to:
  /// **'Wish'**
  String get want;

  /// Inventory status: items the user offers to trade (formerly TRADE)
  ///
  /// In en, this message translates to:
  /// **'For Trade'**
  String get trade;

  /// Single-letter abbreviation for the Own status, used in compact counters
  ///
  /// In en, this message translates to:
  /// **'O'**
  String get haveShort;

  /// Single-letter abbreviation for the Wish status, used in compact counters
  ///
  /// In en, this message translates to:
  /// **'W'**
  String get wantShort;

  /// Single-letter abbreviation for the For Trade status, used in compact counters
  ///
  /// In en, this message translates to:
  /// **'F'**
  String get tradeShort;

  /// Merchandise filter segment: show all items
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get merchFilterAll;

  /// Merchandise filter segment: show items missing from inventory
  ///
  /// In en, this message translates to:
  /// **'Missing'**
  String get merchFilterMissing;

  /// Inventory display-mode option: show only owned items
  ///
  /// In en, this message translates to:
  /// **'Just Own'**
  String get invModeJustHave;

  /// Inventory display-mode option: show wished and for-trade items
  ///
  /// In en, this message translates to:
  /// **'Wish & For Trade'**
  String get invModeWantTrade;

  /// Inventory display-mode option: show all inventory items
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get invModeAll;

  /// Floating action button label to add merchandise
  ///
  /// In en, this message translates to:
  /// **'Add Merch'**
  String get addMerch;

  /// Fallback group name for items without a group
  ///
  /// In en, this message translates to:
  /// **'Other Items'**
  String get otherItems;

  /// Hint text in the event detail search bar
  ///
  /// In en, this message translates to:
  /// **'Search items...'**
  String get searchItemsHint;

  /// Tooltip for the inventory display-mode menu
  ///
  /// In en, this message translates to:
  /// **'Show Controls'**
  String get showControls;

  /// Tooltip for the view-mode menu
  ///
  /// In en, this message translates to:
  /// **'Change View Mode'**
  String get changeViewMode;

  /// View-mode option: detailed list
  ///
  /// In en, this message translates to:
  /// **'Detailed View'**
  String get detailedView;

  /// View-mode option: grid
  ///
  /// In en, this message translates to:
  /// **'Grid View'**
  String get gridView;

  /// View-mode option: compact list
  ///
  /// In en, this message translates to:
  /// **'Compact List'**
  String get compactList;

  /// Snackbar when some missing items were added to Wish and some failed
  ///
  /// In en, this message translates to:
  /// **'Added {added} to Wish; could not add {failed}'**
  String addedToWantPartial(int added, int failed);

  /// Snackbar when missing items were added to Wish
  ///
  /// In en, this message translates to:
  /// **'Added {count} missing items to Wish'**
  String addedMissingToWant(int count);

  /// Snackbar when adding missing items to Wish failed
  ///
  /// In en, this message translates to:
  /// **'Could not add some items to Wish'**
  String get couldNotAddToWant;

  /// Snackbar when there are no missing items to add
  ///
  /// In en, this message translates to:
  /// **'No missing items found'**
  String get noMissingItems;

  /// Menu item to add all missing items to Wish
  ///
  /// In en, this message translates to:
  /// **'Want All Missing'**
  String get wantAllMissing;

  /// Tooltip for the group jump menu
  ///
  /// In en, this message translates to:
  /// **'Jump to group'**
  String get jumpToGroup;

  /// Empty state when an item filter matches nothing
  ///
  /// In en, this message translates to:
  /// **'No items match this filter.'**
  String get noItemsMatchFilter;

  /// Tooltip on the creator badge of an item
  ///
  /// In en, this message translates to:
  /// **'You created this item'**
  String get youCreatedThisItem;

  /// Long-press menu entry to edit an item's name and image
  ///
  /// In en, this message translates to:
  /// **'Edit Item'**
  String get editItem;

  /// Dialog title for editing an item name
  ///
  /// In en, this message translates to:
  /// **'Edit Item Name'**
  String get editItemName;

  /// Hint text in the edit item name dialog
  ///
  /// In en, this message translates to:
  /// **'Item name'**
  String get editItemNameHint;

  /// Dialog title for deleting an item
  ///
  /// In en, this message translates to:
  /// **'Delete Item'**
  String get deleteItem;

  /// Empty state title when an event has no merchandise
  ///
  /// In en, this message translates to:
  /// **'No merchandise yet'**
  String get noMerchandiseYet;

  /// Empty state subtitle prompting item creation
  ///
  /// In en, this message translates to:
  /// **'Add items to start building your inventory.'**
  String get buildInventoryPrompt;

  /// AppBar title of the trades screen
  ///
  /// In en, this message translates to:
  /// **'Trades'**
  String get trades;

  /// Trades tab: pending matches
  ///
  /// In en, this message translates to:
  /// **'Match'**
  String get tabMatch;

  /// Trades tab: outgoing offers
  ///
  /// In en, this message translates to:
  /// **'Offer Out'**
  String get tabOfferOut;

  /// Trades tab: incoming offers
  ///
  /// In en, this message translates to:
  /// **'Offer In'**
  String get tabOfferIn;

  /// Trades tab: active (accepted) trades
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get tabActive;

  /// Trades tab: completed trades
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get tabDone;

  /// Placeholder shown when the other user's name is unknown
  ///
  /// In en, this message translates to:
  /// **'???'**
  String get unknownUser;

  /// Match status chip: pending
  ///
  /// In en, this message translates to:
  /// **'PENDING'**
  String get statusPending;

  /// Match status chip: offered
  ///
  /// In en, this message translates to:
  /// **'OFFERED'**
  String get statusOffered;

  /// Match status chip: accepted
  ///
  /// In en, this message translates to:
  /// **'ACCEPTED'**
  String get statusAccepted;

  /// Match status chip: completed
  ///
  /// In en, this message translates to:
  /// **'COMPLETED'**
  String get statusCompleted;

  /// Label above items the user would give (potential match)
  ///
  /// In en, this message translates to:
  /// **'You give:'**
  String get youGive;

  /// Label above items the user would receive (potential match)
  ///
  /// In en, this message translates to:
  /// **'You receive:'**
  String get youReceive;

  /// Label above items given in a selected offer
  ///
  /// In en, this message translates to:
  /// **'Give:'**
  String get giveLabel;

  /// Label above items received in a selected offer
  ///
  /// In en, this message translates to:
  /// **'Receive:'**
  String get receiveLabel;

  /// Reject offer button
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get reject;

  /// Button to open the offer dialog
  ///
  /// In en, this message translates to:
  /// **'Make Offer'**
  String get makeOffer;

  /// Accept offer button
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get accept;

  /// Cancel outgoing offer button
  ///
  /// In en, this message translates to:
  /// **'Cancel Offer'**
  String get cancelOffer;

  /// Hint shown on an outgoing offer awaiting a reply
  ///
  /// In en, this message translates to:
  /// **'Waiting for response...'**
  String get waitingForResponse;

  /// Button to mark an active trade complete
  ///
  /// In en, this message translates to:
  /// **'Mark Complete'**
  String get markComplete;

  /// Button to apply a completed trade to inventory
  ///
  /// In en, this message translates to:
  /// **'Update Inventory'**
  String get updateInventory;

  /// Label shown when a trade's inventory was already applied
  ///
  /// In en, this message translates to:
  /// **'Inventory Updated'**
  String get inventoryUpdated;

  /// Snackbar after applying a completed trade to inventory
  ///
  /// In en, this message translates to:
  /// **'Inventory updated!'**
  String get inventoryUpdatedSnack;

  /// Offer dialog title
  ///
  /// In en, this message translates to:
  /// **'Make Trade Offer'**
  String get makeTradeOffer;

  /// Section header in the offer dialog for give items
  ///
  /// In en, this message translates to:
  /// **'Items you give:'**
  String get itemsYouGive;

  /// Section header in the offer dialog for receive items
  ///
  /// In en, this message translates to:
  /// **'Items you receive:'**
  String get itemsYouReceive;

  /// Button for the non-proposer to edit and resend a proposal
  ///
  /// In en, this message translates to:
  /// **'Counter-offer'**
  String get counterOffer;

  /// Balance indicator label when the two sides give equal total quantity
  ///
  /// In en, this message translates to:
  /// **'Balanced'**
  String get balanced;

  /// Balance indicator label when the two sides give unequal total quantity
  ///
  /// In en, this message translates to:
  /// **'Unbalanced'**
  String get unbalanced;

  /// Hint explaining the accept button is disabled until balanced
  ///
  /// In en, this message translates to:
  /// **'Accept requires a balanced offer'**
  String get acceptBalanceHint;

  /// Per-side quantity totals shown on an OFFERED match card
  ///
  /// In en, this message translates to:
  /// **'You give {give} / receive {recv}'**
  String balanceSummary(int give, int recv);

  /// Plain-language hint in the offer dialog: a balanced give/receive total enables the trade
  ///
  /// In en, this message translates to:
  /// **'A trade can be completed when the number of items you give and receive are balanced.'**
  String get balanceExplanation;

  /// Quantity label in the offer dialog
  ///
  /// In en, this message translates to:
  /// **'Qty: {count}'**
  String qtyLabel(int count);

  /// The match's single event:group context, shown once on the match card header (#322, ADR 0001). Both are always present on a real match.
  ///
  /// In en, this message translates to:
  /// **'{event}: {group}'**
  String matchGroupLabel(String event, String group);

  /// Submit button on the offer dialog with the selected item count
  ///
  /// In en, this message translates to:
  /// **'Send Offer ({count} items)'**
  String sendOfferItems(int count);

  /// Empty state for the Match tab
  ///
  /// In en, this message translates to:
  /// **'No pending matches. Keep adding items!'**
  String get noPendingMatches;

  /// Empty state for the Offer Out tab
  ///
  /// In en, this message translates to:
  /// **'No outgoing offers.'**
  String get noOutgoingOffers;

  /// Empty state for the Offer In tab
  ///
  /// In en, this message translates to:
  /// **'No incoming offers.'**
  String get noIncomingOffers;

  /// Empty state for the Active tab
  ///
  /// In en, this message translates to:
  /// **'No active trades.'**
  String get noActiveTrades;

  /// Empty state for the Done tab
  ///
  /// In en, this message translates to:
  /// **'No completed trades yet.'**
  String get noCompletedTrades;

  /// Hint shown on the login screen pointing new users to the how-to guide, which lives behind the Profile tab (available after login)
  ///
  /// In en, this message translates to:
  /// **'The How to Trade guide is in the Profile tab — tap it after logging in to read it.'**
  String get howToHint;

  /// Shown when the virtual Profile tab preview on the login screen is tapped — the tab is not usable until after login
  ///
  /// In en, this message translates to:
  /// **'Available after login'**
  String get howToPreviewTabHint;
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
      <String>['en', 'ja'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ja':
      return AppLocalizationsJa();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
