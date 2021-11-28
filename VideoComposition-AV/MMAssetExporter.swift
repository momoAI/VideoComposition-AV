//
//  MMAssetExporter.swift
//  VideoComposition-AV
//
//  Created by momo on 2021/11/28.
//

import Foundation
import UIKit
import AVFoundation

// AVAsssetReader/AVAsssetWriter output/input

class MMAssetExporter {
    static let renderSize: CGSize = CGSize(width: 720, height: 1280)
    static let timescale: CMTimeScale = 600
    
    private var reader: AVAssetReader!
    private var videoTrackOutput: AVAssetReaderTrackOutput!
    private var audioTrackOutput: AVAssetReaderTrackOutput!
    private var videoOutput: AVAssetReaderVideoCompositionOutput!
    private var audioOutput: AVAssetReaderAudioMixOutput!
    private var writer: AVAssetWriter!
    private var videoInput: AVAssetWriterInput!
    private var audioInput: AVAssetWriterInput!
    
    let inputQueue = DispatchQueue(label: "VideoInputQueue")
    let writeGroup = DispatchGroup()
    
    /// 多个视频数据合成一个视频 （通过reader/writer方式）
    public func writeVideoDefult(urls: URL..., outputUrl: URL, callback: @escaping VideoResult) {
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
        guard let videoTrack = videoTracks.first, let audioTrack = audioTracks.first else {
            callback(false, nil)
            return
        }
        
        // AVAssetReader
        do {
            reader = try AVAssetReader(asset: composition)
        } catch let e {
            callback(false, e)
            return
        }
        reader.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        
        // 音视频uncompressed设置 （使用AVAssetReaderTrackOutput必要使用uncompressed设置）
        let audioOutputSetting = [
            AVFormatIDKey: kAudioFormatLinearPCM
        ]
        let videoOutputSetting = [
            kCVPixelBufferPixelFormatTypeKey as String: UInt32(kCVPixelFormatType_422YpCbCr8)
        ]
        
        videoTrackOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: videoOutputSetting)
        videoTrackOutput.alwaysCopiesSampleData = false
        if reader.canAdd(videoTrackOutput) {
            reader.add(videoTrackOutput)
        }
        
        audioTrackOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: audioOutputSetting)
        audioTrackOutput.alwaysCopiesSampleData = false
        if reader.canAdd(audioTrackOutput) {
            reader.add(audioTrackOutput)
        }
        
        reader.startReading()
        
        // -----写数据----
        // AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: outputUrl, fileType: .mp4)
        } catch let e {
            callback(false, e)
            return
        }
        writer.shouldOptimizeForNetworkUse = true
        
        let videoInputSettings: [String : Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 720,
            AVVideoHeightKey: 1280,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 1000000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264High40
            ]
        ]
        let audioInputSettings: [String : Any] = [
            AVFormatIDKey: NSNumber(value: kAudioFormatMPEG4AAC),
            AVNumberOfChannelsKey: NSNumber(value: 2),
            AVSampleRateKey: NSNumber(value: 44100),
            AVEncoderBitRateKey: NSNumber(value: 128000)
        ]
        // AVAssetWriterInput
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoInputSettings)
        if writer.canAdd(videoInput) {
            writer.add(videoInput)
        }
        
        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioInputSettings)
        if writer.canAdd(audioInput) {
            writer.add(audioInput)
        }
        
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        
        // 准备写入数据
        writeGroup.enter()
        videoInput.requestMediaDataWhenReady(on: inputQueue) { [weak self] in
            guard let wself = self else {
                callback(false, nil)
                return
            }
            
            if wself.encodeReadySamples(from: wself.videoTrackOutput, to: wself.videoInput) {
                wself.writeGroup.leave()
            }
        }
        
        writeGroup.enter()
        audioInput.requestMediaDataWhenReady(on: inputQueue) { [weak self] in
            guard let wself = self else {
                callback(false, nil)
                return
            }
            
            if wself.encodeReadySamples(from: wself.audioTrackOutput, to: wself.audioInput) {
                wself.writeGroup.leave()
            }
        }
        
        writeGroup.notify(queue: inputQueue) {
            self.writer.finishWriting {
                callback(true, nil)
            }
        }
    }
    
    /// 多个视频数据合成一个视频 设置audiomix,videocompostion （通过reader/writer方式）
    public func writeVideo(urls: URL..., outputUrl: URL, callback: @escaping VideoResult) {
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
                        let orientation = VideoEditHelper.orientationFromVideo(assetTrack: insertVideoTrack)
                        switch orientation {
                            case .portrait:
                                let scale = MMAssetExporter.renderSize.height / size.width
                                trans = CGAffineTransform(scaleX: scale, y: scale)
                                trans = trans.translatedBy(x: size.height, y: 0)
                                trans = trans.rotated(by: .pi / 2.0)
                            case .landscapeLeft:
                                let scale = MMAssetExporter.renderSize.width / size.width
                                trans = CGAffineTransform(scaleX: scale, y: scale)
                                trans = trans.translatedBy(x: size.width, y: size.height + (MMAssetExporter.renderSize.height - size.height * scale) / scale / 2.0)
                                trans = trans.rotated(by: .pi)
                            case .portraitUpsideDown:
                                let scale = MMAssetExporter.renderSize.height / size.width
                                trans = CGAffineTransform(scaleX: scale, y: scale)
                                trans = trans.translatedBy(x: 0, y: size.width)
                                trans = trans.rotated(by: .pi / 2.0 * 3)
                            case .landscapeRight:
                                // 默认方向
                                let scale = MMAssetExporter.renderSize.width / size.width
                                trans = CGAffineTransform(scaleX: scale, y: scale)
                                trans = trans.translatedBy(x: 0, y: (MMAssetExporter.renderSize.height - size.height * scale) / scale / 2.0)
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
        
        let videoTracks = composition.tracks(withMediaType: .video)
        let audioTracks = composition.tracks(withMediaType: .audio)
        
        let videoComposition = AVMutableVideoComposition()
        // videoComposition必须指定 帧率frameDuration、大小renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.renderSize = MMAssetExporter.renderSize
        let vcInstruction = AVMutableVideoCompositionInstruction()
        vcInstruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        vcInstruction.backgroundColor = UIColor.red.cgColor // 可以设置视频背景颜色
        vcInstruction.layerInstructions = layerInstructions
        videoComposition.instructions = [vcInstruction]
        
        var audioParameters: [AVMutableAudioMixInputParameters] = []
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
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = audioParameters
        
        
        // AVAssetReader
        do {
            reader = try AVAssetReader(asset: composition)
        } catch let e {
            callback(false, e)
            return
        }
        reader.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        
        // AVAssetReaderOutput
        videoOutput = AVAssetReaderVideoCompositionOutput(videoTracks: videoTracks, videoSettings: nil)
        videoOutput.alwaysCopiesSampleData = false
        videoOutput.videoComposition = videoComposition
        if reader.canAdd(videoOutput) {
            reader.add(videoOutput)
        }

        audioOutput = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: nil)
        audioOutput.alwaysCopiesSampleData = false
        audioOutput.audioMix = audioMix
        if reader.canAdd(audioOutput) {
            reader.add(audioOutput)
        }
        
        reader.startReading()
        
        // -----写数据----
        // AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: outputUrl, fileType: .mp4)
        } catch let e {
            callback(false, e)
            return
        }
        writer.shouldOptimizeForNetworkUse = true
        
        let videoInputSettings: [String : Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 720,
            AVVideoHeightKey: 1280,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 1000000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264High40
            ]
        ]
        let audioInputSettings: [String : Any] = [
            AVFormatIDKey: NSNumber(value: kAudioFormatMPEG4AAC),
            AVNumberOfChannelsKey: NSNumber(value: 2),
            AVSampleRateKey: NSNumber(value: 44100),
            AVEncoderBitRateKey: NSNumber(value: 128000)
        ]
        // AVAssetWriterInput
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoInputSettings)
        if writer.canAdd(videoInput) {
            writer.add(videoInput)
        }
        
        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioInputSettings)
        if writer.canAdd(audioInput) {
            writer.add(audioInput)
        }
        
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        
        // 准备写入数据
        writeGroup.enter()
        videoInput.requestMediaDataWhenReady(on: inputQueue) { [weak self] in
            guard let wself = self else {
                callback(false, nil)
                return
            }
            
            if wself.encodeReadySamples(from: wself.videoOutput, to: wself.videoInput) {
                wself.writeGroup.leave()
            }
        }
        
        writeGroup.enter()
        audioInput.requestMediaDataWhenReady(on: inputQueue) { [weak self] in
            guard let wself = self else {
                callback(false, nil)
                return
            }
            
            if wself.encodeReadySamples(from: wself.audioOutput, to: wself.audioInput) {
                wself.writeGroup.leave()
            }
        }
        
        writeGroup.notify(queue: inputQueue) {
            self.writer.finishWriting {
                callback(true, nil)
            }
        }
    }
    
    /// 多张图片合成视频
    public func compositeVideo(images: UIImage..., outputUrl: URL, callback: @escaping VideoResult) {
        
    }
    
    /// 解码编码 返回结果：true：SampleBuffer结束， false:SampleBuffer未结束
    fileprivate func encodeReadySamples(from output: AVAssetReaderOutput, to input: AVAssetWriterInput) -> Bool {
        while input.isReadyForMoreMediaData {
            guard let sampleBuffer = output.copyNextSampleBuffer() else {
                input.markAsFinished()
                return true
            }
            
            let appendResult = input.append(sampleBuffer)
            if !appendResult {
                return true
            }
        }
        
        return false
    }
}
