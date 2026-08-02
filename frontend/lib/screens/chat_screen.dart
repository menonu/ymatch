import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import '../providers/providers.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../utils/system_message.dart';
import 'map_picker_screen.dart';
import 'package:latlong2/latlong.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final int matchId;

  const ChatScreen({super.key, required this.matchId});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _messageController = TextEditingController();
  Timer? _pollingTimer;

  /// #535: list messages stamps the server read watermark; refresh match /
  /// notification badges once so the card clears when the user returns.
  bool _refreshedUnreadBadges = false;

  @override
  void initState() {
    super.initState();
    // Polling stays on the screen (not ChatController): a singleton
    // controller has no per-match lifecycle, while this widget already
    // starts the timer in initState and cancels it in dispose when the
    // route is popped. Moving it would require a family/autoDispose
    // notifier for little gain.
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      ref.invalidate(messagesProvider(widget.matchId));
    });
  }

  void _maybeRefreshUnreadBadges(User user) {
    if (_refreshedUnreadBadges) return;
    _refreshedUnreadBadges = true;
    // Defer past the current build; GET messages already marked read.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.invalidate(matchesProvider(user.id));
      ref.invalidate(notificationCountsProvider(user.id));
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _pollingTimer?.cancel();
    super.dispose();
  }

  // #245: thin wrapper — body shape + invalidation live on ChatController.
  // #498: error feedback is driven by the returned Future so
  // generation-discarded concurrent failures still surface a SnackBar.
  Future<void> _sendMessage(User currentUser) async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();

    try {
      await ref
          .read(chatControllerProvider.notifier)
          .sendMessage(widget.matchId, currentUser.id, text);
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.failedToSend(e.toString()))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (user == null)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final messagesAsync = ref.watch(messagesProvider(widget.matchId));
    final l10n = AppLocalizations.of(context)!;

    // #535: after the thread loads (server mark-as-read), refresh badges once.
    if (messagesAsync.hasValue) {
      _maybeRefreshUnreadBadges(user);
    }

    // #498: send-error SnackBars come from the Future catch in _sendMessage
    // (not ref.listen on the shared slot) so concurrent discarded failures
    // still surface feedback.

    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.white),
      body: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              data: (messages) {
                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      l10n.noMessagesYet,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  );
                }
                return ListView.builder(
                  reverse:
                      false, // In a real app we'd likely want a true bottom-up list, but standard top-down for now.
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    // ADR 0008 / 0010: SYSTEM cancel rows are centered notices
                    // (not chat bubbles). Content is a stable reason code;
                    // display copy is localized (#462).
                    if (msg.hasMessageType() && msg.messageType == 'SYSTEM') {
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 8,
                        ),
                        child: Text(
                          localizeSystemMessage(l10n, msg.content),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      );
                    }
                    final isMe = msg.senderId == user.id;

                    return Align(
                      alignment: isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isMe
                              ? AppTheme.primaryColor
                              : Colors.grey[200],
                          borderRadius: BorderRadius.circular(16).copyWith(
                            bottomRight: isMe ? const Radius.circular(0) : null,
                            bottomLeft: !isMe ? const Radius.circular(0) : null,
                          ),
                        ),
                        child: _buildMessageContent(msg.content, isMe, l10n),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) =>
                  Center(child: Text(l10n.errorPrefix(e.toString()))),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey[300]!)),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.add_location_alt_outlined),
                    color: Colors.grey[600],
                    onPressed: () async {
                      final LatLng? pickedLocation = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const MapPickerScreen(),
                        ),
                      );
                      if (pickedLocation != null) {
                        // Create a Google Maps URL for universality when clicking
                        final mapsUrl =
                            'https://www.google.com/maps/search/?api=1&query=${pickedLocation.latitude},${pickedLocation.longitude}';
                        _messageController.text = mapsUrl;
                        _sendMessage(user);
                      }
                    },
                  ),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: l10n.typeMessage,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(user),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send),
                    color: AppTheme.primaryColor,
                    onPressed: () => _sendMessage(user),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageContent(String text, bool isMe, AppLocalizations l10n) {
    final urlRegExp = RegExp(r'(https?://[^\s]+)');
    final matches = urlRegExp.allMatches(text);

    if (matches.isEmpty) {
      return Text(
        text,
        style: TextStyle(color: isMe ? Colors.white : Colors.black87),
      );
    }

    List<Widget> children = [];
    int lastMatchEnd = 0;

    for (final match in matches) {
      final String beforeMatch = text.substring(lastMatchEnd, match.start);
      if (beforeMatch.isNotEmpty) {
        children.add(
          Text(
            beforeMatch,
            style: TextStyle(color: isMe ? Colors.white : Colors.black87),
          ),
        );
      }

      final String url = match.group(0)!;
      final bool isMapUrl =
          url.contains('maps.app.goo.gl') ||
          url.contains('google.com/maps') ||
          url.contains('maps.apple.com');

      children.add(
        GestureDetector(
          onTap: () async {
            final uri = Uri.parse(url);
            try {
              // #266: surface failure when the OS cannot open the URL.
              final ok =
                  await canLaunchUrl(uri) &&
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
              if (!ok && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.errorPrefix('Could not open link')),
                  ),
                );
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.errorPrefix(e.toString()))),
                );
              }
            }
          },
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isMe
                  ? Colors.white.withValues(alpha: 0.2)
                  : AppTheme.primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isMe
                    ? Colors.white54
                    : AppTheme.primaryColor.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isMapUrl ? Icons.place : Icons.link,
                  size: 16,
                  color: isMe ? Colors.white : AppTheme.primaryColor,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    isMapUrl ? l10n.openInMaps : l10n.openLink,
                    style: TextStyle(
                      color: isMe ? Colors.white : AppTheme.primaryColor,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      lastMatchEnd = match.end;
    }

    final String afterLastMatch = text.substring(lastMatchEnd);
    if (afterLastMatch.isNotEmpty) {
      children.add(
        Text(
          afterLastMatch,
          style: TextStyle(color: isMe ? Colors.white : Colors.black87),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}
