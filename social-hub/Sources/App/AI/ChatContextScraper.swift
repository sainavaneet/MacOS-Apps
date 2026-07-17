import Foundation

/// Per-service JS that extracts the last ~15 messages of the currently
/// OPEN conversation. Returns a JSON string of `{partner, turns}` where
/// each turn has `from` ("me" or "them") and `text`.
enum ChatContextScraper {

    static func script(for serviceID: String) -> String? {
        switch serviceID {
        case "whatsapp":  return whatsApp
        case "telegram":  return telegram
        case "messenger": return messenger
        case "instagram": return instagram
        case "tinder":    return tinder
        default:          return nil
        }
    }

    static let pageTextScript = """
    (function(){
      try {
        var clone = document.body.cloneNode(true);
        clone.querySelectorAll('script, style, noscript').forEach(function(n){ n.remove(); });
        return (clone.innerText || '')
          .replace(/\\n{3,}/g, '\\n\\n')
          .trim()
          .substring(0, 24000);
      } catch(e) { return ''; }
    })();
    """

    // WhatsApp Web — `.message-in`/`.message-out` is the stable hook;
    // if that fails (class obfuscation across releases), fall back to any
    // `[data-id]` container with copyable text + computed alignment.
    private static let whatsApp = """
    (function(){
      try {
        var partnerEl = document.querySelector('header ._amig span') || document.querySelector('span[data-testid="conversation-header-title"]');
        var partner = partnerEl ? (partnerEl.innerText || partnerEl.textContent || '').trim() : '';
        var msgs = document.querySelectorAll('div.message-in, div.message-out');
        if (msgs.length === 0) {
          var candidates = document.querySelectorAll('[data-id]');
          var list = [];
          for (var k = 0; k < candidates.length; k++) {
            var c = candidates[k];
            if (c.querySelector('.copyable-text, .selectable-text, span[dir="auto"]')) list.push(c);
          }
          msgs = list;
        }
        var out = [];
        var start = Math.max(0, msgs.length - 18);
        for (var i = start; i < msgs.length; i++) {
          var m = msgs[i];
          var isMe = m.classList.contains('message-out');
          if (!isMe && !m.classList.contains('message-in')) {
            try {
              var st = window.getComputedStyle(m);
              isMe = (st.justifyContent === 'flex-end') || (st.alignItems === 'flex-end');
            } catch(e) {}
          }
          var t = m.querySelector('.selectable-text span[dir]')
               || m.querySelector('span.selectable-text')
               || m.querySelector('.copyable-text span[dir]')
               || m.querySelector('span[dir="auto"]');
          var text = t ? (t.innerText || t.textContent || '').trim() : '';
          if (!text) continue;
          if (/^\\d{1,2}:\\d{2}\\s*(AM|PM)?$/i.test(text)) continue;
          out.push({ from: isMe ? 'me' : 'them', text: text.substring(0, 400) });
        }
        return JSON.stringify({ partner: partner, turns: out });
      } catch(e) { return JSON.stringify({ partner: '', turns: [] }); }
    })();
    """

    // Telegram WebK — .bubble.is-in / .bubble.is-out
    private static let telegram = """
    (function(){
      try {
        var partnerEl = document.querySelector('.tgme_page_title') || document.querySelector('.TopBar .title .peer-title');
        var partner = partnerEl ? (partnerEl.innerText || partnerEl.textContent || '').trim() : '';
        var msgs = document.querySelectorAll('.bubble.is-in, .bubble.is-out, .Message.message');
        var out = [];
        var start = Math.max(0, msgs.length - 18);
        for (var i = start; i < msgs.length; i++) {
          var m = msgs[i];
          var isMe = m.classList.contains('is-out') || m.classList.contains('own');
          var t = m.querySelector('.message .translatable-message')
               || m.querySelector('.message')
               || m.querySelector('.text-content');
          var text = t ? (t.innerText || t.textContent || '').trim() : '';
          if (text) out.push({ from: isMe ? 'me' : 'them', text: text.substring(0, 400) });
        }
        return JSON.stringify({ partner: partner, turns: out });
      } catch(e) { return JSON.stringify({ partner: '', turns: [] }); }
    })();
    """

    // Messenger — uses role="row" and h4/h5 for author label
    private static let messenger = """
    (function(){
      try {
        var partnerEl = document.querySelector('h1') || document.querySelector('[data-testid="mwThreadlistLabel"]');
        if (!partnerEl) {
          var header = document.querySelector('header, div[role="main"]');
          partnerEl = header ? header.querySelector('h2') : null;
        }
        var partner = partnerEl ? (partnerEl.innerText || partnerEl.textContent || '').trim() : '';
        var rows = document.querySelectorAll('div[role="row"]');
        var out = [];
        var start = Math.max(0, rows.length - 18);
        for (var i = start; i < rows.length; i++) {
          var r = rows[i];
          var inner = r.querySelector('[role="presentation"], [dir="auto"]');
          var text = inner ? (inner.innerText || inner.textContent || '').trim() : '';
          if (!text) continue;
          var st = window.getComputedStyle(r);
          var isMe = (st.alignItems === 'flex-end') || (st.justifyContent === 'flex-end')
                  || !!r.querySelector('[role="presentation"][data-scope="messages_table"][style*="end"]');
          out.push({ from: isMe ? 'me' : 'them', text: text.substring(0, 400) });
        }
        return JSON.stringify({ partner: partner, turns: out });
      } catch(e) { return JSON.stringify({ partner: '', turns: [] }); }
    })();
    """

    // Instagram DM thread — message containers vary; use position heuristic.
    private static let instagram = """
    (function(){
      try {
        var header = document.querySelector('header');
        var partnerEl = (header ? header.querySelector('h1') : null) || (header ? header.querySelector('._aacl') : null);
        var partner = partnerEl ? (partnerEl.innerText || partnerEl.textContent || '').trim() : '';
        var rows = document.querySelectorAll('div[role="listitem"], div[data-scope="messages_table"] div[role="row"]');
        if (rows.length === 0) {
          rows = document.querySelectorAll('div[role="row"]');
        }
        var out = [];
        var start = Math.max(0, rows.length - 18);
        for (var i = start; i < rows.length; i++) {
          var r = rows[i];
          var t = r.querySelector('span[dir="auto"]');
          var text = t ? (t.innerText || t.textContent || '').trim() : '';
          if (!text || text.length < 1) continue;
          var style = window.getComputedStyle(r);
          var isMe = (style.justifyContent === 'flex-end') || (style.alignItems === 'flex-end');
          out.push({ from: isMe ? 'me' : 'them', text: text.substring(0, 400) });
        }
        return JSON.stringify({ partner: partner, turns: out });
      } catch(e) { return JSON.stringify({ partner: '', turns: [] }); }
    })();
    """

    // Tinder — text messages live in a list. Sender side determined by class.
    private static let tinder = """
    (function(){
      try {
        var matches = document.querySelector('.Matches');
        var partnerEl = document.querySelector('.matchInfoName') || (matches ? matches.querySelector('h1') : null);
        var partner = partnerEl ? (partnerEl.innerText || partnerEl.textContent || '').trim() : '';
        var rows = document.querySelectorAll('div[role="listitem"], li[class*="msg"], li[class*="message"]');
        var out = [];
        var start = Math.max(0, rows.length - 18);
        for (var i = start; i < rows.length; i++) {
          var r = rows[i];
          var t = r.querySelector('p, span, div');
          var text = t ? (t.innerText || t.textContent || '').trim() : '';
          if (!text) continue;
          var cls = (r.className || '').toLowerCase();
          var isMe = /\\bme\\b|sent|own|self|right/.test(cls);
          if (!isMe) {
            var st = window.getComputedStyle(r);
            isMe = (st.justifyContent === 'flex-end') || (st.alignItems === 'flex-end');
          }
          out.push({ from: isMe ? 'me' : 'them', text: text.substring(0, 400) });
        }
        return JSON.stringify({ partner: partner, turns: out });
      } catch(e) { return JSON.stringify({ partner: '', turns: [] }); }
    })();
    """
}

struct ChatTurn: Equatable {
    let from: String   // "me" or "them"
    let text: String
}
