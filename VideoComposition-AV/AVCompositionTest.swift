//
//  AVCompositionTest.swift
//  VideoComposition-AV
//
//  Created by momo on 2021/11/9.
//

import Foundation
import AVFoundation
import UIKit

struct AVCompositionTest {
    static func test() {
        let url = Bundle.main.url(forResource: "video1.MP4", withExtension: nil)
        guard let videoUrl = url else { return }
        let asset = AVURLAsset(url: videoUrl)
        guard let videoAssetTrack = asset.tracks(withMediaType: .video).first else { return }
        guard let audioAssetTrack = asset.tracks(withMediaType: .audio).first else { return }
        
        let composition = AVMutableComposition()
        // 视频
        guard let videoCompositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { return }
        try? videoCompositionTrack.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: videoAssetTrack, at: .zero)
        
        // 音频
        let audioCompositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        try? audioCompositionTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: audioAssetTrack, at: .zero)
        
        print(composition.tracks)
        
        // videoInstruction
        let videoCoposition = AVMutableVideoComposition()
        videoCoposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoCoposition.renderSize = videoAssetTrack.naturalSize
        let vcInstruction = AVMutableVideoCompositionInstruction()
        vcInstruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
        vcInstruction.backgroundColor = UIColor.red.cgColor
        let vcLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoCompositionTrack)
        vcLayerInstruction.setTransform(videoAssetTrack.preferredTransform, at: .zero)
        vcLayerInstruction.setOpacity(0, at: .zero)
        vcInstruction.layerInstructions = [vcLayerInstruction]
        videoCoposition.instructions = [vcInstruction]
        
        // audioMix
        let audioMix = AVMutableAudioMix()
        let amParameter = AVMutableAudioMixInputParameters(track: audioCompositionTrack)
        amParameter.setVolume(1, at: .zero)
        audioMix.inputParameters = [amParameter]
        
//        AVComposition
//        AVMutableComposition
//        AVCompositionTrack
//        AVMutableCompositionTrack
        
//        AVMutableAudioMix
//
//        AVVideoComposition
//        AVMutableVideoComposition
//        AVVideoCompositionInstruction
//        AVMutableVideoCompositionInstruction
//        AVVideoCompositionLayerInstruction
//        AVMutableVideoCompositionLayerInstruction
        
    }
}
