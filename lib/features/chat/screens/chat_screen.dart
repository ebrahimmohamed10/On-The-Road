import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_strings.dart';
import '../services/chat_service.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String bookingId;
  final Map<String, dynamic>? extra;

  const ChatScreen({
    super.key,
    required this.bookingId,
    this.extra,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  RealtimeChannel? _realtimeChannel;

  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    try {
      final msgs = await ref.read(chatServiceProvider).getMessages(widget.bookingId);
      if (!mounted) return;
      setState(() {
        _messages = msgs;
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  void _subscribeRealtime() {
    _realtimeChannel = ref.read(chatServiceProvider).subscribeToMessages(
      bookingId: widget.bookingId,
      onNewMessage: (newMsg) {
        if (!mounted) return;
        final currentUserId = ref.read(chatServiceProvider).currentUser?.id;
        // Avoid duplicate if sent by current user and already added optimistically
        final exists = _messages.any((m) =>
            m['id'] != null && m['id'].toString() == newMsg['id']?.toString());
        if (!exists) {
          setState(() {
            _messages.add(newMsg);
          });
          _scrollToBottom();
        }
      },
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage([String? textToSend]) async {
    final text = (textToSend ?? _messageController.text).trim();
    if (text.isEmpty || _isSending) return;

    if (textToSend == null) {
      _messageController.clear();
    }

    final user = ref.read(chatServiceProvider).currentUser;
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';

    // Optimistic UI insert
    final optimisticMsg = {
      'id': tempId,
      'booking_id': widget.bookingId,
      'sender_id': user?.id,
      'content': text,
      'created_at': DateTime.now().toIso8601String(),
    };

    setState(() {
      _messages.add(optimisticMsg);
      _isSending = true;
    });
    _scrollToBottom();

    try {
      final sent = await ref.read(chatServiceProvider).sendMessage(
            bookingId: widget.bookingId,
            content: text,
          );
      if (!mounted) return;
      setState(() {
        _isSending = false;
        if (sent != null && sent['id'] != null) {
          final idx = _messages.indexWhere((m) => m['id'] == tempId);
          if (idx != -1) {
            _messages[idx] = sent;
          }
        }
      });
      // Invalidate conversation list so last message preview updates
      ref.invalidate(conversationsProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().contains('Messaging is available only for confirmed')
                ? AppStrings.tr(
                    context,
                    ar: 'المحادثة متاحة فقط بعد تأكيد الحجز من السائق.',
                    en: 'Messaging is available once the booking is confirmed.',
                  )
                : AppStrings.messageError(context),
          ),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _formatMsgTime(BuildContext context, dynamic timestamp) {
    if (timestamp == null) return '';
    try {
      final dt = DateTime.parse(timestamp.toString()).toLocal();
      final isAr = AppStrings.isArabic(context);
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final period = isAr ? (dt.hour >= 12 ? 'م' : 'ص') : (dt.hour >= 12 ? 'PM' : 'AM');
      final minute = dt.minute.toString().padLeft(2, '0');
      return '$hour:$minute $period';
    } catch (_) {
      return '';
    }
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _formatDateHeader(BuildContext context, DateTime dt) {
    final now = DateTime.now();
    final isAr = AppStrings.isArabic(context);
    if (_isSameDay(dt, now)) return AppStrings.todayLabel(context);
    if (_isSameDay(dt, now.subtract(const Duration(days: 1)))) {
      return AppStrings.yesterdayLabel(context);
    }
    final arMonths = [
      'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
    ];
    final enMonths = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final month = isAr ? arMonths[dt.month - 1] : enMonths[dt.month - 1];
    return '${dt.day} $month';
  }

  void _showPhoneCallSheet(BuildContext context, String name, String? phone) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              phone ?? '+20 101 234 5678',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Color(0xFFF59E0B),
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.phone_rounded),
              label: Text(AppStrings.callDriver(context)),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final user = ref.read(chatServiceProvider).currentUser;

    final driverName = widget.extra?['driverName'] ??
        (AppStrings.isArabic(context) ? 'السائق' : 'Driver');
    final driverInitials = widget.extra?['driverInitials'] ??
        (driverName.isNotEmpty ? driverName.substring(0, 1) : '?');
    final route = widget.extra?['route'] ?? '';
    final phone = widget.extra?['phone'];

    final quickReplies = [
      AppStrings.quickReplyOnWay(context),
      AppStrings.quickReplyArrived(context),
      AppStrings.quickReplyDelayed(context),
      AppStrings.quickReplyThanks(context),
    ];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: const Color(0xFFF59E0B).withValues(alpha: 0.15),
              child: Text(
                driverInitials,
                style: const TextStyle(
                  color: Color(0xFFD97706),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    driverName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (route.isNotEmpty)
                    Text(
                      route,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.hintColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone_outlined, size: 22),
            onPressed: () => _showPhoneCallSheet(context, driverName, phone),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ─── Safety Notice Banner ───────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFFEF3C7).withValues(alpha: 0.5),
              child: Row(
                children: [
                  const Icon(
                    Icons.shield_outlined,
                    size: 16,
                    color: Color(0xFFD97706),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      AppStrings.chatTripNotice(context),
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ─── Messages List ──────────────────────────────────
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  size: 48,
                                  color: theme.hintColor.withValues(alpha: 0.4),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  AppStrings.tr(
                                    context,
                                    ar: 'لا توجد رسائل بعد',
                                    en: 'No messages yet',
                                  ),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: theme.hintColor,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  AppStrings.tr(
                                    context,
                                    ar: 'أرسل رسالة للسائق للتنسيق حول نقطة وموعد التجمع.',
                                    en: 'Send a message to coordinate pickup location and time.',
                                  ),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: theme.hintColor,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final msg = _messages[index];
                            final isMe = user != null && msg['sender_id'] == user.id;

                            // Date separator check
                            bool showDateHeader = false;
                            DateTime? currentMsgDate;
                            try {
                              currentMsgDate = DateTime.parse(msg['created_at'].toString()).toLocal();
                              if (index == 0) {
                                showDateHeader = true;
                              } else {
                                final prevMsg = _messages[index - 1];
                                final prevDate = DateTime.parse(prevMsg['created_at'].toString()).toLocal();
                                showDateHeader = !_isSameDay(currentMsgDate, prevDate);
                              }
                            } catch (_) {}

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (showDateHeader && currentMsgDate != null)
                                  Center(
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(vertical: 12),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: theme.dividerColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        _formatDateHeader(context, currentMsgDate),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: theme.hintColor,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                _buildMessageBubble(
                                  context: context,
                                  content: msg['content']?.toString() ?? '',
                                  timeStr: _formatMsgTime(context, msg['created_at']),
                                  isMe: isMe,
                                  theme: theme,
                                  isDark: isDark,
                                ),
                              ],
                            );
                          },
                        ),
            ),

            // ─── Quick Replies Chips ────────────────────────────
            SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: quickReplies.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final reply = quickReplies[index];
                  return ActionChip(
                    label: Text(
                      reply,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    backgroundColor: theme.colorScheme.surface,
                    side: BorderSide(
                      color: theme.dividerColor.withValues(alpha: 0.2),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    onPressed: () => _sendMessage(reply),
                  );
                },
              ),
            ),

            const SizedBox(height: 6),

            // ─── Input Bar ──────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color: theme.dividerColor.withValues(alpha: 0.12),
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: TextField(
                        controller: _messageController,
                        maxLines: 4,
                        minLines: 1,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        decoration: InputDecoration(
                          hintText: AppStrings.typeMessageHint(context),
                          hintStyle: TextStyle(
                            fontSize: 13,
                            color: theme.hintColor,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF0F172A),
                    ),
                    child: IconButton(
                      icon: _isSending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.send_rounded,
                              color: Color(0xFFF59E0B),
                              size: 20,
                            ),
                      onPressed: _isSending ? null : () => _sendMessage(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble({
    required BuildContext context,
    required String content,
    required String timeStr,
    required bool isMe,
    required ThemeData theme,
    required bool isDark,
  }) {
    return Align(
      alignment: isMe ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe
              ? (isDark ? const Color(0xFF2C2411) : const Color(0xFFFEF3C7))
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          border: Border.all(
            color: isMe
                ? const Color(0xFFF59E0B).withValues(alpha: 0.35)
                : theme.dividerColor.withValues(alpha: 0.15),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              content,
              style: TextStyle(
                fontSize: 14,
                color: isMe
                    ? (isDark ? const Color(0xFFFEF3C7) : const Color(0xFF78350F))
                    : theme.textTheme.bodyMedium?.color,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 10,
                    color: isMe
                        ? (isDark ? const Color(0xFFFDE68A).withValues(alpha: 0.7) : const Color(0xFF92400E).withValues(alpha: 0.7))
                        : theme.hintColor,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.done_all_rounded,
                    size: 13,
                    color: isDark ? const Color(0xFFFDE68A) : const Color(0xFFD97706),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
