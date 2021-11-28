//
//  AVAssetTest.swift
//  VideoComposition-AV
//
//  Created by momo on 2021/10/29.
//

import Foundation
import AVFoundation

struct AVAssetTest {
    static func test() {
        // load http url
        let url = URL(string: "https://test-img.fooww.com/groupxyz/M01/00/93/rBFpk2CLyBeALtPXAAi0ixJ8eVk433.mp4")
    
        guard let videoUrl = url else { return }
        let asset = AVURLAsset(url: videoUrl)
        
        let duration = asset.duration
        CMTimeShow(duration)
        
        let keys = ["duration"]
        asset.loadValuesAsynchronously(forKeys: keys) {
            let status = asset.statusOfValue(forKey: "duration", error: nil)
            print(status.rawValue)
        }
        
        // load file url
        let url2 = Bundle.main.url(forResource: "video2.MP4", withExtension: nil)
        guard let videoUrl = url2 else { return }
        let asset2 = AVURLAsset(url: videoUrl)
        
        let duration2 = asset2.duration
        CMTimeShow(duration2)
        
        // 65types utis
        let types = AVURLAsset.audiovisualTypes()
        print(types)
        
        // 44 mimetypes
        let mimetypes = AVURLAsset.audiovisualMIMETypes()
        print(mimetypes)
        
        print(asset.preferredRate, asset.preferredVolume)
        print(asset2.preferredRate, asset2.preferredVolume)
        
        // track
        // all tracks
        let tracks = asset.tracks
        let tracks2 = asset2.tracks
        print(tracks,tracks2)
        for track in tracks {
            print(track.mediaType)
        }
        
        // appoint mediatype tracks
        let videoTracks = asset.tracks(withMediaType: .video)
        print(videoTracks)
        
        let groups = asset2.trackGroups
        for group in groups {
            print(group.trackIDs)
        }
        
        // Metadata
        let createDate = asset2.creationDate
        print(createDate?.stringValue ?? "")
        print(asset2.lyrics ?? "")
        let cmetadata = asset2.commonMetadata
        let metadata = asset2.metadata
        print(cmetadata,metadata)
        
        print(asset.containsFragments, asset2.containsFragments)
        print(asset2.isPlayable,asset2.isExportable,asset2.isReadable,asset2.isComposable,asset2.isCompatibleWithSavedPhotosAlbum)
    }
}
