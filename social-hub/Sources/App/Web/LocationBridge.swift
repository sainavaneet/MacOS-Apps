import Foundation
import CoreLocation
@preconcurrency import WebKit

@MainActor
final class LocationBridge: NSObject {
    static let shared = LocationBridge()
    static let channelName = "socialHubGeo"
    static let injectedScript = """
    (function(){
      try {
        var pending = {};
        var nextId = 1;
        window.__socialHubLocResolve = function(id, ok, payload) {
          var p = pending[id];
          if (!p) return;
          if (!p.watch) delete pending[id];
          try {
            if (ok) {
              p.success({ coords: payload, timestamp: Date.now() });
            } else if (p.error) {
              p.error({ code: (payload && payload.code) || 2,
                        message: (payload && payload.message) || 'unavailable',
                        PERMISSION_DENIED: 1, POSITION_UNAVAILABLE: 2, TIMEOUT: 3 });
            }
          } catch(e) {}
        };
        var geo = {
          getCurrentPosition: function(success, error, opts) {
            var id = nextId++;
            pending[id] = { success: success, error: error, watch: false };
            try { window.webkit.messageHandlers.socialHubGeo.postMessage({ id: id, type: 'getCurrentPosition' }); }
            catch(e) { if (error) error({ code: 2, message: 'unavailable' }); }
          },
          watchPosition: function(success, error, opts) {
            var id = nextId++;
            pending[id] = { success: success, error: error, watch: true };
            try { window.webkit.messageHandlers.socialHubGeo.postMessage({ id: id, type: 'watchPosition' }); }
            catch(e) {}
            return id;
          },
          clearWatch: function(id) {
            delete pending[id];
            try { window.webkit.messageHandlers.socialHubGeo.postMessage({ id: id, type: 'clearWatch' }); } catch(e) {}
          }
        };
        try { Object.defineProperty(navigator, 'geolocation', { value: geo, configurable: false }); }
        catch(e) { try { navigator.geolocation = geo; } catch(e2) {} }
      } catch(e) {}
    })();
    """

    private let manager = CLLocationManager()
    private var latest: CLLocation?

    /// (webView, requestId, isWatch)
    private var pending: [(WKWebView, Int, Bool)] = []
    /// Active watches keyed by request id so we keep streaming updates.
    private var watches: [(WKWebView, Int)] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request(from webView: WKWebView, id: Int, type: String) {
        switch type {
        case "getCurrentPosition":
            if let loc = latest, Date().timeIntervalSince(loc.timestamp) < 60 {
                respond(to: webView, id: id, location: loc, watch: false)
            } else {
                pending.append((webView, id, false))
                start()
            }
        case "watchPosition":
            watches.append((webView, id))
            if let loc = latest {
                respond(to: webView, id: id, location: loc, watch: true)
            }
            start()
        case "clearWatch":
            watches.removeAll { $0.1 == id }
            if watches.isEmpty && pending.isEmpty { manager.stopUpdatingLocation() }
        default:
            break
        }
    }

    private func start() {
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        if status == .denied || status == .restricted {
            fail(code: 1, message: "permission_denied")
            return
        }
        manager.startUpdatingLocation()
    }

    private func respond(to webView: WKWebView, id: Int, location: CLLocation, watch: Bool) {
        let payload: [String: Any] = [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "accuracy": location.horizontalAccuracy,
            "altitude": location.altitude,
            "altitudeAccuracy": location.verticalAccuracy,
            "heading": location.course >= 0 ? location.course : NSNull(),
            "speed": location.speed >= 0 ? location.speed : NSNull()
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        let js = "window.__socialHubLocResolve(\(id), true, \(json));"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func fail(code: Int, message: String) {
        let payload: [String: Any] = ["code": code, "message": message]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        let snapshot = pending + watches.map { ($0.0, $0.1, true) }
        pending.removeAll()
        for (webView, id, _) in snapshot {
            let js = "window.__socialHubLocResolve(\(id), false, \(json));"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}

extension LocationBridge: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.latest = loc
            let toResolve = self.pending
            self.pending.removeAll()
            for (webView, id, _) in toResolve {
                self.respond(to: webView, id: id, location: loc, watch: false)
            }
            for (webView, id) in self.watches {
                self.respond(to: webView, id: id, location: loc, watch: true)
            }
            if self.watches.isEmpty { manager.stopUpdatingLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.fail(code: 2, message: error.localizedDescription) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            if status == .denied || status == .restricted {
                self.fail(code: 1, message: "permission_denied")
            } else if status == .authorizedAlways || status == .authorized {
                if !self.pending.isEmpty || !self.watches.isEmpty {
                    manager.startUpdatingLocation()
                }
            }
        }
    }
}
