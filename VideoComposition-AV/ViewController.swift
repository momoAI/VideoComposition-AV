//
//  ViewController.swift
//  VideoComposition-AV
//
//  Created by 研发部-陆续 on 2021/10/26.
//

import UIKit

class ViewController: UIViewController {
    let exporter = MMAssetExporter()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
//        CMTimeTest.test()
        
//        AVAssetTest.test()
        
//        AVAssetTrackTest.test()
        
//        AVCompositionTest.test()
        
        let btn = UIButton(frame: CGRect(x: 100, y: 100, width: 100, height: 50))
        btn.setTitle("test", for: .normal)
        btn.backgroundColor = .red
        btn.addTarget(self, action: #selector(testVideo), for: .touchUpInside)
        view.addSubview(btn)
        
    }

    @objc func testVideo() {
        let videoUrl = FileHelper.createDirectory(pathDirectory: .documentDirectory, path: "videos")
        guard let outputUrl = videoUrl?.appendingPathComponent(FileHelper.uuid() + ".mp4") else { return }
        let ai1 = Bundle.main.url(forResource: "video1.MP4", withExtension: nil)
        let ai2 = Bundle.main.url(forResource: "video2.MP4", withExtension: nil)
//        let ai3 = Bundle.main.url(forResource: "video3.mp4", withExtension: nil)
        let ai3 = Bundle.main.url(forResource: "landscapeRight.MOV", withExtension: nil)
        guard let url1 = ai1, let url2 = ai2, let url3 = ai3 else { return }
        
//        VideoEditHelper.compositeVideosDefault(urls: url1, url2, url3, outputUrl: outputUrl) { success, error in
//
//        }
        
        
//        VideoEditHelper.compositeVideos(urls: url3, outputUrl: outputUrl) { success, error in
//
//        }
        
//        VideoEditHelper.removeTrack(url: url1, outputUrl: outputUrl, type: .audio) { success, error in
//
//        }
    
//        let img = VideoEditHelper.getVideoFrameImage(url1, seconds: 0)
        
//        VideoEditHelper.cutVideo(url: url1, outputUrl: outputUrl, secondsRange: 0.0...10.0) { success, error in
//
//        }
        
//        VideoEditHelper.saveVideo(url1) { suc, err in
//
//        }
        
//        guard let audioUrl = Bundle.main.url(forResource: "audio1.mp3", withExtension: nil) else { return }
//        VideoEditHelper.addAudio(videoUrl: url1, audioUrl: audioUrl, outputUrl: outputUrl, removeOriginalAudio: false) { suc, err in
//
//        }
        
//        guard let wmImage = UIImage(named: "image1") else { return }
//        VideoEditHelper.addWatermark(videoUrl: url1, wmImage: wmImage, wmText: "I'm water text", wmframe: CGRect(x: 0, y: 100, width: 200, height: 100), outputUrl: outputUrl) { suc, err in
//            VideoEditHelper.saveVideo(outputUrl) { suc2, err2 in
//
//            }
//        }
        
        exporter.writeVideo(urls: url1, url2, url3, outputUrl: outputUrl) { succ, err in
            VideoEditHelper.saveVideo(outputUrl) { suc2, err2 in

            }
        }
    }

}

