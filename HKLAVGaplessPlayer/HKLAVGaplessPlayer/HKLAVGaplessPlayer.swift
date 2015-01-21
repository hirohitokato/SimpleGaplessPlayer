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

/// 再生時のrate指定に使う特殊値。この値を指定した場合、アセットの
/// 持つ1フレームをそのまま1フレームとして扱う
public let HKLAVGaplessPlayerPlayRateAsIs: Float = FLT_MIN

/**
:class: HKLAVGaplessPlayer
:abstract: アセットおよびそのアセットリーダーを保持していて、外部からのリクエストにより非同期でサンプルバッファを生成する
*/
public class HKLAVGaplessPlayer: NSObject {
    public weak var delegate: HKLAVGaplessPlayerDelegate! = nil

    override public init() {
        super.init()

        // DisplayLinkを作成
        _displayLink = CADisplayLink(target: self, selector: "_displayLinkCallback:")
        _displayLink.frameInterval = 60 / kPlaybackFrameRate
        _displayLink.paused = true
        dispatch_async(dispatch_get_main_queue()) {
            self._displayLink.addToRunLoop(NSRunLoop.mainRunLoop(), forMode: NSDefaultRunLoopMode)
        }
    }

    /**
    Appends given asset to the end of queue.

    :param: asset The asset to be appended.
    */
    public func appendAsset(asset: AVAsset) {
        _producer.appendAsset(asset)
    }

    /**
    Removes a given asset from the queue.
    
    If asset is currently playing, this also has the effect as advanceToNextAsset.

    :param: asset The asset to be removed.
    :returns: true if the asset is removed from the queue or false if it did not.
    */
    public func removeAsset(asset: AVAsset) -> Bool {
        return _producer.removeAsset(asset)
    }

    /**
    Removes all the assets from the queue.

    This has the side-effect of stopping playback by the player.
    */
    public func removeAllAssets() {
        return _producer.removeAllAssets()
    }

    /**
    Ends playback of the current asset and initiates playback of the next asset in the player's queue.
    */
    public func advanceToNextAsset() {
        _producer.advanceToNextAsset()
    }

    /**
    The current rate of playback.

    A value of 0.0 means pauses the video, while a value of 1.0 play at the natural rate of the current item. Negative rate value ranges are not  supported.
    */
    public var rate: Float { return _producer.playbackRate }

    /// The current position(0.0-1.0) of playback.
    public var position: Float { return _producer.position }

    /**
    プレーヤーを再生開始

    rateに「HKLAVGaplessPlayerPlayRateAsIs」を指定した場合、アセット
    がもともと提供するフレームをそのまま再生に使う。つまり、60fpsで再生する
    環境であれば、240fpsのムービーだと1/4倍速、30fpsだと2倍速の再生になる。

    :param: rate     The current rate of playback. Default value is 1.0(the natural rate)。0.0 means pause.
    :param: position The position where player starts playback. It is that in time window(0.0-1.0). Default value is nil(play from current position)
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
    Pauses playback. This is the same as setting rate to 0.0.
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
    true if the player is in playing.
    */
    public var isPlaying: Bool { return !_displayLink.paused }

    /** The automatic vs. nonautomatic repeat state of the player.

    If true, the player plays assets repeatedly in the time window.
    The default value for this property is false.
    */
    public var autoRepeat: Bool {
        get { return _producer.autoRepeat }
        set { _producer.autoRepeat = newValue }
    }

    /**
    */
    public var playbackMode: PlaybackMode {
        get { return _producer.playbackMode }
        set {
            if (_producer.playbackMode != newValue) { pause() }
            _producer.playbackMode = newValue
        }
    }

    // MARK: Private variables & methods
    private var _displayLink: CADisplayLink!

     /// フレームの保持と生成を担当するクラス
    let _producer: StreamFrameProducer = StreamFrameProducer()

    /// 最後にピクセルバッファを取得した時刻
    private var _lastTimestamp: CFTimeInterval = 0
    /// 表示に使う時間の残り時間
    private var _remainingPresentationTime: CFTimeInterval = 0.0
    private var _previousTimestamp: CFTimeInterval = 0.0

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
            _displayLink.paused = true
            _lastTimestamp = CACurrentMediaTime()
            _remainingPresentationTime = 0.0
            _previousTimestamp = 0.0
            _playbackRate = CFTimeInterval(rate)
        } else {

            // 指定レートで再生開始
            if _producer.startReading(rate: rate, atPosition: position) {
                _lastTimestamp = CACurrentMediaTime()
                _remainingPresentationTime = 0.0
                _previousTimestamp = 0.0
                _displayLink.paused = false
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

        // 表示時間を計算
        let now = CACurrentMediaTime()
        var delta: CFTimeInterval
        if _previousTimestamp.isZero {
            delta = displayLink.duration * CFTimeInterval(displayLink.frameInterval)
        } else {
            delta = now - _previousTimestamp
        }
        _previousTimestamp = now

        // 時間を供給
        _remainingPresentationTime += delta

        // フレームの表示可能時間を、供給されたぶんだけ消費する
        while _remainingPresentationTime > 0.0 {

            // サンプルバッファの取得
            if let (sbuf, _, duration) = _producer.nextSampleBuffer() {

                // サンプルバッファの最新取得時刻を更新した上で、
                // 得られたプレゼンテーション時間を消費する
                _lastTimestamp = displayLink.timestamp

                if duration == FrameDurationIsAsIs {
                    // HKLAVGaplessPlayerPlayRateAsIsの場合は1VSYNC==1フレームとなる
                    _remainingPresentationTime = 0.0
                } else {
                    _remainingPresentationTime -= duration.f64
                }

                // 表示処理はループの最後で1回だけ実行
                if _remainingPresentationTime <= 0.0 {
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

internal let FrameDurationIsAsIs: CMTime = kCMTimeNegativeInfinity
