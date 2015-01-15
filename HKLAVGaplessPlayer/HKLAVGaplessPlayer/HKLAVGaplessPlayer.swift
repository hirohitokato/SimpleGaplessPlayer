//
//  HKLAVGaplessPlayer.swift
//
//  Created by Hirohito Kato on 2014/12/22.
//  Copyright (c) 2014年 Hirohito Kato. All rights reserved.
//

import Foundation
import CoreMedia
import AVFoundation


let kPlaybackFrameRate: Int = 60
let kFrameInterval: Float = 1.0/Float(kPlaybackFrameRate)

/// 再生時のrate指定に使う特殊値。この値を指定した場合、アセットの
/// 持つ1フレームをそのまま1フレームとして扱う
public let HKLAVGaplessPlayerPlayRateAsIs: Float = FLT_MIN
internal let FrameDurationIsAsIs: CMTime = kCMTimeNegativeInfinity
/**
:class: HKLAVGaplessPlayer
:abstract:
アセットおよびそのアセットリーダーを保持していて、外部からのリクエストにより
非同期でサンプルバッファを生成する
*/
public class HKLAVGaplessPlayer: NSObject {
    public weak var delegate: HKLAVGaplessPlayerDelegate! = nil

    override public init() {
        super.init()

        // DisplayLinkを作成
        displayLink = CADisplayLink(target: self, selector: "_displayLinkCallback:")
        displayLink.frameInterval = 60 / kPlaybackFrameRate
        displayLink.paused = true
        dispatch_async(dispatch_get_main_queue()) {
            self.displayLink.addToRunLoop(NSRunLoop.mainRunLoop(), forMode: NSDefaultRunLoopMode)
        }

        _producer.addObserver(self, forKeyPath: "position", options: .New, context: &_positionContext)
    }

    deinit {
        _producer.removeObserver(self, forKeyPath: "position", context: &position)
    }

    /**
    アセットを内部キューの末尾に追加する

    :param: asset 再生対象となるアセット
    */
    public func appendAsset(asset: AVAsset) {
        _producer.appendAsset(asset)
    }

    /**
    次のアセットへ再生位置を進める
    */
    public func advanceToNextAsset() {
        _producer.advanceToNextAsset()
    }

    /// 現在の再生レートを返す
    public var rate: Float {
        return _producer.playbackRate
    }

    /// 現在の再生位置を返す
    dynamic public private(set) var position: Float = 1.0

    /**
    プレーヤーを再生開始

    rateに「HKLAVGaplessPlayerPlayRateAsIs」を指定した場合、アセット
    がもともと提供するフレームをそのまま再生に使う。つまり、60fpsで再生する
    環境であれば、240fpsのムービーだと1/4倍速、30fpsだと2倍速の再生になる。

    :param: rate     再生レート。デフォルト:1.0(等倍速再生)。0.0は停止。
    :param: position 再生位置(0.0-1.0) デフォルト:nil(現在位置から再生)
    */
    public func play(rate: Float, position:Float? = nil) {
        _setRate(rate, position:position)
    }
    /**
    プレーヤーを等倍速で再生開始する。
    
    :discussion: （play(rate:,position:)がデフォルト値を持つため、publicにしてもObjective-Cではアクセスできない。そのため、コンビニエンスメソッドとしてplay()を用意した）
    */
    public func play() {
        _setRate(1.0, position:nil)
    }
    /**
    再生の一時停止。再開可能
    */
    public func pause() {
        _setRate(0.0)
    }
    /**
    再生停止。再開は最初から
    */
    public func stop() {
        pause()
        _producer.cancelReading()
    }
    /**
    現在再生中かどうか
    */
    public var isPlaying: Bool {
        return !displayLink.paused
    }

    // MARK: Private variables & methods
    private var displayLink: CADisplayLink!

     /// フレームの保持と生成を担当するクラス
    let _producer: StreamFrameProducer = StreamFrameProducer()

    /// 最後にピクセルバッファを取得した時刻
    private var _lastTimestamp: CFTimeInterval = 0
    /// 表示に使う時間の残り時間
    private var _remainingPresentationTime: CFTimeInterval = 0.0

    /// 再生速度の係数。1.0が通常速度、2.0だと倍速になる
    private var _playbackRate : CFTimeInterval = 1.0

    private var _positionContext = 0

    /**
    プレーヤーを再生開始

    :param: rate     再生レート。デフォルト:1.0(等倍速再生)。0.0は停止
    :param: position 再生位置(0.0-1.0) デフォルト:nil(現在位置から再生)
    */
    private func _setRate(rate:Float, position:Float? = nil) {
        if rate < 0.0 {
            assert(false, "Unable to set a negative value(\(rate)) to playback rate")
        }
        if position != nil && (position < 0.0 || position > 1.0) {
            assert(false, "position(\(rate)) must be 0.0...1.0")
        }

        if rate == 0 {

            // 一時停止
            displayLink.paused = true
            _lastTimestamp = CACurrentMediaTime()
            _remainingPresentationTime = 0.0
            _playbackRate = CFTimeInterval(rate)
        } else {

            // 指定レートで再生開始
            if _producer.startReading(rate: rate, atPosition: position) {
                _lastTimestamp = CACurrentMediaTime()
                _remainingPresentationTime = 0.0
                displayLink.paused = false
                _playbackRate = CFTimeInterval(rate)
            }
        }
    }
}

// MARK: … CADisplayLink callback function
extension HKLAVGaplessPlayer {

    /**
    CADisplayLinkのコールバック関数。frameInterval間隔で、画面更新のタイミングで呼ばれる

    :param: displayLink CADisplayLink。現在時刻や直近の処理時間を取得できる
    */
    @objc func _displayLinkCallback(displayLink: CADisplayLink) {

        // 表示対象の時刻を計算（再生レートも加味）
        let callbackDuration =
        displayLink.duration * CFTimeInterval(displayLink.frameInterval)
        //let nextOutputHostTime = displayLink.timestamp + callbackDuration

        // 時間を消費
        _remainingPresentationTime -= callbackDuration

        // フレームの表示時間を、消費したぶんだけ補充する
        while _remainingPresentationTime < 0.0 {

            // サンプルバッファの取得
            if let (sbuf, _, duration) = _producer.nextSampleBuffer() {

                // ピクセルバッファの最新取得時刻を更新し、
                // 得られた時間を表示可能時間として補充する
                _lastTimestamp = displayLink.timestamp

                if duration == FrameDurationIsAsIs {
                    // HKLAVGaplessPlayerPlayRateAsIsの場合は1VSYNC==1フレームとなる
                    _remainingPresentationTime = 0.0
                } else {
                    _remainingPresentationTime += duration.f64
                }

                // 表示処理はループの最後で1回だけ実行
                if _remainingPresentationTime >= 0.0 {
                    delegate?.player(self, didOutputSampleBuffer: sbuf)
                }
            } else {
                // サンプルバッファが得られなかった場合、今回の処理では何もしない
                println("nil")
                break
            }
        }

        if displayLink.timestamp - _lastTimestamp > 0.5 {
            displayLink.paused = true
            println("Paused display link in order to save energy.")
        }
    }
}

// MARK: … KVO
extension HKLAVGaplessPlayer {
    public override func observeValueForKeyPath(keyPath: String,
        ofObject object: AnyObject, change: [NSObject : AnyObject],
        context: UnsafeMutablePointer<Void>)
    {
        if context == &_positionContext {
            position = _producer.position
        } else {
            super.observeValueForKeyPath(keyPath, ofObject: object, change: change, context: context)
        }
    }
}