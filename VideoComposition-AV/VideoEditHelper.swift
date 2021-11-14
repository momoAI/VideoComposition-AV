//
//  VideoEditHelper.swift
//  VideoComposition-AV
//
//  Created by luxu on 2021/11/10.
//

import Foundation
import UIKit
import AVFoundation
import Photos

// (是否成功，错误信息)
typealias VideoResult = (Bool, Error?) -> Void


struct VideoEditHelper {
    
    static let renderSize: CGSize = CGSize(width: 720, height: 1280)
    static let timescale: CMTimeScale = 600
    
    /// 合成视频
    /// - Parameters:
    ///   - urls: 视频url  http、local
    ///   - outputUrl: 指定合成后视频存储路径（之后通过该路径获取视频）
    ///   - callback: 合成结果
    public static func compositeVideos(urls: URL..., outputUrl: URL, callback: @escaping VideoResult) {
        let composition = AVMutableComposition()
        let videoCompositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let audioCompositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        var insertTime = CMTime.zero
        var layerInstructions: [AVMutableVideoCompositionLayerInstruction] = []
        for url in urls {
            autoreleasepool {
                let asset = AVURLAsset(url: url)
                let videoTrack = asset.tracks(withMediaType: .video).first
                let audioTrack = asset.tracks(withMediaType: .audio).first
                let videoTimeRange = videoTrack?.timeRange
                let audioTimeRange = audioTrack?.timeRange
                
                if let insertVideoTrack = videoTrack, let insertVideoTime = videoTimeRange {
                    do {
                        try videoCompositionTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: insertVideoTime.duration), of: insertVideoTrack, at: insertTime)
                        
                        var trans = insertVideoTrack.preferredTransform
                        let vcLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: insertVideoTrack)
                        let size = insertVideoTrack.naturalSize
                        if size.width / size.height > 1 {
                            let scale = renderSize.width / size.width
                            let height = scale * renderSize.height
                            trans = CGAffineTransform(a: insertVideoTrack.preferredTransform.a * scale, b: insertVideoTrack.preferredTransform.b * scale, c: insertVideoTrack.preferredTransform.c * scale, d: insertVideoTrack.preferredTransform.d * scale, tx: insertVideoTrack.preferredTransform.tx * scale, ty: insertVideoTrack.preferredTransform.ty * scale + (renderSize.height - height) / 2)
                        }
                        
                        vcLayerInstruction.setTransform(trans, at: insertTime)
                        layerInstructions.append(vcLayerInstruction)
                    } catch let e {
                        callback(false, e)
                        return
                    }
                }
                if let insertAudioTrack = audioTrack, let insertAudioTime = audioTimeRange {
                    do {
                        try audioCompositionTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: insertAudioTime.duration), of: insertAudioTrack, at: insertTime)
                    } catch let e {
                        callback(false, e)
                        return
                    }
                }
                
                insertTime = insertTime + asset.duration
            }
        }
        
        let videoComposition = AVMutableVideoComposition()
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.renderSize = renderSize
        let vcInstruction = AVMutableVideoCompositionInstruction()
        vcInstruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        vcInstruction.backgroundColor = UIColor.red.cgColor
        vcInstruction.layerInstructions = layerInstructions
        videoComposition.instructions = [vcInstruction]
        
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPreset1280x720) else {
            callback(false, nil)
            return
        }
        
        exportSession.videoComposition = videoComposition
        
        exportVideo(exportSession, outputUrl, callback)
    }
    
    /// 合成视频 不设置videoInstruction，audioMix
    /// - Parameters:
    ///   - urls: 视频url  http、local
    ///   - outputUrl: 指定合成后视频存储路径（之后通过该路径获取视频）
    ///   - callback: 合成结果
    public static func compositeVideosDefault(urls: URL..., outputUrl: URL, callback: @escaping VideoResult) {
        let composition = AVMutableComposition()
        let videoCompositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let audioCompositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        var insertTime = CMTime.zero
        for url in urls {
            autoreleasepool {
                let asset = AVURLAsset(url: url)
                let videoTrack = asset.tracks(withMediaType: .video).first
                let audioTrack = asset.tracks(withMediaType: .audio).first
                let videoTimeRange = videoTrack?.timeRange
                let audioTimeRange = audioTrack?.timeRange
                
                if let insertVideoTrack = videoTrack, let insertVideoTime = videoTimeRange {
                    do {
                        try videoCompositionTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: insertVideoTime.duration), of: insertVideoTrack, at: insertTime)
                    } catch let e {
                        callback(false, e)
                        return
                    }
                }
                if let insertAudioTrack = audioTrack, let insertAudioTime = audioTimeRange {
                    do {
                        try audioCompositionTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: insertAudioTime.duration), of: insertAudioTrack, at: insertTime)
                    } catch let e {
                        callback(false, e)
                        return
                    }
                }
                
                // insertTimeRange 多个轨道，后一个视频黑屏
    //            let assetTimeRage = CMTimeRange(start: .zero, duration: asset.duration)
    //            do {
    //                try composition.insertTimeRange(assetTimeRage, of: asset, at: insertTime)
    //            } catch let e {
    //                callback(false, e)
    //                return
    //            }
                
                insertTime = insertTime + asset.duration
            }
        }
        
        // 多个视频为720 1280的使用 AVAssetExportPresetMediumQuality/AVAssetExportPresetLowQuality 报错：Code=-11821 "Cannot Decode"
        exportVideo(composition, AVAssetExportPresetPassthrough, outputUrl, callback)
    }
    
    /// 视频添加音频轨道
    /// - Parameters:
    ///   - videoUrl: 视频
    ///   - audioUrl: 音频
    ///   - outputUrl: 合成后路径
    ///   - removeOriginalAudio: 是否删除原音频 默认false
    ///   - callback: 结果
    public static func addAudio(videoUrl: URL, audioUrl: URL, outputUrl: URL, removeOriginalAudio: Bool = false, callback: @escaping VideoResult) {
        var audioParameters: [AVMutableAudioMixInputParameters] = []
        let asset = AVURLAsset(url: videoUrl)
        let composition = AVMutableComposition()
        do {
            try composition.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: asset, at: .zero)
        } catch let e {
            callback(false, e)
            return
        }

        let tracks = composition.tracks(withMediaType: .audio)
        for track in tracks {
            if removeOriginalAudio {
                composition.removeTrack(track)
            } else {
                let adParameter = AVMutableAudioMixInputParameters(track: track)
                adParameter.setVolume(0.5, at: .zero)
                audioParameters.append(adParameter)
            }
        }
        
        let audioAsset = AVURLAsset(url: audioUrl)
        let audioCompositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        let audioTracks = audioAsset.tracks(withMediaType: .audio)
        for audioTrack in audioTracks {
            let adParameter = AVMutableAudioMixInputParameters(track: audioTrack)
            adParameter.setVolume(1, at: .zero)
            audioParameters.append(adParameter)
            
            do {
                try audioCompositionTrack?.insertTimeRange(audioTrack.timeRange, of: audioTrack, at: .zero)
            } catch let e {
                callback(false, e)
                return
            }
        }
        
        // AVAssetExportPresetPassthrough报错：Code=-11838 "Operation Stopped"
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetMediumQuality) else {
            callback(false, nil)
            return
        }
        // 调节音频
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = audioParameters
        exportSession.audioMix = audioMix
        
        exportVideo(exportSession, outputUrl, callback)
    }
    
    /// 多张图片合成视频
    public static func compositeVideo(images: UIImage..., outputUrl: URL, callback: @escaping VideoResult) {
        
    }
    
    /// 删除某类型（轨道）数据
    /// - Parameters:
    ///   - url: 视频url
    ///   - outputUrl: 保存路径
    ///   - type：类型
    ///   - exportback: 导出回调 为nil不导出
    /// - Returns: 合成后的Composition
    public static func removeTrack(url: URL, outputUrl: URL, type: AVMediaType, exportback: VideoResult? = nil) -> AVMutableComposition? {
        let asset = AVURLAsset(url: url)
        let composition = AVMutableComposition()
        do {
            try composition.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: asset, at: .zero)
        } catch let e {
            exportback?(false, e)
            return nil
        }
        
        let tracks = composition.tracks(withMediaType: type)
        for track in tracks {
            composition.removeTrack(track)
        }
        
        exportVideo(composition, AVAssetExportPresetPassthrough, outputUrl, exportback)
        
        return composition
    }
    
    /// 裁剪视频
    /// - Parameters:
    ///   - url: 视频url
    ///   - outputUrl: 保存路径
    ///   - secondsRange: 选取的时间范围
    ///   - callback: 返回
    public static func cutVideo(url: URL, outputUrl: URL, secondsRange: ClosedRange<Double>, callback: @escaping VideoResult) {
        let asset = AVURLAsset(url: url)
        let composition = AVMutableComposition()
        do {
            let timeRange = CMTimeRange(start: CMTime(seconds: secondsRange.lowerBound, preferredTimescale: timescale), end: CMTime(seconds: secondsRange.upperBound, preferredTimescale: timescale))
            try composition.insertTimeRange(timeRange, of: asset, at: .zero)
        } catch let e {
            callback(false, e)
            return
        }
        
        exportVideo(composition, AVAssetExportPresetPassthrough, outputUrl, callback)
    }
    
    /// 获取指定时间帧
    /// - Parameters:
    ///   - url: 视频url
    ///   - seconds: 指定时间 s
    /// - Returns: 帧对应图片
    public static func getVideoFrameImage(_ url: URL, seconds: Double) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        // .zero 精确获取
        imageGenerator.requestedTimeToleranceAfter = .zero
        imageGenerator.requestedTimeToleranceBefore = .zero
        var actualTime: CMTime = .zero
        do {
            let time = CMTime(seconds: seconds, preferredTimescale: timescale)
            let imageRef = try imageGenerator.copyCGImage(at: time, actualTime: &actualTime)
            print(actualTime)
            return UIImage(cgImage: imageRef)
        } catch {
            return nil
        }
    }
    
    /// 保存视频到相册
    public static func saveVideo(_ url: URL, callback: @escaping VideoResult) {
        let photoLibrary = PHPhotoLibrary.shared()
        photoLibrary.performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        } completionHandler: { success, error in
            callback(success, error)
        }
    }
    
    
    // MARK: --private
    fileprivate static func exportVideo(_ exportSession: AVAssetExportSession, _ outputUrl: URL, _ callback: @escaping VideoResult) {
        exportSession.outputFileType = .mp4
        exportSession.outputURL = outputUrl
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.exportAsynchronously {
            switch exportSession.status {
                case .completed:
                    callback(true, nil)
                default:
                    callback(false, exportSession.error)
            }
        }
    }
    
    fileprivate static func exportVideo(_ asset: AVAsset, _ presetName: String, _ outputUrl: URL, _ callback: VideoResult? = nil) {
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: presetName) else {
            callback?(false, nil)
            return
        }
        print(AVAssetExportSession.exportPresets(compatibleWith: asset))
        
        exportSession.outputFileType = .mp4
        exportSession.outputURL = outputUrl
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.exportAsynchronously {
            switch exportSession.status {
                case .completed:
                    callback?(true, nil)
                default:
                    callback?(false, exportSession.error)
            }
        }
    }
    
    /// 获取视频方向
    fileprivate static func orientationFromVideo(assetTrack: AVAssetTrack) -> VideoOrientation {
        var orientation: VideoOrientation = .landscapeRight
        let t = assetTrack.preferredTransform
        if t.a == 0 && t.b == 1.0 && t.c == -1.0 && t.d == 0 {
            orientation = .portrait
        } else if t.a == 0 && t.b == -1.0 && t.c == 1.0 && t.d == 0 {
            orientation = .portraitUpsideDown
        } else if t.a == 1.0 && t.b == 0 && t.c == 0 && t.d == 1.0 {
            orientation = .landscapeRight
        } else if t.a == -1.0 && t.b == 0 && t.c == 0 && t.d == -1.0 {
            // LandscapeLeft
            orientation = .landscapeLeft
        }
        return orientation
    }
}


enum VideoOrientation: Int {
    // rawvalue 对应角度
    case landscapeRight = 0
    case portrait = 90
    case landscapeLeft = 180
    case portraitUpsideDown = 270
}
