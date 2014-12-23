//
//  HKLAVGaplessPlayer.swift
//
//  Created by Hirohito Kato on 2014/12/22.
//  Copyright (c) 2014年 Hirohito Kato. All rights reserved.
//

import Foundation
import CoreMedia
import AVFoundation

/**
:class: HKLAVGaplessPlayer
:abstract:
アセットおよびそのアセットリーダーを保持していて、外部からのリクエストにより
非同期でサンプルバッファを生成する
*/
class HKLAVGaplessPlayer: NSObject {
    weak var playerView: HKLGLPixelBufferView! = nil

    /**
    アセットを内部キューの末尾に追加する

    :param: asset 再生対象となるアセット
    */
    func appendAsset(asset: AVAsset) {
        if displayLink == nil {
            // DisplayLinkを作成
            displayLink = CADisplayLink(target: self, selector: "displayLinkCallback:")
            displayLink.frameInterval = 60 / kFrameRate
            displayLink.paused = true
            dispatch_sync(dispatch_get_main_queue()) {
                self.displayLink.addToRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
            }
        }

        _producer.appendAsset(asset)
    }

    func play() {
        displayLink.paused = false
        _lastTimestamp = CACurrentMediaTime()
        _remainingPresentationTime = 0.0
    }
    func pause() {
        displayLink.paused = true
        _lastTimestamp = CACurrentMediaTime()
        _remainingPresentationTime = 0.0
    }

    // MARK: Private variables & methods
    private var displayLink: CADisplayLink!

     /// フレームの保持と生成を担当するクラス
    let _producer: StreamFrameProducer = StreamFrameProducer()

    /// 最後にピクセルバッファを取得した時刻
    private var _lastTimestamp: CFTimeInterval = 0
    /// 表示に使う時間の残り時間
    private var _remainingPresentationTime: CFTimeInterval = 0.0

    // MARK: … CADisplayLink callback function

    /**
    CADisplayLinkのコールバック関数。frameInterval間隔で、画面更新のタイミングで呼ばれる

    :param: displayLink CADisplayLink。現在時刻や直近の処理時間を取得できる
    */
    @objc func displayLinkCallback(displayLink: CADisplayLink) {
        // 表示対象の時刻を計算
        let nextOutputHostTime = displayLink.timestamp + displayLink.duration

        // 時間を消費
        _remainingPresentationTime -= displayLink.duration

        // フレームの表示時間を、消費したぶんだけ補充する
        while _remainingPresentationTime < 0.0 {

            // サンプルバッファの取得
            if let (sbuf, duration) = _producer.nextSampleBuffer() {
                if let imgbuf = CMSampleBufferGetImageBuffer(sbuf) {

                    // ピクセルバッファの最新取得時刻を更新し、
                    // 得られた時間を表示可能時間として補充する
                    _lastTimestamp = displayLink.timestamp
                    _remainingPresentationTime += CMTimeGetSeconds(duration)

                    // 表示処理はループの最後で1回だけ実行
                    if _remainingPresentationTime >= 0.0 {
                        playerView?.displayPixelBuffer(imgbuf)
                    }
                }
            } else {
                // サンプルバッファが得られなかった場合、今回の処理では何もしない
                break
            }
        }

        if displayLink.timestamp - _lastTimestamp > 0.5 {
            displayLink.paused = true
            println("Paused display link in order to save energy.")
        }
    }
}

