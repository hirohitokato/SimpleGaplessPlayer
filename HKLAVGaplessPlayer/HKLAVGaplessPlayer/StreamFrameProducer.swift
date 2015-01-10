//
//  StreamFrameProducer.swift
//
//  Created by Hirohito Kato on 2014/12/22.
//  Copyright (c) 2014年 Hirohito Kato. All rights reserved.
//

import Foundation
import CoreMedia
import AVFoundation

let kMaximumNumOfReaders = 3 // AVAssetReaderで事前にstartReading()しておくムービーの数

/**
*  アセット配列の中における位置（アセット位置）を表現するデータ構造
*/
private struct AssetPosition: Printable, DebugPrintable {
    var index: Int
    var time: CMTime
    init(_ index: Int, _ time: CMTime) {
        self.index=index
        self.time=time
    }
    var description: String {
        return "{i:\(self.index) t:\(self.time)}"
    }
    var debugDescription: String { return self.description }
}

/**
:class: StreamFrameProducer
:abstract:
アセットおよびそのアセットリーダーを保持していて、外部からのリクエストにより
非同期でサンプルバッファを生成する
*/
public class StreamFrameProducer: NSObject {

    /// 格納しているアセットの合計再生時間を返す
    var amountDuration: CMTime {
        let lock = ScopedLock(self)
        return _amountDuration
    }

    /// アセット全体のうち再生対象となる時間。いわゆる時間窓に相当
    var window = CMTime(value: 30, 1)

    /// 再生のスピード。1.0が通常再生、2.0だと倍速再生。負数は非対応
    var playbackRate: Float {
        return _playbackRate
    }

    /// AVAssetReaderで事前にstartReading()しておくムービーの数。
    /// 注意：多くても5個程度にしておくこと。さもないとアプリが落ちるため
    var maxNumOfReaders: Int = kMaximumNumOfReaders

    /**
    アセットを内部キューの末尾に保存する。余裕がある場合はアセットリーダーも
    同時に生成する

    :param: asset フレームの取り出し対象となるアセット
    */
    func appendAsset(asset: AVAsset) {
        // TODO: durationが判明した順でappendすると、アセットによる差でappendAssetを呼んだ順から狂う
        asset.loadValuesAsynchronouslyForKeys(["duration"]) {
            [unowned self] in
            let lock = ScopedLock(self)

            self._assets.append(asset)
            self._amountDuration += asset.duration

            // 読み込んだリーダーの数に応じて、追加でリーダーを作成する
            if self._readers.count < self.maxNumOfReaders {
                if let assetreader = AssetReaderFragment(asset:asset) {
                    self._readers.append(assetreader)
                } else {
                    NSLog("Failed to instantiate a AssetReaderFragment.")
                }
            }
        }
    }

    /**
    再生対象のアセットを１つ進める。存在しない場合は何もしない
    */
    func advanceToNextAsset() {
        if !_readers.isEmpty {
            _readers.removeAtIndex(0)
            if !_readers.isEmpty {
                _prepareNextAssetReaders()
            }
        }
    }

    /**
    生成された最新のサンプルバッファを返す。読み込まれた後、サンプルバッファは
    次に読み込まれるまでnilに

    :returns: リーダーから読み込まれたサンプルバッファ
    */
    func nextSampleBuffer() -> (sbuf:CMSampleBufferRef, presentationTimeStamp:CMTime, frameDuration:CMTime)! {
        let lock = ScopedLock(self)

        // 一度取得したらnilに変わる
        if let nextBuffer = self._prepareNextBuffer() {
            // 現在時刻を更新
            _currentPresentationTimestamp = nextBuffer.presentationTimeStamp
            return nextBuffer
        }
        return nil
    }

    /**
    アセットリーダーから読み込みを開始する

    :param: rate 再生レート
    :param: position 再生開始する位置(0.0-1.0)。Float.NaNの場合は現在位置を継続

    :returns: 読み込み開始に成功したかどうか
    */
    func startReading(rate:Float = 1.0, atPosition pos:Float? = nil) -> Bool {
        let lock = ScopedLock(self)
        if _assets.isEmpty {
            return false
        }
        var currentAsset: AVAsset? = nil
        if let pos = pos {
            if let playerInfo = _getAssetPositionOf(pos) {
                currentAsset = _assets[playerInfo.index]
                position = pos
                _currentPresentationTimestamp = playerInfo.time
            }
        } else {
            currentAsset = _readers.first?.asset
        }

        // レートが異なる場合、再生位置の指定があった場合は
        // リーダーを組み立て直してから再生準備を整える
        if rate != _playbackRate || pos != nil {
            println("cancelReading()")
            cancelReading()
        }
        _playbackRate = rate

        _prepareNextAssetReaders(initial: currentAsset, atTime:_currentPresentationTimestamp)
        return true
    }

    /**
    読み込み前のリーダーをすべて削除し、読み込みをキャンセルする。

    内部で保持しているAVAssetReaderOutputをすべて削除し、読み込み処理を
    停止する。再び読み込めるようにする場合、startReading()を呼ぶか、別のアセットを
    appendAsset()して、リーダーの準備をしておくこと
    */
    func cancelReading() {
        let lock = ScopedLock(self)
        _readers.removeAll(keepCapacity: false)
    }

    // MARK: Internals

    /// 再生位置。window内における先頭(古)〜末尾(新)を、0.0-1.0の数値で表す
    dynamic var position: Float = 1.0

    // MARK: Privates

    private var _assets = [AVAsset]() // アセット
    private var _readers = [AssetReaderFragment]() // リーダー

    private var _currentPresentationTimestamp: CMTime = kCMTimeZero

    /// アセット全体の総再生時間（内部管理用）
    private var _amountDuration = kCMTimeZero

    /// 再生レート。1.0が通常再生、2.0だと倍速再生
    private var _playbackRate: Float = 0.0

    /**
    サンプルバッファの生成
    */
    private func _prepareNextBuffer()
        -> (sbuf:CMSampleBufferRef, presentationTimeStamp:CMTime, frameDuration:CMTime)?
    {

        // サンプルバッファを生成する
        while let target = _readers.first {

            switch target.status {
            case .Reading:
                // サンプルバッファの読み込み
                let out = target.output
                if let sbuf = out.copyNextSampleBuffer() {
                    // 取得したサンプルバッファの指す時間位置が1.0を超えていなければ、
                    // 表示用としてサンプルバッファを返す
                    let pts = CMSampleBufferGetPresentationTimeStamp(sbuf) + target.startTime
                    let pos = _getRelativePositionOf(find(_assets, target.asset)!, time: pts)
                    if pos <= 1.0 + 0.02/*tolerance*/ {
                        return ( sbuf, pts, target.frameInterval )
                    }
                } else {
                    println("move to next")
                    // リーダーのサンプルバッファが枯渇した場合、または取得した
                    // サンプルバッファの位置が1.0を超えていた場合は、次のムービーへ移動する
                    _readers.removeAtIndex(0)
                    _currentPresentationTimestamp = kCMTimeZero
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0)) {
                        [unowned self] in
                        self._prepareNextAssetReaders()
                    }
                }
            case .Completed:
                // AVAssetReaderは.Reading状態でcopyNextSampleBufferを返した
                // 次のタイミングで.Completedに遷移するため、ここには来ないはず
                _readers.removeAtIndex(0)
                _currentPresentationTimestamp = kCMTimeZero
            default:
                NSLog("Invalid state[\(Int(target.status.rawValue))]. Something is wrong.")
                _readers.removeAtIndex(0)
                _currentPresentationTimestamp = kCMTimeZero
            }
        }
        return nil
    }

    private func _prepareNextAssetReaders(initial: AVAsset? = nil, atTime time: CMTime = kCMTimeZero) {
        let lock = ScopedLock(self)

        // 読み込み済みリーダーの数が上限になっていれば何もしない
        if (_readers.count >= maxNumOfReaders) { return }

        // アセットをどこから読み込むかを決定する
        let startIndex = (initial == nil) ? 0 : find(_assets, initial!) ?? 0
        // startTimeの設定は初回のみ有効
        var startTime = time

        // リーダーが空の場合、まず先頭のアセットを読み込む
        if _readers.isEmpty && startIndex < _assets.count {
            if let assetreader = AssetReaderFragment(asset:_assets[startIndex],
                rate:_playbackRate, startTime:startTime)
            {
                startTime = kCMTimeZero
                _readers.append(assetreader)
            } else {
                NSLog("Failed to instantiate a AssetReaderFragment.")
            }
        }

        // 読み込みしていないアセットがあれば読み込む
        outer: for (i, asset) in enumerate(_assets[startIndex..<_assets.count]) {

            let actualIndex = i + startIndex
            // 登録済みの最後のアセットを見つけて、それ以降のアセットを
            // 追加対象として読み込む
            if _readers.last?.asset === asset && actualIndex+1 < _assets.count {
                for target_asset in _assets[actualIndex+1..<_assets.count] {

                    // 読み込み済みリーダーの数が上限になれば処理終了
                    if (_readers.count >= maxNumOfReaders) {
                        break outer
                    }

                    if let assetreader = AssetReaderFragment(asset:target_asset,
                        rate:_playbackRate, startTime:startTime)
                    {
                        startTime = kCMTimeZero
                        _readers.append(assetreader)
                    } else {
                        NSLog("Failed to instantiate a AssetReaderFragment.")
                        break outer
                    }
                }
            }
        }
    }
}

/**
*  再生位置を決めるための処理
*/
private extension StreamFrameProducer {
    // MARK: Internals
    /**
    指定した再生位置(0.0-1.0)に対するアセット位置を計算して返す

    :param: position 再生位置(0.0-1.0)

    :returns: 指定した再生位置に相当するアセット位置
    */
    func _getAssetPositionOf(position: Float) -> AssetPosition? {
        let lock = ScopedLock(self)

        if _assets.isEmpty || _readers.isEmpty { return nil }

        // 1) 1.0のアセット位置を算出する
        if let one = _getWindowEnd() {

            // 再生位置を1.0位置からのオフセット時間に変換する
            let offset = ( window * (1.0 - position) ) * -1.0

            // 2) 算出した1.0位置からのオフセットを引いたアセット位置を探す
            if let result = _findAsset(_assets, from: one, offset: offset) {

                // 算出した値なので、端数が出ないよう1/600スケールに丸めて返す
                let time = CMTimeConvertScale(result.time, 600, .RoundHalfAwayFromZero)
                return AssetPosition(result.index, time)
            }
        }
        return nil
    }

    /**
    現在の再生位置を元に、指定したアセット位置が示す再生位置を返す

    :param: index アセットのインデックス。_assets内のインデックス番号のこと。
    :param: time  アセット上の時間

    :returns: 再生位置(0.0-1.0)。値域外の場合はnilを返す
    */
    func _getRelativePositionOf(index:Int, time:CMTime) -> Float? {
        let target = AssetPosition(index, time)

        /*
        「offset = window * position」であることを利用して位置を求める

        offset = window * position
        → position = offset/window
        (※ offset = t(target) - t0 なので)
        → position = (t(target) - t0)/window
        (※ t0 = t1 - window なので)
        → position = (t(target) - t1 + window)/window
        ∴ position = (window + target - t1) / window
        */
        if let t1 = _getWindowEnd() {
            let numer = window + _getDurationBetweenAssets(from:target, to:t1)
            let position = numer.f / window.f
            return position
        }
        return nil
    }
    
    // MARK: Privates
    /**
    Window末尾(=再生位置が1.0)のときのアセットと、そのアセット位置を計算して返す

    :returns: _assets内の、position=1.0となるアセット位置
    */
    func _getWindowEnd() -> AssetPosition? {

        if _assets.isEmpty || _readers.isEmpty { return nil }

        // 現在の再生場所を起点にしてposition=1.0地点を探索する
        if let i_t1 = find(self._assets, _readers.first!.asset) {

            let t1 = AssetPosition(i_t1, _currentPresentationTimestamp)
            let offset = window * (1.0 - position)

            if let windowEnd = _findAsset(_assets, from: t1, offset: offset) {
                return windowEnd
            } else {
                // 見つからなかった場合、全アセットの最後端を1.0として扱う
                return AssetPosition(_assets.count-1, _assets.last!.duration)
            }
        }
        return nil
    }

    /**
    アセット位置から指定時間ぶんオフセットした位置がどこにあるかを調べる。
    該当するアセットが無い場合はnilを返す

    :param: assets 探索対象のアセット列
    :param: index  探索基点となるアセット位置(インデックス, 時刻)
    :param: offset オフセット時間

    :returns: アセット位置(インデックス, 時刻)
    */
    func _findAsset(assets:[AVAsset], from:AssetPosition, offset:CMTime)
        -> AssetPosition?
    {
        if from.index < 0 || from.index >= assets.count { return nil }
        if offset.isZero { return from }

        // アセット列のうち、どの範囲を探すか
        let targets = offset.isSignMinus ?
            reverse(assets[0...from.index]) : Array(assets[from.index..<assets.count])

        // 繰り返し処理を簡略化するためにゲタを履かせる
        var offset = offset + (offset.isSignMinus ?
            (assets[from.index].duration - from.time) : from.time)

        for (i, asset) in enumerate(targets) {

            if offset <= asset.duration {
                return offset.isSignMinus ?
                    AssetPosition(from.index - i, asset.duration - offset) :
                    AssetPosition(from.index + i, offset)
            }
            offset -= asset.duration
        }
        return nil
    }

    /**
    複数アセットを跨いだ、アセット間の時間を求める。from>toの場合は負値が返る。

    :param: from lhs 起点となるアセット位置
    :param: to rhs 終点となるアセット位置

    :returns: 指定期間内のduration.
    */
    func _getDurationBetweenAssets(from lhs: AssetPosition, to rhs: AssetPosition) -> CMTime {
            var sumTime: CMTime = kCMTimeZero

        // lhsとrhsが同じアセットの場合は、単純に時間の差を返す
            if lhs.index == rhs.index {
                return lhs.time - rhs.time
            }

            // 中間のアセットのduration合計を求める
            let intermediates = (lhs.index < rhs.index) ?
                _assets[lhs.index+1 ..< rhs.index] : _assets[rhs.index+1 ..< lhs.index]
            sumTime = intermediates.reduce(sumTime) { $0 + $1.duration }

            if lhs.index < rhs.index {
                // (lhsの残り時間 + rhs)の符号反転
                sumTime += (_assets[lhs.index].duration - lhs.time) + rhs.time
                return kCMTimeZero - sumTime
            } else {
                // lhs + rhsの残り時間
                sumTime += lhs.time + (_assets[rhs.index].duration - rhs.time)
                return sumTime
            }
        }

}