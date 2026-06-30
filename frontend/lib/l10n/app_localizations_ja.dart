// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appName => 'ymatch';

  @override
  String get cancel => 'キャンセル';

  @override
  String get delete => '削除';

  @override
  String get save => '保存';

  @override
  String get create => '作成';

  @override
  String get set => '設定';

  @override
  String get remove => '削除';

  @override
  String get retry => '再試行';

  @override
  String get refresh => '更新';

  @override
  String get confirm => '確認';

  @override
  String get masterKeyUuid => 'マスターキー (UUID)';

  @override
  String get unknown => '不明';

  @override
  String errorPrefix(String error) {
    return 'エラー: $error';
  }

  @override
  String get loginTagline => 'グッズをスムーズに取引。';

  @override
  String get loginBackendErrorTitle => 'バックエンドに接続できません';

  @override
  String get loginBackendErrorBody =>
      'サービスが一時停止中の可能性があります。\nしばらく経ってから再試行してください。';

  @override
  String get loggingIn => 'ログイン中...';

  @override
  String get restoreAccount => 'アカウントを復元';

  @override
  String get startAsNewUser => '新規ユーザーとして開始';

  @override
  String get restoreExistingAccount => '既存のアカウントを復元';

  @override
  String get navItems => 'アイテム';

  @override
  String get navMatches => 'マッチ';

  @override
  String get navProfile => 'プロフィール';

  @override
  String get navAdmin => '管理';

  @override
  String get backendUnreachableBanner => 'バックエンドサービスに接続できません';

  @override
  String get searchEventsHint => 'イベントやグループを検索...';

  @override
  String get sortEvents => 'イベントを並べ替え';

  @override
  String get sortNewestFirst => '新着順';

  @override
  String get sortMostPopular => '人気順';

  @override
  String get sortAlphabetical => 'アルファベット順';

  @override
  String get newEvent => '新規イベント';

  @override
  String get filterAllEvents => 'すべてのイベント';

  @override
  String get filterFavorites => 'お気に入り';

  @override
  String get filterMyItems => 'マイアイテム';

  @override
  String get noEventsMatchFilter => 'このフィルターに一致するイベントはありません。';

  @override
  String tradersCount(int count) {
    return '$count 人のトレーダー';
  }

  @override
  String viewsCount(int count) {
    return '$count 回閲覧';
  }

  @override
  String get draftBadge => '下書き';

  @override
  String get unknownDate => '日付不明';

  @override
  String get invalidDate => '無効な日付';

  @override
  String get editName => '名前を編集';

  @override
  String get editEventName => 'イベント名を編集';

  @override
  String get eventNameHint => 'イベント名';

  @override
  String get deleteEvent => 'イベントを削除';

  @override
  String deleteEventConfirm(String name) {
    return '「$name」を削除してもよろしいですか？';
  }

  @override
  String get noEventsFound => 'イベントが見つかりません';

  @override
  String get createEventPrompt => '取引を始めるにはイベントを作成してください。';

  @override
  String get createEvent => 'イベントを作成';

  @override
  String get eventNameLabel => 'イベント名';

  @override
  String newEventNameHint(int number) {
    return 'イベント $number';
  }

  @override
  String favPrefix(String name) {
    return 'お気に入り: $name';
  }

  @override
  String get groupFallback => 'グループ';

  @override
  String groupChipLabel(String event, String group) {
    return '$event: $group';
  }

  @override
  String get username => 'ユーザー名';

  @override
  String get editUsername => 'ユーザー名を編集';

  @override
  String get usernameUpdated => 'ユーザー名を更新しました';

  @override
  String failedToUpdateUsername(String error) {
    return 'ユーザー名の更新に失敗しました: $error';
  }

  @override
  String get masterKeyCopied => 'マスターキーをクリップボードにコピーしました';

  @override
  String get saveKeyWarning => 'このキーを保存しておくと、別のデバイスでアカウントを復元できます！';

  @override
  String get howToTrade => '取引のやり方';

  @override
  String get tradeStep1 => 'アイテムタブを開き、あなたのイベントを見つけます。';

  @override
  String get tradeStep2 =>
      '+ と - を使って、交換したいアイテムの数を入力します。求 / 譲の数に応じて、アイテムグループ内で交換のマッチングが行われます。';

  @override
  String get tradeStep3 => 'マッチを開き、取引したい相手を確認します。';

  @override
  String get logOut => 'ログアウト';

  @override
  String revisionInfo(String frontend, String backend) {
    return 'フロントエンド: $frontend  /  バックエンド: $backend';
  }

  @override
  String get selectImageSource => '画像の選択元';

  @override
  String get gallery => 'ギャラリー';

  @override
  String get camera => 'カメラ';

  @override
  String failedToPickImage(String error) {
    return '画像の取得に失敗しました: $error';
  }

  @override
  String get selectGroupFirst => 'まずアイテムグループを選択または作成してください。';

  @override
  String addedSuccessfully(String name) {
    return '「$name」を追加しました。';
  }

  @override
  String failedToAdd(String name, String error) {
    return '「$name」の追加に失敗しました: $error';
  }

  @override
  String failedToUpdateItem(String name, String error) {
    return '「$name」の更新に失敗しました: $error';
  }

  @override
  String get selectGroup => 'グループを選択';

  @override
  String get newGroup => '新規グループ';

  @override
  String get itemName => 'アイテム名';

  @override
  String get itemNameHint => '例: レアホロカード #1';

  @override
  String get photo => '写真';

  @override
  String get changeImage => '画像を変更';

  @override
  String get chooseImage => '画像を選択';

  @override
  String get adding => '追加中...';

  @override
  String get addItem => 'アイテムを追加';

  @override
  String existingItemsInGroup(String group) {
    return '「$group」内の既存アイテム';
  }

  @override
  String get uncategorized => '未分類';

  @override
  String get noItemsInGroup => 'このグループにはまだアイテムがありません。';

  @override
  String get newGroupName => '新しいグループ名';

  @override
  String get newGroupHint => '例: キーホルダー';

  @override
  String failedToSend(String error) {
    return '送信に失敗しました: $error';
  }

  @override
  String get noMessagesYet => 'まだメッセージがありません。挨拶してみましょう！';

  @override
  String get typeMessage => 'メッセージを入力...';

  @override
  String get messageAction => 'メッセージ';

  @override
  String get openInMaps => 'マップで開く';

  @override
  String get openLink => 'リンクを開く';

  @override
  String get have => '所持';

  @override
  String get want => '求';

  @override
  String get trade => '譲';

  @override
  String get haveShort => '所';

  @override
  String get wantShort => '求';

  @override
  String get tradeShort => '譲';

  @override
  String get merchFilterAll => 'すべて';

  @override
  String get merchFilterMissing => '未所持';

  @override
  String get invModeJustHave => '所持のみ';

  @override
  String get invModeWantTrade => '求・譲';

  @override
  String get invModeAll => 'すべて';

  @override
  String get addMerch => 'グッズを追加';

  @override
  String get otherItems => 'その他のアイテム';

  @override
  String get searchItemsHint => 'アイテムを検索...';

  @override
  String get showControls => '表示設定';

  @override
  String get changeViewMode => '表示切替';

  @override
  String get detailedView => '詳細表示';

  @override
  String get gridView => 'グリッド表示';

  @override
  String get compactList => 'リスト表示';

  @override
  String addedToWantPartial(int added, int failed) {
    return '求に$added件追加、$failed件は失敗';
  }

  @override
  String addedMissingToWant(int count) {
    return '不足$count件を求に追加';
  }

  @override
  String get couldNotAddToWant => '一部のアイテムを求に追加できませんでした';

  @override
  String get noMissingItems => '不足アイテムはありません';

  @override
  String get wantAllMissing => '不足をすべて求に追加';

  @override
  String get jumpToGroup => 'グループにジャンプ';

  @override
  String get noItemsMatchFilter => 'このフィルターに一致するアイテムはありません。';

  @override
  String get youCreatedThisItem => 'あなたが作成したアイテム';

  @override
  String get editItem => 'アイテムを編集';

  @override
  String get editItemName => 'アイテム名を編集';

  @override
  String get editItemNameHint => 'アイテム名';

  @override
  String get deleteItem => 'アイテムを削除';

  @override
  String get noMerchandiseYet => 'グッズがまだありません';

  @override
  String get buildInventoryPrompt => 'アイテムを追加して在庫を作り始めましょう。';

  @override
  String get trades => '取引';

  @override
  String get tabMatch => 'マッチ';

  @override
  String get tabOfferOut => 'オファー送信';

  @override
  String get tabOfferIn => 'オファー受信';

  @override
  String get tabActive => '進行中';

  @override
  String get tabDone => '完了';

  @override
  String get unknownUser => '不明';

  @override
  String get statusPending => '保留中';

  @override
  String get statusOffered => 'オファー中';

  @override
  String get statusAccepted => '承認済';

  @override
  String get statusCompleted => '完了';

  @override
  String get youGive => 'あなたが渡すもの:';

  @override
  String get youReceive => 'あなたが受け取るもの:';

  @override
  String get giveLabel => '渡す:';

  @override
  String get receiveLabel => '受け取る:';

  @override
  String get reject => '拒否';

  @override
  String get makeOffer => 'オファーを作成';

  @override
  String get accept => '承認';

  @override
  String get cancelOffer => 'オファーを取り消す';

  @override
  String get waitingForResponse => '返信待ち...';

  @override
  String get markComplete => '完了にする';

  @override
  String get updateInventory => '在庫を更新';

  @override
  String get inventoryUpdated => '在庫更新済';

  @override
  String get inventoryUpdatedSnack => '在庫を更新しました！';

  @override
  String get makeTradeOffer => '取引オファーを作成';

  @override
  String get itemsYouGive => '渡すアイテム:';

  @override
  String get itemsYouReceive => '受け取るアイテム:';

  @override
  String get counterOffer => '逆オファー';

  @override
  String get balanced => '均衡';

  @override
  String get unbalanced => '不均衡';

  @override
  String get acceptBalanceHint => '承諾には均衡したオファーが必要です';

  @override
  String balanceSummary(int give, int recv) {
    return '渡す $give / 受取 $recv';
  }

  @override
  String get balanceExplanation => '渡す数と受け取る数が釣り合っていれば、取引できます。';

  @override
  String qtyLabel(int count) {
    return '数量: $count';
  }

  @override
  String itemContext(String event, String group) {
    return '$event: $group';
  }

  @override
  String sendOfferItems(int count) {
    return 'オファーを送信（$count件）';
  }

  @override
  String get noPendingMatches => '保留中のマッチはありません。アイテムを追加しましょう！';

  @override
  String get noOutgoingOffers => '送信中のオファーはありません。';

  @override
  String get noIncomingOffers => '受信したオファーはありません。';

  @override
  String get noActiveTrades => '進行中の取引はありません。';

  @override
  String get noCompletedTrades => '完了した取引はまだありません。';
}
