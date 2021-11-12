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
                        
                        let vcLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: insertVideoTrack)
                        vcLayerInstruction.setTransform(insertVideoTrack.preferredTransform, at: insertTime)
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
        videoComposition.renderSize = composition.naturalSize
        let vcInstruction = AVMutableVideoCompositionInstruction()
        vcInstruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        vcInstruction.backgroundColor = UIColor.red.cgColor
        vcInstruction.layerInstructions = layerInstructions
        videoComposition.instructions = [vcInstruction]
        
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            callback(false, nil)
            return
        }
        
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
        
        exportVideo(composition, AVAssetExportPresetPassthrough, outputUrl, callback)
    }
    
    /// 多张图片合成视频
    public static func compositeVideo(images: UIImage..., outputUrl: URL, callback: @escaping VideoResult) {
        
    }
    
    /// 删除某类型（轨道）数据
    /// - Parameters:
    ///   - url: 视频url
    ///   - outputUrl: 保存路径
    ///   - type：类型
    ///   - callback: 返回
    public static func removeTrack(url: URL, outputUrl: URL, type: AVMediaType, callback: @escaping VideoResult) {
        let asset = AVURLAsset(url: url)
        let composition = AVMutableComposition()
        do {
            try composition.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: asset, at: .zero)
        } catch let e {
            callback(false, e)
            return
        }
        
        let tracks = composition.tracks(withMediaType: type)
        for track in tracks {
            composition.removeTrack(track)
        }
        
        exportVideo(composition, AVAssetExportPresetPassthrough, outputUrl, callback)
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
    
    fileprivate static func exportVideo(_ asset: AVAsset, _ presetName: String, _ outputUrl: URL, _ callback: @escaping VideoResult) {
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: presetName) else {
            callback(false, nil)
            return
        }
        
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
}
