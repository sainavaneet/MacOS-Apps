import Foundation

enum ToolsBridge {
    static let channelName = "socialHubTools"

    /// Tinder auto-swipe — runs entirely inside our WKWebView, posts progress
    /// back via the `socialHubTools` channel. Designed for *responsive stop*:
    /// every delay polls the `running` flag every 30 ms and aborts early.
    static let tinderAutoSwipe = """
    (function(){
      if (window.__shAutoSwipe) { return; }

      function post(event, extra) {
        try {
          var msg = { event: event };
          if (extra) { for (var k in extra) msg[k] = extra[k]; }
          window.webkit.messageHandlers.socialHubTools.postMessage(msg);
        } catch(e) {}
      }
      function log(message) {
        post('log', { message: String(message) });
        try { console.log('[AutoSwipe]', message); } catch(e) {}
      }
      function visible(el) {
        if (!el) return false;
        if (el.offsetParent === null) return false;
        var r = el.getBoundingClientRect();
        return r.width > 0 && r.height > 0;
      }
      function findLikeButton() {
        var sels = [
          'button[data-testid="gamepad-like-button"]',
          'button[data-testid="gamepad-buttons-button-like"]',
          'button[aria-label="Like"]',
          'button[aria-label*="Like" i]',
          'button.gamepad-button-like',
          'div[role="button"][aria-label*="Like" i]'
        ];
        for (var i=0; i<sels.length; i++) {
          var nodes = document.querySelectorAll(sels[i]);
          for (var j=0; j<nodes.length; j++) {
            if (visible(nodes[j])) return nodes[j];
          }
        }
        var gamepad = document.querySelector('div[class*="gamepad"]');
        if (gamepad) {
          var btns = gamepad.querySelectorAll('button');
          for (var k=0; k<btns.length; k++) {
            var label = (btns[k].getAttribute('aria-label') || '').toLowerCase();
            if (label.indexOf('like') >= 0 && visible(btns[k])) return btns[k];
          }
        }
        return null;
      }
      function findCard() {
        var sels = [
          'div[data-testid="rec-card"]',
          'div[class*="recsCardboard__cards"]',
          'div[class*="recsCardboard__card"]',
          'main div[class*="recCard"]',
          'div[class*="profileCard"]'
        ];
        for (var i=0; i<sels.length; i++) {
          var el = document.querySelector(sels[i]);
          if (el && visible(el)) return true;
        }
        return !!findLikeButton();
      }
      function realClick(el) {
        try {
          var rect = el.getBoundingClientRect();
          var x = rect.left + rect.width / 2;
          var y = rect.top + rect.height / 2;
          ['pointerdown','mousedown','pointerup','mouseup','click'].forEach(function(type){
            try {
              var Ctor = type.indexOf('pointer') === 0 ? PointerEvent : MouseEvent;
              var ev = new Ctor(type, {
                view: window, bubbles: true, cancelable: true, composed: true,
                clientX: x, clientY: y, button: 0, buttons: 1, pointerType: 'mouse'
              });
              el.dispatchEvent(ev);
            } catch(e) {
              try { el.dispatchEvent(new MouseEvent(type === 'pointerdown' ? 'mousedown' : (type === 'pointerup' ? 'mouseup' : type),
                { view: window, bubbles: true, cancelable: true, clientX: x, clientY: y })); } catch(e2) {}
            }
          });
          return true;
        } catch(e) {
          try { el.click(); return true; } catch(e2) { return false; }
        }
      }
      function pressArrowRight() {
        try {
          var targets = [document, document.body];
          if (document.activeElement) targets.push(document.activeElement);
          ['keydown','keypress','keyup'].forEach(function(type){
            targets.forEach(function(t){
              if (!t || !t.dispatchEvent) return;
              try {
                t.dispatchEvent(new KeyboardEvent(type, {
                  key: 'ArrowRight', code: 'ArrowRight',
                  keyCode: 39, which: 39, bubbles: true, cancelable: true
                }));
              } catch(e) {}
            });
          });
          return true;
        } catch(e) { return false; }
      }
      function dismissPopups() {
        var sels = [
          'button[aria-label="Back to Tinder"]',
          'button[data-testid="itsAMatch-keepSwiping"]',
          'div[class*="itsAMatch"] button[class*="keepSwiping"]',
          'button[aria-label="Close"]',
          'button[title="Close"]'
        ];
        sels.forEach(function(sel){
          document.querySelectorAll(sel).forEach(function(b){
            if (visible(b)) { try { b.click(); } catch(e) {} }
          });
        });
      }

      window.__shAutoSwipe = {
        running: false,
        swiped: 0,
        noCard: 0,
        speed: 1.0,
        BASE_MIN: 700,
        BASE_MAX: 2800,
        THINKING_CHANCE: 0.12,   // 12% chance of an extra-long pause
        THINKING_MULT: 2.5,
        NO_CARD_RETRY: 1800,
        MAX_NO_CARD: 6,

        setSpeed: function(s) {
          var n = Number(s);
          if (!isFinite(n) || n <= 0) return;
          this.speed = Math.max(0.1, Math.min(25, n));
          log('Speed = ' + this.speed + 'x');
        },

        start: function() {
          if (this.running) { log('Already running'); return; }
          this.running = true;
          this.swiped = 0;
          this.noCard = 0;
          log('Starting on ' + location.pathname);
          if (location.pathname.indexOf('/app/recs') < 0) {
            log('Navigating to /app/recs');
            try {
              window.history.pushState({}, '', '/app/recs');
              window.dispatchEvent(new PopStateEvent('popstate'));
            } catch(e) { location.href = 'https://tinder.com/app/recs'; }
            var self = this;
            setTimeout(function(){ self._begin(); }, 1500);
          } else {
            this._begin();
          }
        },

        _begin: function() {
          post('started');
          var like = findLikeButton();
          log(like ? 'Found Like button' : 'Like button not visible yet — will retry');
          this._loop();
        },

        stop: function() {
          if (!this.running) return;
          this.running = false;
          log('Stop requested');
          post('stopped', { swiped: this.swiped });
        },

        // Cancellable delay — polls running flag every 30 ms.
        _delay: function(ms) {
          var self = this;
          return new Promise(function(resolve){
            var elapsed = 0;
            var STEP = 30;
            var timer = setInterval(function(){
              elapsed += STEP;
              if (!self.running || elapsed >= ms) {
                clearInterval(timer);
                resolve();
              }
            }, STEP);
          });
        },

        _loop: async function() {
          var self = this;
          while (self.running) {
            dismissPopups();
            await self._delay(100);
            if (!self.running) break;

            if (!findCard()) {
              self.noCard++;
              post('no-card', { noCard: self.noCard });
              if (self.noCard >= self.MAX_NO_CARD) {
                self.running = false;
                post('limit-hit', { swiped: self.swiped });
                return;
              }
              await self._delay(self.NO_CARD_RETRY);
              continue;
            }
            self.noCard = 0;

            var like = findLikeButton();
            var ok = false;
            if (like) ok = realClick(like);
            if (!ok) {
              if (pressArrowRight()) { ok = true; }
            }
            if (ok) {
              self.swiped++;
              post('swipe', { count: self.swiped });
            } else {
              log('Swipe attempt failed');
              await self._delay(500);
            }
            if (!self.running) break;
            // Random per-swipe delay with occasional "thinking pauses"
            // so the rhythm doesn't feel mechanical.
            var base = self.BASE_MIN + Math.random() * (self.BASE_MAX - self.BASE_MIN);
            if (Math.random() < self.THINKING_CHANCE) base *= self.THINKING_MULT;
            var jitter = Math.max(40, base / self.speed);
            await self._delay(jitter);
          }
          post('stopped', { swiped: self.swiped });
        }
      };
      log('Auto-swipe ready');
    })();
    """

    static let tinderAutoSwipeStart = "window.__shAutoSwipe && window.__shAutoSwipe.start();"
    static let tinderAutoSwipeStop  = "window.__shAutoSwipe && window.__shAutoSwipe.stop();"

    static func tinderAutoSwipeSetSpeed(_ speed: Double) -> String {
        "window.__shAutoSwipe && window.__shAutoSwipe.setSpeed(\(speed));"
    }
}
