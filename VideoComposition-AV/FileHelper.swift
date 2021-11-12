//
//  DirectoreHelper.swift
//  VideoComposition-AV
//
//  Created by luxu on 2021/11/10.
//

import Foundation

struct FileHelper {
    
    /// 创建文件路径（如存在直接返回）
    /// - Parameters:
    ///   - pathDirectory: 目录
    ///   - path: 文件名
    /// - Returns: 完整路径
    public static func createDirectory(pathDirectory: FileManager.SearchPathDirectory, path: String) -> URL? {
        let documentPath = FileManager.default.urls(for: pathDirectory, in: .userDomainMask).first
        guard var result = documentPath else { return nil }
        result = result.appendingPathComponent(path)
        let exists = FileManager.default.fileExists(atPath: result.path)
        if !exists {
            do {
                try FileManager.default.createDirectory(atPath: result.path, withIntermediateDirectories: true, attributes: nil)
            } catch {
                return nil
            }
        }
        
        return result
    }
    
    public static func uuid() -> String {
        let theUUID = CFUUIDCreate(nil)
        let cfStr = CFUUIDCreateString(nil, theUUID)
        return cfStr as String? ?? ""
    }
}
