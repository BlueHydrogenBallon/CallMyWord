import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Share service provider
final shareServiceProvider = Provider<ShareService>((ref) {
  return ShareService();
});

/// Service for sharing invite links
class ShareService {
  static const playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.callmyword';
  static const webPlayUrl = 'https://callmyword.web.app';

  /// Build the invite message with the invite code
  String buildInviteMessage(String inviteCode) {
    return '''Join me on Call My Word!

Use my invite code: $inviteCode

Download: $playStoreUrl
Or play online: $webPlayUrl''';
  }

  /// Build a shareable link with the invite code
  String buildInviteLink(String inviteCode) {
    return '$webPlayUrl/invite?code=$inviteCode';
  }

  /// Copy invite link to clipboard
  Future<void> copyInviteLink(String inviteCode) async {
    final message = buildInviteMessage(inviteCode);
    await Clipboard.setData(ClipboardData(text: message));
  }

  /// Share via platform share sheet (generic share)
  Future<void> shareInvite(String inviteCode) async {
    final message = buildInviteMessage(inviteCode);
    await Share.share(
      message,
      subject: 'Join me on Call My Word!',
    );
  }

  /// Share via email
  Future<bool> shareViaEmail(String inviteCode) async {
    final message = buildInviteMessage(inviteCode);
    final subject = Uri.encodeComponent('Join me on Call My Word!');
    final body = Uri.encodeComponent(message);
    final emailUri = Uri.parse('mailto:?subject=$subject&body=$body');

    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
      return true;
    }
    return false;
  }

  /// Share via Facebook Messenger
  Future<bool> shareViaMessenger(String inviteCode) async {
    final link = buildInviteLink(inviteCode);
    final encodedLink = Uri.encodeComponent(link);

    // Try Messenger app deep link first
    final messengerUri = Uri.parse('fb-messenger://share?link=$encodedLink');
    if (await canLaunchUrl(messengerUri)) {
      await launchUrl(messengerUri);
      return true;
    }

    // Fallback to web-based Messenger share
    final webMessengerUri = Uri.parse(
        'https://www.facebook.com/dialog/send?link=$encodedLink&app_id=YOUR_FB_APP_ID&redirect_uri=$encodedLink');

    if (await canLaunchUrl(webMessengerUri)) {
      await launchUrl(webMessengerUri, mode: LaunchMode.externalApplication);
      return true;
    }

    return false;
  }

  /// Open a URL in external browser
  Future<bool> openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return true;
    }
    return false;
  }
}
