import AVFoundation
import XCTest

final class InteractionSoundResourceTests: XCTestCase {
    func testCaptureCueResourcesAreBundledAndPlayable() throws {
        let resourceNames = [
            "ResponsayCaptureStartCue", "ResponsayCaptureStopCue",
            "ResponsayCaptureStart_PianoUpright", "ResponsayCaptureStop_PianoUpright",
            "ResponsayCaptureStart_Marimba", "ResponsayCaptureStop_Marimba",
            "ResponsayCaptureStart_Beep", "ResponsayCaptureStop_Beep",
            "ResponsayCaptureStart_Blip", "ResponsayCaptureStop_Blip",
            "ResponsayCaptureStart_Blop", "ResponsayCaptureStop_Blop",
            "ResponsayCaptureStart_Bong", "ResponsayCaptureStop_Bong",
            "ResponsayCaptureStart_Clack", "ResponsayCaptureStop_Clack",
            "ResponsayCaptureStart_Ding", "ResponsayCaptureStop_Ding",
            "ResponsayCaptureStart_Sonar", "ResponsayCaptureStop_Sonar",
            "ResponsayCaptureStart_Thump", "ResponsayCaptureStop_Thump",
            "ResponsayCaptureStart_TwoTone", "ResponsayCaptureStop_TwoTone",
        ]
        for resourceName in resourceNames {
            let url = try XCTUnwrap(
                Bundle.main.url(forResource: resourceName, withExtension: "wav"),
                "\(resourceName).wav should be copied into the app bundle")
            let player = try AVAudioPlayer(contentsOf: url)

            XCTAssertGreaterThan(player.duration, 0.15)
            XCTAssertLessThan(player.duration, 0.5)
            XCTAssertEqual(player.numberOfChannels, 1)
            XCTAssertTrue(player.prepareToPlay())
        }
    }
}
