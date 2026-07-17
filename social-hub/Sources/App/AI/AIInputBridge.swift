import Foundation

/// JS helpers for reading and writing the focused chat input across services.
/// Handles both <input>/<textarea> and contenteditable divs (WhatsApp,
/// Messenger, Instagram, Telegram all use contenteditable).
enum AIInputBridge {

    static let readScript = """
    (function(){
      function fromActive() {
        var el = document.activeElement;
        if (!el || el === document.body) return null;
        if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') return el.value || '';
        if (el.isContentEditable) return el.innerText || el.textContent || '';
        return null;
      }
      function fromFooter() {
        // Best-effort fallback: find a visible contenteditable that looks
        // like a message-compose box (WhatsApp uses contenteditable=true with
        // role=textbox; Messenger/IG/TG similar).
        var sels = [
          '[contenteditable="true"][role="textbox"]',
          'div[contenteditable="true"][data-tab]',
          '[contenteditable="true"][aria-label*="message" i]',
          '[contenteditable="true"][aria-label*="type" i]',
          'div[contenteditable="true"]',
          'textarea',
          'input[type="text"]'
        ];
        for (var i = 0; i < sels.length; i++) {
          var els = document.querySelectorAll(sels[i]);
          for (var j = 0; j < els.length; j++) {
            var el = els[j];
            if (!el.offsetParent) continue;
            if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') {
              if (el.value !== undefined) return el.value;
            }
            if (el.isContentEditable) {
              return el.innerText || el.textContent || '';
            }
          }
        }
        return '';
      }
      var v = fromActive();
      if (v === null) v = fromFooter();
      return v || '';
    })();
    """

    /// Returns JS that replaces the focused input's text with the given
    /// string. Tries multiple insertion strategies — execCommand, paste event
    /// simulation with DataTransfer, and native setter + input event — so
    /// React-based apps (Messenger/Instagram) and WhatsApp Web both work.
    static func writeScript(_ text: String) -> String {
        let json = (try? JSONSerialization.data(withJSONObject: [text]))
            .flatMap { String(data: $0, encoding: .utf8) }
            ?? "[\"\"]"
        return """
        (function(){
          var arr = \(json);
          var text = arr[0] || '';
          function targetEl() {
            var el = document.activeElement;
            if (el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.isContentEditable)) {
              if (el.offsetParent) return el;
            }
            var sels = [
              '[contenteditable="true"][role="textbox"]',
              'div[contenteditable="true"][data-tab]',
              '[contenteditable="true"][aria-label*="message" i]',
              '[contenteditable="true"][aria-label*="type" i]',
              '[contenteditable="true"][aria-label*="send" i]',
              'div[contenteditable="true"]',
              'textarea[aria-label*="message" i]',
              'textarea',
              'input[type="text"]'
            ];
            for (var i = 0; i < sels.length; i++) {
              var els = document.querySelectorAll(sels[i]);
              for (var j = 0; j < els.length; j++) {
                if (els[j].offsetParent) return els[j];
              }
            }
            return null;
          }
          var el = targetEl();
          if (!el) return false;
          el.focus();
          if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') {
            // Native value setter REPLACES the value (not appends), then
            // a single 'input' event tells React to re-read it.
            try {
              var proto = el.tagName === 'INPUT' ? window.HTMLInputElement.prototype : window.HTMLTextAreaElement.prototype;
              var setter = Object.getOwnPropertyDescriptor(proto, 'value');
              if (setter && setter.set) { setter.set.call(el, text); }
              else { el.value = text; }
              el.dispatchEvent(new Event('input', { bubbles: true }));
              return true;
            } catch(e) {
              el.value = text;
              return true;
            }
          }
          if (el.isContentEditable) {
            // Strategies are MUTUALLY EXCLUSIVE — only fall through if the
            // previous one actually threw. Otherwise we get double inserts
            // when execCommand succeeds and then the paste event re-pastes
            // the same text via the page's own onpaste handler.
            var aThrew = false;
            try {
              // Select everything currently in the box, replace with new text.
              var range = document.createRange();
              range.selectNodeContents(el);
              var sel = window.getSelection();
              sel.removeAllRanges();
              sel.addRange(range);
              document.execCommand('delete', false);
              document.execCommand('insertText', false, text);
              // NOTE: execCommand fires its own native `input` event with
              // inputType=insertText and data=text. Do NOT dispatch a
              // synthetic one as well — React-based apps (WhatsApp etc.)
              // treat both as separate inserts → duplicated content.
            } catch(e) { aThrew = true; }
            if (!aThrew) return true;

            var bThrew = false;
            try {
              var dt = new DataTransfer();
              dt.setData('text/plain', text);
              var ev = new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true });
              el.dispatchEvent(ev);
            } catch(e) { bThrew = true; }
            if (!bThrew) return true;

            try {
              el.textContent = text;
              // Plain bubbling input event (no inputType/data) — just a
              // "value changed, re-read it" signal for React.
              el.dispatchEvent(new Event('input', { bubbles: true }));
              return true;
            } catch(e) { return false; }
          }
          return false;
        })();
        """
    }

    /// Just focuses the chat input (without modifying it) so subsequent paste
    /// commands have a target.
    static let focusScript = """
    (function(){
      function findIt() {
        var sels = [
          '[contenteditable="true"][role="textbox"]',
          'div[contenteditable="true"][data-tab]',
          '[contenteditable="true"][aria-label*="message" i]',
          '[contenteditable="true"]',
          'textarea',
          'input[type="text"]'
        ];
        for (var i = 0; i < sels.length; i++) {
          var els = document.querySelectorAll(sels[i]);
          for (var j = 0; j < els.length; j++) {
            if (els[j].offsetParent) return els[j];
          }
        }
        return null;
      }
      var el = findIt();
      if (el) { el.focus(); return true; }
      return false;
    })();
    """
}
