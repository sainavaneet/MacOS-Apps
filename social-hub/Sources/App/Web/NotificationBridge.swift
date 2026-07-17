import Foundation
import UserNotifications

enum NotificationBridge {
    static let channelName = "socialHubNotify"

    static let injectedScript = """
    (function(){
      function send(title, opts){
        try {
          window.webkit.messageHandlers.socialHubNotify.postMessage({
            title: String(title ?? ''),
            body: (opts && opts.body) ? String(opts.body) : '',
            tag: (opts && opts.tag) ? String(opts.tag) : '',
            icon: (opts && opts.icon) ? String(opts.icon) : ''
          });
        } catch(e) {}
      }

      // 1) Page-side `new Notification(...)`
      try {
        function Shim(title, opts){
          send(title, opts);
          return { close: function(){}, addEventListener: function(){}, removeEventListener: function(){} };
        }
        Shim.permission = 'granted';
        Shim.requestPermission = function(cb){
          try { if (cb) cb('granted'); } catch(e) {}
          return Promise.resolve('granted');
        };
        Object.defineProperty(window, 'Notification', { value: Shim, writable: false, configurable: false });
      } catch(e) {}

      // 2) Service-worker push: ServiceWorkerRegistration.prototype.showNotification
      //    This is how WhatsApp, Messenger, Instagram actually deliver pushes.
      try {
        if (window.ServiceWorkerRegistration && ServiceWorkerRegistration.prototype) {
          var orig = ServiceWorkerRegistration.prototype.showNotification;
          ServiceWorkerRegistration.prototype.showNotification = function(title, opts){
            send(title, opts);
            try { return orig.apply(this, arguments); } catch(e) { return Promise.resolve(); }
          };
        }
      } catch(e) {}

      // 3) Permission query API
      try {
        if (navigator.permissions && navigator.permissions.query) {
          var origQuery = navigator.permissions.query.bind(navigator.permissions);
          navigator.permissions.query = function(desc){
            if (desc && desc.name === 'notifications') {
              return Promise.resolve({ state: 'granted', addEventListener: function(){}, removeEventListener: function(){} });
            }
            return origQuery(desc);
          };
        }
      } catch(e) {}
    })();
    """

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func deliver(title: String, body: String, serviceName: String) {
        let content = UNMutableNotificationContent()
        content.title = title.isEmpty ? serviceName : title
        if !body.isEmpty { content.body = body }
        content.subtitle = serviceName
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
