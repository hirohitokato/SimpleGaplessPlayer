//
//  HKLAVGaplessPlayerDelegate.swift
//
//  Created by Hirohito Kato on 2015/01/15.
//  Copyright (c) 2015年 Hirohito Kato. All rights reserved.
//

import Foundation
import CoreMedia

/**
HKLAVGaplessPlayerで逐次得られるフレームを受け取るための外部公開プロトコル。
フレームデータがほしいクラスは、本プロトコルに従うことで定期的にデリゲート
メソッドが呼ばれるようになる。
*/
@objc public protocol HKLAVGaplessPlayerDelegate {

    /**
    1秒間のうち、何回player(_:didOutputSampleBuffer:)が呼ばれるかを返す。
    必ず60を割り切れる値(60,30,20,15など)を返すこと。

    :param: player HKLAVGaplessPlayerオブジェクト
    :returns: フレームレート。60fpsであれば60、30fpsの場合は30を渡す
    */
    func expectedPlaybackFramerate(player:HKLAVGaplessPlayer) -> Int

    /**
    フレームが生成されるたびに呼ばれるデリゲートメソッド。
    
    メソッドが呼ばれるタイミングは、HKLAVGaplessPlayerのフレームレートに
    依存する。

    :param: player HKLAVGaplessPlayerオブジェクト
    :param: sampleBuffer サンプルバッファ。映像のフレームデータを持つ
    */
    func player(player:HKLAVGaplessPlayer,
        didOutputSampleBuffer sampleBuffer:CMSampleBufferRef)
}
