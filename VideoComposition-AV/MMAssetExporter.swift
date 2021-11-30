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
    
    private let inputQueue = DispatchQueue(label: "VideoInputQueue")
    private let writeGroup = DispatchGroup()
    
    public var composition: AVComposition!
    public var videoComposition: AVVideoComposition!
    public var audioMix: AVAudioMix!
    public var outputUrl: URL!
    public var videoInputSettings: [String : Any]?
    public var videoOutputSettings: [String : Any]?
    public var audioInputSettings: [String : Any]?
    public var audioOutputSettings: [String : Any]?
    
    
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
            AVVideoWidthKey: MMAssetExporter.renderSize.width,
            AVVideoHeightKey: MMAssetExporter.renderSize.height,
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
        var audioParameters: [AVMutableAudioMixInputParameters] = []
        
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
                        
                        let adParameter = AVMutableAudioMixInputParameters(track: insertAudioTrack)
                        adParameter.setVolume(1, at: .zero)
                        audioParameters.append(adParameter)
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
        videoComposition.renderSize = MMAssetExporter.renderSize
        let vcInstruction = AVMutableVideoCompositionInstruction()
        vcInstruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        vcInstruction.backgroundColor = UIColor.red.cgColor // 可以设置视频背景颜色
        vcInstruction.layerInstructions = layerInstructions
        videoComposition.instructions = [vcInstruction]
        
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = audioParameters
        
        self.composition = composition
        self.outputUrl = outputUrl
        self.videoComposition = videoComposition
        self.audioMix = audioMix
        self.videoInputSettings = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: MMAssetExporter.renderSize.width,
            AVVideoHeightKey: MMAssetExporter.renderSize.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 1000000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264High40
            ]
        ]
        self.audioInputSettings = [
            AVFormatIDKey: NSNumber(value: kAudioFormatMPEG4AAC),
            AVNumberOfChannelsKey: NSNumber(value: 2),
            AVSampleRateKey: NSNumber(value: 44100),
            AVEncoderBitRateKey: NSNumber(value: 128000)
        ]
        
        self .exportAsynchronously(completionHandler: callback)
    }
    
    public func exportAsynchronously(completionHandler callback: @escaping VideoResult) {
        let videoTracks = composition.tracks(withMediaType: .video)
        let audioTracks = composition.tracks(withMediaType: .audio)
        
        do {
            reader = try AVAssetReader(asset: composition)
        } catch let e {
            callback(false, e)
            return
        }
        reader.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        
        // AVAssetReaderOutput
        videoOutput = AVAssetReaderVideoCompositionOutput(videoTracks: videoTracks, videoSettings: videoOutputSettings)
        videoOutput.alwaysCopiesSampleData = false
        videoOutput.videoComposition = videoComposition
        if reader.canAdd(videoOutput) {
            reader.add(videoOutput)
        }

        audioOutput = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: audioOutputSettings)
        audioOutput.alwaysCopiesSampleData = false
        audioOutput.audioMix = audioMix
        if reader.canAdd(audioOutput) {
            reader.add(audioOutput)
        }
        
        if !reader.startReading() {
            callback(false, reader.error)
            return
        }
        
        // -----写数据----
        // AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: outputUrl, fileType: .mp4)
        } catch let e {
            callback(false, e)
            return
        }
        writer.shouldOptimizeForNetworkUse = true
        
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
        do {
            writer = try AVAssetWriter(outputURL: outputUrl, fileType: .mp4)
        } catch let e {
            callback(false, e)
            return
        }
        writer.shouldOptimizeForNetworkUse = true
        
        videoInputSettings = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: MMAssetExporter.renderSize.width,
            AVVideoHeightKey: MMAssetExporter.renderSize.height
        ]
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoInputSettings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: nil)
        if writer.canAdd(videoInput) {
            writer.add(videoInput)
        }
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        
        let pixelBuffers = images.map { image in
            self.pixelBuffer(from: image)
        }
        
        let seconds = 2 // 每张图片显示时长 s
        let timescale = 30 // 1s 30帧
        let frames = images.count * seconds * timescale // 总帧数
        var frame = 0
        videoInput.requestMediaDataWhenReady(on: inputQueue) { [weak self] in
            guard let wself = self else {
                callback(false, nil)
                return
            }
            
            if frame >= frames {
                // 全部数据写入完毕
                wself.videoInput.markAsFinished()
                wself.writer.finishWriting {
                    callback(true, nil)
                }
                return
            }
            
            let imageIndex = frame / (seconds * timescale)
            let time = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(timescale))
            let pxData = pixelBuffers[imageIndex]
            if let cvbuffer = pxData {
                adaptor.append(cvbuffer, withPresentationTime: time)
            }
            
            frame += 1
        }
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
    
    fileprivate func pixelBuffer(from image: UIImage) -> CVPixelBuffer? {
        guard let cgImage = image.cgImage else { return nil }
        
        let size = image.size
        // 宽高须是4的整数倍，不然视频会出现绿边
        let width = Int(Int(size.width / 4) * 4)
        let height = Int(Int(size.height / 4) * 4)
        var kcall = kCFTypeDictionaryKeyCallBacks
        var vcall = kCFTypeDictionaryValueCallBacks
        let emptyProperties = CFDictionaryCreate(kCFAllocatorDefault, nil, nil, CFIndex(0), &kcall, &vcall)
        let options: [CFString : Any] = [
            kCVPixelBufferCGImageCompatibilityKey : true,
            kCVPixelBufferCGBitmapContextCompatibilityKey : true,
            kCVPixelBufferIOSurfacePropertiesKey : emptyProperties ?? []
        ]
        var opPxbuffer: CVPixelBuffer?
        _ = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, options as CFDictionary, &opPxbuffer);
        guard let pxbuffer = opPxbuffer else { return nil }
        
        CVPixelBufferLockBaseAddress(pxbuffer, CVPixelBufferLockFlags(rawValue: 0));
        
        let pxdata = CVPixelBufferGetBaseAddress(pxbuffer)
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        var bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue;
        let hasAlpha = cgImage.alphaInfo != CGImageAlphaInfo.none
        if (!hasAlpha) {
            bitmapInfo = CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        }
        
        // Quartz创建一个位图上下文，将要绘制的信息作为位图数据绘制到指定的内存块。
        // 一个新的位图上下文的像素格式由三个参数决定：每个组件的位数，颜色空间，alpha选项
        guard let context = CGContext(data: pxdata, width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pxbuffer), space: rgbColorSpace, bitmapInfo: bitmapInfo) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        
        CVPixelBufferUnlockBaseAddress(pxbuffer, CVPixelBufferLockFlags(rawValue: 0))
        
        return pxbuffer
    }
}
