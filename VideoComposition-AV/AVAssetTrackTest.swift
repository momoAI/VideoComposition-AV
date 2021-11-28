//
//  AVAssetTrackTest.swift
//  VideoComposition-AV
//
//  Created by momo on 2021/11/8.
//

import Foundation
import AVFoundation

struct AVAssetTrackTest {
    static func test() {
        let url2 = Bundle.main.url(forResource: "video2.MP4", withExtension: nil)
        guard let videoUrl = url2 else { return }
        let asset2 = AVURLAsset(url: videoUrl)
        
        guard let videoTrack = asset2.tracks(withMediaType: .video).first else { return }
        let trackAsset = videoTrack.asset
        print(asset2 == trackAsset)
        print(videoTrack.trackID)
        print(videoTrack.mediaType)
        
        guard let trackDes = videoTrack.formatDescriptions as? [CMVideoFormatDescription] else { return }
        for des in trackDes {
            print(des.mediaSubType,des.extensions)
        }
        
        print(videoTrack.isPlayable,videoTrack.isEnabled,videoTrack.isDecodable)
        print(videoTrack.totalSampleDataLength)
        print(videoTrack.hasMediaCharacteristic(.visual),videoTrack.hasMediaCharacteristic(.audible),videoTrack.hasMediaCharacteristic(.legible),videoTrack.hasMediaCharacteristic(.frameBased),videoTrack.hasMediaCharacteristic(.easyToRead))
        
        print(videoTrack.timeRange, videoTrack.estimatedDataRate)
        print(videoTrack.naturalSize)
        print(videoTrack.preferredVolume)
        
        print(videoTrack.nominalFrameRate, videoTrack.minFrameDuration)
        
        for segment in videoTrack.segments {
            print(segment)
        }
    }
}
