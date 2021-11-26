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
        guard let videoCompositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            callback(false, nil)
            return
        }
        let audioCompositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        
        // layerInstruction 用于更改视频图层
        let vcLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoCompositionTrack)
        var layerInstructions = [vcLayerInstruction]
        
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
                        try videoCompositionTrack.insertTimeRange(CMTimeRange(start: .zero, duration: insertVideoTime.duration), of: insertVideoTrack, at: insertTime)
                        
                        // 更改Transform 调整方向、大小
                        var trans = insertVideoTrack.preferredTransform
                        let size = insertVideoTrack.naturalSize
                        let orientation = orientationFromVideo(assetTrack: insertVideoTrack)
                        switch orientation {
                            case .portrait:
                                let scale = renderSize.height / size.width
                                trans = CGAffineTransform(scaleX: scale, y: scale)
                                trans = trans.translatedBy(x: size.height, y: 0)
                                trans = trans.rotated(by: .pi / 2.0)
                            case .landscapeLeft:
                                let scale = renderSize.width / size.width
                                trans = CGAffineTransform(scaleX: scale, y: scale)
                                trans = trans.translatedBy(x: size.width, y: size.height + (renderSize.height - size.height * scale) / scale / 2.0)
                                trans = trans.rotated(by: .pi)
                            case .portraitUpsideDown:
                                let scale = renderSize.height / size.width
                                trans = CGAffineTransform(scaleX: scale, y: scale)
                                trans = trans.translatedBy(x: 0, y: size.width)
                                trans = trans.rotated(by: .pi / 2.0 * 3)
                            case .landscapeRight:
                                // 默认方向
                                let scale = renderSize.width / size.width
                                trans = CGAffineTransform(scaleX: scale, y: scale)
                                trans = trans.translatedBy(x: 0, y: (renderSize.height - size.height * scale) / scale / 2.0)
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
        // videoComposition必须指定 帧率frameDuration、大小renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.renderSize = renderSize
        let vcInstruction = AVMutableVideoCompositionInstruction()
        vcInstruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        vcInstruction.backgroundColor = UIColor.red.cgColor // 可以设置视频背景颜色
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
        // 创建资源集合composition及可编辑轨道
        let composition = AVMutableComposition()
        // 视频轨道
        let videoCompositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) // kCMPersistentTrackID_Invalid 自动创建随机ID
        // 音频轨道
        let audioCompositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        
        var insertTime = CMTime.zero
        for url in urls {
            autoreleasepool {
                // 获取视频资源 并分离出视频、音频轨道
                let asset = AVURLAsset(url: url)
                let videoTrack = asset.tracks(withMediaType: .video).first
                let audioTrack = asset.tracks(withMediaType: .audio).first
                let videoTimeRange = videoTrack?.timeRange
                let audioTimeRange = audioTrack?.timeRange
                
                // 将多个视频轨道合到一个轨道上（AVMutableCompositionTrack）
                if let insertVideoTrack = videoTrack, let insertVideoTime = videoTimeRange {
                    do {
                        // 在某个时间点插入轨道
                        try videoCompositionTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: insertVideoTime.duration), of: insertVideoTrack, at: insertTime)
                    } catch let e {
                        callback(false, e)
                        return
                    }
                }
                
                // 将多个音频轨道合到一个轨道上（AVMutableCompositionTrack）
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
    
    
    /// 添加水印
    /// - Parameters:
    ///   - videoUrl: 视频url
    ///   - wmImage: 水印图片
    ///   - wmText: 水印文字
    ///   - wmframe: 水印位置大小
    ///   - outputUrl: 输出路径
    ///   - callback: 返回
    public static func addWatermark(videoUrl: URL, wmImage: UIImage, wmText: String, wmframe: CGRect, outputUrl: URL, callback: @escaping VideoResult) {
        let asset = AVURLAsset(url: videoUrl)
        let composition = AVMutableComposition()
        do {
            try composition.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: asset, at: .zero)
        } catch let e {
            callback(false, e)
            return
        }
        
        guard let videoCompositionTrack = composition.tracks(withMediaType: .video).first else {
            callback(false, nil)
            return
        }
        
        // instructions
        var trans = videoCompositionTrack.preferredTransform
        let size = videoCompositionTrack.naturalSize
        let orientation = orientationFromVideo(assetTrack: videoCompositionTrack)
        switch orientation {
            case .portrait:
                trans = CGAffineTransform(translationX: size.height, y: 0)
                trans = trans.rotated(by: .pi / 2.0)
            case .landscapeLeft:
                trans = CGAffineTransform(translationX: size.width, y: size.height)
                trans = trans.rotated(by: .pi)
            case .portraitUpsideDown:
                trans = CGAffineTransform(translationX: 0, y: size.width)
                trans = trans.rotated(by: .pi / 2.0 * 3)
            case .landscapeRight:
                // 默认方向
                break
        }
        
        let vcLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoCompositionTrack)
        vcLayerInstruction.setTransform(trans, at: .zero)
        let videoComposition = AVMutableVideoComposition()
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.renderSize = composition.naturalSize
        let vcInstruction = AVMutableVideoCompositionInstruction()
        vcInstruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        vcInstruction.layerInstructions = [vcLayerInstruction]
        videoComposition.instructions = [vcInstruction]
        
        // animationTool
        let renderFrame = CGRect(origin: .zero, size: size)
        let imageLayer = CALayer()
        let textLayer = CATextLayer()
        let watermarkLayer = CALayer()
        let videoLayer = CALayer()
        let animationLayer = CALayer()
        
        // 水印layer 可以包含多个图层
        watermarkLayer.frame = wmframe
        imageLayer.frame = watermarkLayer.bounds
        imageLayer.contents = wmImage.cgImage
        textLayer.frame = watermarkLayer.bounds
        textLayer.string = wmText
        textLayer.foregroundColor = UIColor.red.cgColor
        textLayer.fontSize = 30
        watermarkLayer.addSublayer(imageLayer)
        watermarkLayer.addSublayer(textLayer)
        watermarkLayer.masksToBounds = true
        watermarkLayer.backgroundColor = UIColor.red.cgColor
        
        // 视频layer
        videoLayer.frame = renderFrame
        
        // core animation layer
        animationLayer.frame = renderFrame
        animationLayer.addSublayer(videoLayer)
        animationLayer.addSublayer(watermarkLayer)
        
        let animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: animationLayer)
        videoComposition.animationTool = animationTool
        
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPreset1280x720) else {
            callback(false, nil)
            return
        }
        
        exportSession.videoComposition = videoComposition
        
        exportVideo(exportSession, outputUrl, callback)
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

// MARK: - AVAsssetReader/AVAsssetWriter output/input
extension VideoEditHelper {
    /// 多个视频数据合成一个视频 （通过reader/writer方式）
    public static func writeVideo(urls: URL..., outputUrl: URL, callback: @escaping VideoResult) {
        // 创建资源集合composition及可编辑轨道
        let composition = AVMutableComposition()
        // 视频轨道
        let videoCompositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        // 音频轨道
        let audioCompositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        
        var insertTime = CMTime.zero
        for url in urls {
            autoreleasepool {
                // 获取视频资源 并分离出视频、音频轨道
                let asset = AVURLAsset(url: url)
                let videoTrack = asset.tracks(withMediaType: .video).first
                let audioTrack = asset.tracks(withMediaType: .audio).first
                let videoTimeRange = videoTrack?.timeRange
                let audioTimeRange = audioTrack?.timeRange
                
                // 将多个视频轨道合到一个轨道上（AVMutableCompositionTrack）
                if let insertVideoTrack = videoTrack, let insertVideoTime = videoTimeRange {
                    do {
                        // 在某个时间点插入轨道
                        try videoCompositionTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: insertVideoTime.duration), of: insertVideoTrack, at: insertTime)
                    } catch let e {
                        callback(false, e)
                        return
                    }
                }
                
                // 将多个音频轨道合到一个轨道上（AVMutableCompositionTrack）
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
        
        // -----读取数据----
        let videoTracks = composition.tracks(withMediaType: .video)
        let audioTracks = composition.tracks(withMediaType: .audio)
        
        // AVAssetReader
        var reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: composition)
        } catch let e {
            callback(false, e)
            return
        }
        reader.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        
        // AVAssetReaderOutput
        let videoOutput = AVAssetReaderVideoCompositionOutput(videoTracks: videoTracks, videoSettings: nil)
        videoOutput.alwaysCopiesSampleData = false
        if reader.canAdd(videoOutput) {
            reader.add(videoOutput)
        }
        
        let audioOutput = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: nil)
        audioOutput.alwaysCopiesSampleData = false
        if reader.canAdd(audioOutput) {
            reader.add(audioOutput)
        }
        
        reader.startReading()
        
        // -----写数据----
        // AVAssetWriter
        var writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: outputUrl, fileType: .mp4)
        } catch let e {
            callback(false, e)
            return
        }
        writer.shouldOptimizeForNetworkUse = true
        
        // AVAssetWriterInput
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil)
        if writer.canAdd(videoInput) {
            writer.add(videoInput)
        }
        
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
        if writer.canAdd(audioInput) {
            writer.add(audioInput)
        }
        
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        
        // 准备写入数据
        let inputQueue = DispatchQueue(label: "VideoInputQueue")
        videoInput.requestMediaDataWhenReady(on: inputQueue) {
            encodeReadySamples(from: videoOutput, to: videoInput)
        }
        
        audioInput.requestMediaDataWhenReady(on: inputQueue) {
            encodeReadySamples(from: audioOutput, to: audioInput)
        }
    }
    
    /// 多张图片合成视频
    public static func compositeVideo(images: UIImage..., outputUrl: URL, callback: @escaping VideoResult) {
        
    }
    
    fileprivate static func encodeReadySamples(from output: AVAssetReaderOutput, to input: AVAssetWriterInput) -> Bool {
        while input.isReadyForMoreMediaData {
            guard let sampleBuffer = output.copyNextSampleBuffer() else {
                input.markAsFinished()
                return false
            }
            
            return input.append(sampleBuffer)
        }
        
        return true
    }
}


// MARK: - ENUM
enum VideoOrientation: Int {
    // rawvalue 对应角度
    case landscapeRight = 0
    case portrait = 90
    case landscapeLeft = 180
    case portraitUpsideDown = 270
}
