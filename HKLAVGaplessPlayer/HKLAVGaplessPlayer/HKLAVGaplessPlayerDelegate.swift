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
    フレームが生成されるたびに呼ばれるデリゲートメソッド。
    
    メソッドが呼ばれるタイミングは、HKLAVGaplessPlayerのフレームレートに
    依存する。

    :param: player HKLAVGaplessPlayerオブジェクト
    :param: sampleBuffer サンプルバッファ。映像のフレームデータを持つ
    */
    func player(player:HKLAVGaplessPlayer,
        didOutputSampleBuffer sampleBuffer:CMSampleBufferRef)
}
