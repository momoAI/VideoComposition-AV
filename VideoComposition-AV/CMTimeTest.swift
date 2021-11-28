//
//  CMTimeTest.swift
//  VideoComposition-AV
//
//  Created by momo on 2021/10/26.
//

import Foundation
import CoreMedia

struct CMTimeTest {
    static func test() {
        let time = CMTime(seconds: 0.5, preferredTimescale: 1)
        print(time.seconds)
        print(time.value)

        let time2 = CMTime(seconds: 1, preferredTimescale: 2)
        print(time2.seconds)
        print(time2.value)

        let time3 = CMTime(value: 1, timescale: 30)
        print(time3.seconds)
        print(time3.value)

        let compassTime = time2 + time3
        CMTimeShow(compassTime)

        let zero = CMTime.zero
        print(zero.seconds)
        print(zero.value)
        print(zero.timescale)

        if zero < time3 {
            print("min.....")
        }
        
        let seconds = 200.0 / 3
        //        let seconds = 66.667
        let time4 = CMTime(seconds: seconds, preferredTimescale: 3)
        CMTimeShow(time4)
        let time5 = CMTimeMultiply(time4, multiplier: 3)
        CMTimeShow(time5)
        let time6 = time5 - CMTime(value: 200, timescale: 2)
        CMTimeShow(time6)
        
        let range = CMTimeRange(start: time4, end: time5)
        CMTimeRangeShow(range)
        let range2 = CMTimeRange(start: time4, duration: time5)
        CMTimeRangeShow(range2)
    }
}
