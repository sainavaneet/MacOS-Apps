import Foundation

/// On-demand DOM helpers for reading the *currently visible* chat list.
///
/// Background polling and `MutationObserver` machinery were removed: they were
/// firing 1.5–2 s per service forever (even when the window was hidden) and
/// the Instagram path produced false-positive notifications whenever the page
/// re-rendered. Detection now lives in `WebController.handleTitleChange` —
/// title-only — and the scraper is only invoked when the user clicks a toast
/// or asks the AI composer for context.
enum ChatScraper {
    static let channelName = "socialHubChat"

    /// Service-specific helper. Returns a JSON string `[{sender, preview, avatar}]`
    /// for unread chats currently visible in the chat list. Called on demand via
    /// `evaluateJavaScript`; never installed as a persistent script.
    static func pollScript(for serviceID: String) -> String? {
        switch serviceID {
        case "whatsapp":  return whatsAppPoll
        case "messenger": return messengerPoll
        case "instagram": return instagramPoll
        case "telegram":  return telegramPoll
        case "snapchat":  return snapchatPoll
        case "tinder":    return tinderPoll
        default:          return nil
        }
    }

    private static let cleanTextHelper = """
    function _shCleanText(node) {
      if (!node) return '';
      try {
        var clone = node.cloneNode(true);
        clone.querySelectorAll(
          '.dialog-subtitle-badge, [class*="badge" i], [class*="Badge" i], ' +
          '[class*="counter" i], [class*="Counter" i], [class*="unread" i], ' +
          '[aria-label*="unread" i]'
        ).forEach(function(b){ b.remove(); });
        return (clone.textContent || '').replace(/\\s+/g, ' ').trim();
      } catch(e) {
        return (node.textContent || '').replace(/\\s+/g, ' ').trim();
      }
    }
    function _shFindAvatar(row) {
      try {
        var imgs = row.querySelectorAll('img[src]');
        for (var i = 0; i < imgs.length; i++) {
          var src = imgs[i].getAttribute('src') || '';
          if (!src || src.indexOf('data:') === 0) continue;
          if (src.length < 12) continue;
          if (/bitmoji|sc-cdn|sc-static|cf-st\\.sc-cdn|pps\\.whatsapp|fbcdn|cdninstagram|tinder|t\\.me|telegram/i.test(src)) {
            return src;
          }
        }
        for (var k = 0; k < imgs.length; k++) {
          var s = imgs[k].getAttribute('src') || '';
          if (!s || s.indexOf('data:') === 0) continue;
          var w = imgs[k].naturalWidth || imgs[k].width || 0;
          if (w >= 24 || s.length > 30) return s;
        }
        var divs = row.querySelectorAll('div, span, a');
        for (var j = 0; j < divs.length; j++) {
          var style = divs[j].getAttribute('style') || '';
          var m = style.match(/url\\(["']?(https?:[^"')]+)["']?\\)/i);
          if (m && m[1]) return m[1];
        }
      } catch(e) {}
      return '';
    }
    """

    // ─────────────────────── WhatsApp ───────────────────────

    private static let whatsAppPoll = cleanTextHelper + """
    (function(){
      var out = {};
      var rows = document.querySelectorAll('div[role="listitem"], div[role="row"]');
      rows.forEach(function(row){
        var hasUnread = !!row.querySelector('[aria-label*="unread message" i], [aria-label*="unread chat" i]');
        if (!hasUnread) {
          var spans = row.querySelectorAll('span');
          for (var i=0; i<spans.length; i++) {
            var s = spans[i];
            if (s.textContent && /^\\d+$/.test(s.textContent.trim())
                && s.offsetWidth > 0 && s.offsetHeight > 0 && s.offsetWidth < 40) { hasUnread = true; break; }
          }
        }
        if (!hasUnread) return;
        var titleEl = row.querySelector('span[title]');
        var sender = titleEl ? (titleEl.getAttribute('title') || titleEl.textContent || '') : '';
        sender = (sender || '').trim();
        if (!sender) return;
        var preview = '';
        var dirs = row.querySelectorAll('span[dir]');
        if (dirs.length) preview = _shCleanText(dirs[dirs.length - 1]);
        var key = sender + '|' + preview;
        out[key] = { sender: sender, preview: preview, avatar: _shFindAvatar(row) };
      });
      return JSON.stringify(Object.values(out));
    })();
    """

    // ─────────────────────── Messenger ──────────────────────

    private static let messengerPoll = cleanTextHelper + """
    (function(){
      var out = {};
      var rows = document.querySelectorAll('a[role="link"][aria-label], div[role="row"], div[role="gridcell"]');
      rows.forEach(function(row){
        var label = row.getAttribute('aria-label') || '';
        var hasUnread = /unread|new message/i.test(label) || !!row.querySelector('[aria-label*="unread" i]');
        if (!hasUnread) return;
        var nameEl = row.querySelector('span[dir="auto"]');
        var sender = nameEl ? _shCleanText(nameEl) : '';
        var preview = '';
        var spans = row.querySelectorAll('span[dir="auto"]');
        if (spans.length > 1) preview = _shCleanText(spans[spans.length - 1]);
        if (!sender) return;
        var key = sender + '|' + preview;
        out[key] = { sender: sender, preview: preview, avatar: _shFindAvatar(row) };
      });
      return JSON.stringify(Object.values(out));
    })();
    """

    // ─────────────────────── Instagram ──────────────────────
    //
    // Stricter than before: drops the "status text matching" heuristic that
    // produced false positives on every DOM reflow. Only fires when the row
    // has a bold sender (Instagram's actual unread marker) OR an explicit
    // unread class/aria-label.

    private static let instagramPoll = cleanTextHelper + """
    (function(){
      var out = {};
      var rows = document.querySelectorAll(
        'a[href^="/direct/t/"], ' +
        'div[role="listbox"] div[role="button"], ' +
        'div[role="list"] > div[role="button"]'
      );
      rows.forEach(function(row){
        var nameEl = row.querySelector('span[dir="auto"]:not([aria-hidden="true"])');
        if (!nameEl) nameEl = row.querySelector('span[dir="auto"]');
        var sender = nameEl ? _shCleanText(nameEl) : '';
        if (!sender) return;
        if (/sent (a|you|an)|reacted|liked|new message/i.test(sender)) {
          var altImg = row.querySelector('img[alt]');
          if (altImg) sender = (altImg.getAttribute('alt') || '')
              .replace(/'s profile picture.*$/i, '').trim();
        }
        sender = (sender || '').trim();
        if (!sender) return;
        if (/^(Messages|Requests|Notes|Stories|Notifications|My notes|Sign Up|Log In)$/i.test(sender)) return;

        var isBold = false;
        if (nameEl) {
          try {
            var weight = parseInt(window.getComputedStyle(nameEl).fontWeight, 10) || 0;
            if (weight >= 600) isBold = true;
          } catch(e) {}
        }
        var hasUnreadAttr = !!row.querySelector(
          '[aria-label*="unread" i], [class*="unread" i]'
        );
        if (!isBold && !hasUnreadAttr) return;

        var preview = '';
        var spans = row.querySelectorAll('span[dir="auto"], span');
        for (var i = spans.length - 1; i >= 0; i--) {
          var t = _shCleanText(spans[i]);
          if (!t || t === sender) continue;
          if (t.length > 200) continue;
          if (/^\\d+[hmdwy]$/.test(t)) continue;
          if (/^Active (now|\\d+[hmdwy] ago)$/i.test(t)) continue;
          preview = t;
          break;
        }
        if (!preview) preview = 'New message';

        var key = sender + '|' + preview;
        out[key] = {
          sender: sender,
          preview: preview,
          avatar: _shFindAvatar(row)
        };
      });
      return JSON.stringify(Object.values(out));
    })();
    """

    // ─────────────────────── Telegram (WebK) ────────────────

    private static let telegramPoll = cleanTextHelper + """
    (function(){
      var out = {};
      var rows = document.querySelectorAll('ul.chatlist li.chatlist-chat, a[data-peer-id], div.ListItem-button');
      rows.forEach(function(row){
        var badge = row.querySelector('.dialog-subtitle-badge.badge-unread, .dialog-subtitle-badge:not(.is-muted), .Badge.unread, .ChatBadge-unread');
        if (!badge) return;
        var titleEl = row.querySelector('.peer-title, .user-title, .dialog-title .peer-title, .title h3');
        var sender = titleEl ? _shCleanText(titleEl) : '';
        if (!sender) return;
        var preview = '';
        var textEl = row.querySelector('.dialog-subtitle-text');
        if (textEl) {
          preview = _shCleanText(textEl);
        } else {
          var sub = row.querySelector('.dialog-subtitle, .ListItem-subtitle, .last-message');
          if (sub) preview = _shCleanText(sub);
        }
        var key = sender + '|' + preview;
        out[key] = { sender: sender, preview: preview, avatar: _shFindAvatar(row) };
      });
      return JSON.stringify(Object.values(out));
    })();
    """

    // ─────────────────────── Snapchat ───────────────────────

    private static let snapchatPoll = cleanTextHelper + """
    (function(){
      var out = {};
      var rows = document.querySelectorAll(
        '[role="row"], [role="listitem"], [role="button"], ' +
        '[data-testid*="feed-item" i], [data-testid*="conversation" i], [data-testid*="chat" i]'
      );
      var seenSenders = {};
      rows.forEach(function(row){
        var rect = row.getBoundingClientRect ? row.getBoundingClientRect() : { height: 0 };
        if (rect.height < 36 || rect.height > 120) return;

        var rowText = (row.textContent || '');
        if (/on mobile/i.test(rowText)) return;
        var statusMatch = rowText.match(/(New Snap|New Chat|Sent you a Snap|Sent you a Chat|Tap to view)/i);
        var hasUnreadClass = !!row.querySelector('[class*="unread" i], [data-testid*="unread" i], [aria-label*="unread" i], [aria-label*="new" i]');
        if (!statusMatch && !hasUnreadClass) return;
        if (!statusMatch && /\\bReceived\\b/i.test(rowText) && !/new|sent you|tap to view/i.test(rowText)) return;

        var sender = '';
        var img = row.querySelector('img[alt]');
        if (img) {
          var alt = (img.getAttribute('alt') || '').trim();
          if (alt && !/^(snap|chat|story|spotlight|memories)$/i.test(alt)) sender = alt;
        }
        if (!sender) {
          var labeled = row.querySelector('[aria-label]:not([aria-label*="unread" i]):not([aria-label*="new" i])');
          if (labeled) {
            var lbl = (labeled.getAttribute('aria-label') || '').trim();
            if (lbl && lbl.length < 60 && !/snap|chat|story/i.test(lbl)) sender = lbl;
          }
        }
        if (!sender) {
          var spans = row.querySelectorAll('span, div');
          for (var i = 0; i < spans.length; i++) {
            var t = _shCleanText(spans[i]);
            if (!t || t.length > 50) continue;
            if (/new snap|sent you|received|tap to view|new chat|just now|ago|min|hour|day|^[0-9hms ]+$/i.test(t)) continue;
            if (/^(snapchat|chat|stories|spotlight|map|memories|friends)$/i.test(t)) continue;
            sender = t;
            break;
          }
        }
        sender = (sender || '').trim();
        if (!sender) return;
        if (seenSenders[sender]) return;
        seenSenders[sender] = true;

        var preview = statusMatch ? statusMatch[1] : 'New activity';
        if (/sent you a snap/i.test(preview)) preview = 'Sent you a Snap';
        else if (/sent you a chat/i.test(preview)) preview = 'Sent you a Chat';
        else if (/new snap/i.test(preview))    preview = 'New Snap';
        else if (/new chat/i.test(preview))    preview = 'New Chat';
        else if (/tap to view/i.test(preview)) preview = 'Tap to view';

        var key = sender + '|' + preview;
        out[key] = { sender: sender, preview: preview, avatar: _shFindAvatar(row) };
      });
      return JSON.stringify(Object.values(out));
    })();
    """

    // ─────────────────────── Tinder ─────────────────────────

    private static let tinderPoll = cleanTextHelper + """
    (function(){
      var out = {};
      var rows = document.querySelectorAll(
        '.messageListItem, ' +
        'a[href^="/app/messages/"], ' +
        'div[role="listitem"]'
      );
      rows.forEach(function(row){
        var unreadEl = row.querySelector(
          '.messageListItem__hasUnread, ' +
          '[class*="hasUnread" i], [class*="unread" i], ' +
          '[data-testid*="unread" i], [class*="badge" i]'
        );
        var rowText = (row.textContent || '').trim();
        var bullet = /^\\s*•/.test(rowText);
        var hasUnread = !!unreadEl || bullet;
        if (!hasUnread) return;

        var nameEl = row.querySelector(
          '.messageListItem__title, [class*="messageListItem__title" i], ' +
          '[class*="title" i] h3, h3, [class*="name" i]'
        );
        var sender = nameEl ? _shCleanText(nameEl) : '';
        if (!sender) {
          var els = row.querySelectorAll('span, div, h2, h3');
          for (var i = 0; i < els.length; i++) {
            var t = _shCleanText(els[i]);
            if (!t) continue;
            if (t.length > 30) continue;
            if (/^\\s*•/.test(t)) continue;
            if (/^(new match|new like|matches|messages|tinder)$/i.test(t)) continue;
            sender = t; break;
          }
        }
        sender = (sender || '').trim();
        if (!sender) return;

        var preview = '';
        var prevEl = row.querySelector(
          '.messageListItem__preview, ' +
          '[class*="messageListItem__preview" i], ' +
          '[class*="preview" i], [class*="lastMessage" i]'
        );
        if (prevEl) preview = _shCleanText(prevEl);
        if (!preview) {
          preview = rowText.replace(sender, '').replace(/^\\s*•\\s*/, '').trim();
          preview = preview.replace(/^You:\\s*/, '');
          if (preview.length > 80) preview = preview.substring(0, 80) + '…';
        }
        if (!preview) preview = 'New match';

        var key = sender + '|' + preview;
        out[key] = { sender: sender, preview: preview, avatar: _shFindAvatar(row) };
      });
      return JSON.stringify(Object.values(out));
    })();
    """
}
