import Foundation

/// JS injected into every webview to detect when a `<video>` or `<audio>`
/// element starts/stops playing. Posts a `{playing: Bool}` message via
/// `webkit.messageHandlers.socialHubAudio` whenever the aggregate playing
/// state of the page changes.
///
/// Event-driven only — no `setInterval`. WebKit reliably bubbles the
/// `play` / `pause` / `ended` / `volumechange` / `emptied` events through
/// the capture phase, which is enough; the previous defensive 800 ms /
/// 2 s polling was redundant and burned CPU forever.
enum AudioBridge {
    static let channelName = "socialHubAudio"

    static let injectedScript = """
    (function(){
      var lastPlaying = false;
      function isAnyPlaying() {
        try {
          var media = document.querySelectorAll('video, audio');
          for (var i = 0; i < media.length; i++) {
            var el = media[i];
            if (!el.paused && !el.ended && el.currentTime > 0 && !el.muted && el.volume > 0) {
              return true;
            }
          }
        } catch(e) {}
        return false;
      }
      function check() {
        var playing = isAnyPlaying();
        if (playing !== lastPlaying) {
          lastPlaying = playing;
          try { window.webkit.messageHandlers.socialHubAudio.postMessage({ playing: playing }); } catch(e) {}
        }
      }
      ['play', 'pause', 'ended', 'volumechange', 'emptied'].forEach(function(ev){
        document.addEventListener(ev, check, true);
      });
      setTimeout(check, 600);
    })();
    """
}
