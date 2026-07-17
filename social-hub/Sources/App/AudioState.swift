import SwiftUI

@MainActor
final class AudioState: ObservableObject {
    @Published var playingAudio: Set<String> = []

    func setPlayingAudio(_ playing: Bool, for serviceID: String) {
        if playing {
            playingAudio.insert(serviceID)
        } else {
            playingAudio.remove(serviceID)
        }
    }
}
