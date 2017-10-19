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
登録したアセットをどのように再生するか。

Streaming/Playbackの指定により、アセットの再生状況と時間窓の扱いが変わる。

- Streaming: ストリーミング(次々とアセットが登録されることを想定)。現在の再生位置で時間窓が変化する
- Playback:  再生(固定のアセットを再生することを想定)。全アセットの先頭/末尾が常に時間窓の先頭/末尾となる
*/
public enum PlaybackMode {
    case Streaming
    case Playback
}

/**
:class: StreamFrameProducer
:abstract:
アセットおよびそのアセットリーダーを保持していて、外部からのリクエストにより
非同期でサンプルバッファを生成する
*/
class StreamFrameProducer: NSObject {

    init(decodeQueue: dispatch_queue_t) {
        _decodeQueue = decodeQueue
        super.init()
    }
    /// 格納しているアセットの合計再生時間を返す
    var amountDuration: CMTime {
        get {
            var duration: CMTime = kCMTimeZero
            sync { me in
                duration = me._amountDuration
            }
            return duration
        }
    }

    /**
    アセット全体のうち再生対象となる時間。いわゆる時間窓に相当。
    playbackModeがStreamingの場合は指定した時間を表し、Playbackの場合は
    アセット全体の時間を表す
    */
    var window: CMTime {
        get {
            switch playbackMode {
            case .Streaming: return _window
            case .Playback:  return _amountDuration
            }
        }
        set(newWindow) { _window = newWindow }
    }

    /// 再生のスピード。1.0が通常再生、2.0だと倍速再生。負数は非対応
    var playbackRate: Float { return _playbackRate }

    /// アセットの再生方法。詳細はPlaybackModeを参照のこと。
    var playbackMode: PlaybackMode = .Playback {
        didSet(oldMode) {
            // 異なる値がセットされたら、状態をリセットする
            if (oldMode != playbackMode) {
                cancelReading(async: false)
                removeAllAssets()
            }
        }
    }

    /// Auto-RepeatモードのON/OFF。ONの場合、アセット末尾にたどり着いたらwindow先頭に戻る
    var autoRepeat: Bool = true {
        willSet {
            if newValue == true && playbackMode == .Streaming {
                NSLog("autoRepeat is available if the playback mode is Playback. Though the value is set, it's ignored.")
            }
        }
    }

    /// windowの範囲外(== position < 0.0)になったアセットを自動的に取り除くかどうか
    var autoRemoveOutdatedAssets: Bool = true

    /// AVAssetReaderで事前にstartReading()しておくムービーの数。
    /// 注意：多くても5個程度にしておくこと。さもないとアプリが落ちるため
    var maxNumOfReaders: Int = kMaximumNumOfReaders

    func assets() -> [AVAsset] {
        var assets = [AVAsset]()
        _assets.forEach { assets.append($0.asset) }
        return assets
    }

    /**
    アセットを内部キューの末尾に保存する。

    :param: asset フレームの取り出し対象となるアセット
    */
    func appendAsset(asset: AVAsset) {
        async { me in
            let holder = AssetHolder(asset) { duration in
                me._amountDuration += duration
                return
            }
            me._assets.append(holder)
        }
    }

    /**
    assetで示すアセットをアセット群から取り除く

    :param: asset 削除したいアセット
    */
    func removeAsset(asset: AVAsset) {
        sync { me in

            if let index = me._assets.index(where: { $0.asset == asset }) {

                me._amountDuration -= asset.duration
                me._assets.remove(at: index)

                // リーダーとしてスケジュール済みの場合、リーダーからも削除する
                if let readerIndex = me._readers.index(where: { $0.asset == asset }) {

                    me._readers.remove(at: readerIndex)

                    // 再生中のムービーを削除する場合、advanceToNextAsset()を呼ぶ
                    if readerIndex == 0 {
                        me.advanceToNextAsset(shouldLock: false)
                    }
                }
            }
        }
    }

    /**
    アセットをすべて削除する
    */
    func removeAllAssets() {
        sync { me in
            me.cancelReading(async: false)
            me._assets.removeAll(keepingCapacity: false)
            me._resetPosition()
            me._amountDuration = kCMTimeZero
        }

    }

    /**
    再生対象のアセットを１つ進める。存在しない場合は何もしない
    */
    func advanceToNextAsset(shouldLock: Bool = true) {
        let operation = { [unowned self] () -> Void in
            if !self._readers.isEmpty {
                // autoRemoveOutdatedAssetsが有効ならばwindow外の古いアセットを削除
                if self.autoRemoveOutdatedAssets {
                    if let assetPos = self._getAssetPosition(of: 0.0) {
                        // 合計時間も減じておく
                        let duration = self._assets[0..<assetPos.index].reduce(kCMTimeZero) { $0 + $1.duration }
                        self._assets.removeSubrange(0..<assetPos.index)
                        self._amountDuration -= duration
                    }
                }

                // 時間がリセットされる前に0.0位置の値を保持しておく(必要なときだけ)
                let zeroPos = (self._readers[0].asset == self._assets.last?.asset && self.autoRepeat) ?
                    self._getAssetPosition(of: 0.0) : nil

                // 現在再生中のリーダーを削除
                let removed = self._readers.remove(at: 0)
                self._currentPresentationTimestamp = kCMTimeZero

                // アセットが残っているか、またはplaybackモードかつautorepeat==trueなら次を読み込む
                if removed.asset != self._assets.last?.asset {
                    if let removedIndex = self._assets.index(where: { $0.asset == removed.asset }) {
                        self._prepareNextAssetReaders(initial: self._assets[removedIndex+1].asset)
                    }
                } else if self.autoRepeat && self.playbackMode == .Playback {

                    // autorepeatで先頭に戻る場合、時間窓の0.0位置から読み込む

                    self._position = 0.0
                    if let zeroPos = zeroPos {
                        self._prepareNextAssetReaders(initial: self._assets[zeroPos.index].asset, atTime: zeroPos.time)
                    } else {
                        self._prepareNextAssetReaders()
                    }
                }
            }
        }

        if shouldLock {
            async { me in operation() }
        } else {
            operation()
        }
    }

    /**
    生成された最新のサンプルバッファを返す。読み込まれた後、サンプルバッファは
    次に読み込まれるまでnilに

    :returns: リーダーから読み込まれたサンプルバッファ
    */
    func nextSampleBuffer() -> (sbuf:CMSampleBuffer, frameDuration:CMTime)! {
        var result: (sbuf:CMSampleBuffer, frameDuration:CMTime)! = nil
        sync { me in
            if me._currentSampleBuffer != nil {
                result = me._currentSampleBuffer
                me._currentSampleBuffer = nil
            } else {
                result = me._prepareNextBuffer()
            }

            // 次のサンプルバッファを非同期で用意しておく
            me.async { me in
                me._currentSampleBuffer = me._prepareNextBuffer()
            }
        }
        return result
    }

    /**
    アセットリーダーから読み込みを開始する

    :param: rate 再生レート
    :param: position 再生開始する位置(0.0-1.0)。Float.NaNの場合は現在位置を継続

    :returns: 読み込み開始に成功したかどうか
    */
    func startReading(rate:Float = 1.0, atPosition pos:Float? = nil) -> Bool {
        var result = false
        sync { me in
            if me._assets.isEmpty {
                return
            }
            var currentAsset: AVAsset? = nil
            if let pos = pos {
                if let playerInfo = me._getAssetPosition(of: pos) {

                    if me.autoRepeat &&
                        me._assets[playerInfo.index].asset == me._assets.last!.asset &&
                        playerInfo.time.isNearlyEqualTo(me._assets.last!.duration, CMTimeMake(1,10))
                    {
                        // 得られたアセット位置が全体の末尾かつautoRepeat=trueの場合、
                        // 窓時間の先頭に戻る
                        let zero = me._getAssetPosition(of: 0.0) ?? AssetPosition(0, kCMTimeZero)

                        currentAsset = me._assets[zero.index].asset
                        me._currentPresentationTimestamp = zero.time
                        me._position = me._getPosition(of: 0, time: kCMTimeZero)!
                    } else {
                        currentAsset = me._assets[playerInfo.index].asset
                        me._position = pos
                        me._currentPresentationTimestamp = playerInfo.time
                    }
                }
            } else {
                currentAsset = me._readers.first?.asset
            }

            // レートが異なる場合、再生位置の指定があった場合は
            // リーダーを組み立て直してから再生準備を整える
            if rate != me._playbackRate || pos != nil {
                me.cancelReading(async: false)
            }
            me._playbackRate = rate
            me._prepareNextAssetReaders(initial: currentAsset, atTime:me._currentPresentationTimestamp)

            result = true
        }
        return result
    }

    /**
    読み込み前のリーダーをすべて削除し、読み込みをキャンセルする。

    内部で保持しているAVAssetReaderOutputをすべて削除し、読み込み処理を
    停止する。再び読み込めるようにする場合、startReading()を呼ぶか、別のアセットを
    appendAsset()して、リーダーの準備をしておくこと
    */
    func cancelReading(async asyncFlag: Bool=true) {
        let operation = { [unowned self] ()->Void in
            self._readers.removeAll(keepingCapacity: false)
        }
        if asyncFlag {
            async { me in operation() }
        } else {
            operation()
        }
    }

    /// 再生位置。window内における先頭(古)〜末尾(新)を、0.0-1.0の数値で表す
    var position: Float { return _position }
    private var _position: Float = 1.0

    // MARK: Privates

    private let _decodeQueue: dispatch_queue_t
    private var _assets = [AssetHolder]() // アセット
    private var _readers = [AssetReaderFragment]() // リーダー

    private var _currentSampleBuffer: (sbuf:CMSampleBuffer, frameDuration:CMTime)! = nil
    private var _currentPresentationTimestamp: CMTime = kCMTimeZero


    /// アセット全体の総再生時間（内部管理用）
    private var _amountDuration = kCMTimeZero
    private var _window = CMTime(value: 5, 1)

    /// 再生レート。1.0が通常再生、2.0だと倍速再生
    private var _playbackRate: Float = 1.0

    /**
    現在位置をリセットする
    */
    private func _resetPosition() {
        switch playbackMode {
        case .Streaming:
            _position = 1.0
        case .Playback:
            _position = 0.0
        }
    }

    /**
    サンプルバッファの生成
    */
    private func _prepareNextBuffer()
        -> (sbuf:CMSampleBuffer, frameDuration:CMTime)?
    {
        // サンプルバッファを生成する
        while let target = _readers.first {

            // サンプルバッファの読み込み
            if let frameData = target.copyNextFrame() {

                // 現在のプレゼンテーション時間を更新
                let pts = target.currentPresentationTimestamp
                _currentPresentationTimestamp = pts

                switch playbackMode {
                case .Streaming:
                    // 1.0位置が最終アセット末尾に到達している場合はpositionを移動
                    if _readers.first!.asset == _assets.last!.asset &&
                        _assets.last!.asset.duration == _getWindowEnd()?.time
                    {
                        if let pos = _getPosition(of: _assets.index(where: {$0.asset == target.asset})!, time: pts) {
                            _position = pos
                        }
                    }
                case .Playback:
                    if let pos = _getPosition(of: _assets.index(where: {$0.asset == target.asset})!, time: pts) {
                        _position = pos
                    }
                }
                if pts == kCMTimeZero {
                    var urls = ""
                    for reader in _readers {
                        urls += "[\(reader.URL!.lastPathComponent)]"
                    }
                    NSLog("[\(target.URL!.lastPathComponent)] start copying. ← \(urls)")
                }
                return ( frameData.sampleBuffer, frameData.duration )
            } else {
                if target.status == .completed {
                    // 現在のリーダーからサンプルバッファをすべて読み終えた場合、次へ移動する
                    // TODO: 取得したサンプルバッファの位置が1.0を超えていた場合も移動する
                    advanceToNextAsset(shouldLock: false)
                } else {
                    NSLog("[\(target.URL!.lastPathComponent)] Invalid state[\(Int(target.status.rawValue))]. Something is wrong.")
                    _readers.remove(at: 0)
                    _currentPresentationTimestamp = kCMTimeZero
                }
            }
        }
        return nil
    }

    private func _prepareNextAssetReaders(initial: AVAsset? = nil, atTime time: CMTime = kCMTimeZero) {

        // 読み込み済みリーダーの数が上限になっていれば何もしない
        if (_readers.count >= maxNumOfReaders) { return }

        // アセットをどこから読み込むかを決定する
        let startIndex = (initial == nil) ? 0 : _assets.index(where: {$0.asset == initial!}) ?? 0
        // startTimeの設定は初回のみ有効
        var startTime = time

        // 再生速度が0.0のままであれば、デフォルトの再生速度に設定する
        if _playbackRate == 0.0 {
            _playbackRate = 1.0
        }
        
        // リーダーが空の場合、まず先頭のアセットを読み込む
        if _readers.isEmpty && startIndex < _assets.count {
            if let assetreader = _createFragment(_assets[startIndex].asset,
                rate:_playbackRate, startTime:startTime)
            {
                startTime = kCMTimeZero
                _readers.append(assetreader)
            } else {
                _assets.remove(at: startIndex)
            }
        }

        // 読み込みしていないアセットがあれば読み込む(バックグラウンドで)
        async { me in
            var failedIndex: Int? = nil
            outer: for (i, holder) in me._assets[startIndex..<me._assets.count].enumerated() {
                let asset = holder.asset
                let actualIndex = i + startIndex

                // 登録済みの最後のアセットを見つけて、それ以降のアセットを
                // 追加対象として読み込む
                if me._readers.last?.asset === asset && actualIndex+1 < me._assets.count {
                    for (j, target) in me._assets[actualIndex+1..<me._assets.count].enumerated() {

                        // 読み込み済みリーダーの数が上限になれば処理終了
                        if (me._readers.count >= me.maxNumOfReaders) {
                            break outer
                        }

                        if let assetreader = me._createFragment(target.asset,
                            rate:me._playbackRate, startTime:startTime)
                        {
                            startTime = kCMTimeZero
                            me._readers.append(assetreader)
                        } else {
                            // 再度作成しようとしても使えないので、取り除く
                            failedIndex = actualIndex+1+j
                            break outer
                        }
                    }
                }
            }
            // 作成に失敗した場合はアセット群から取り除く（次に読み込んでも失敗しているため）
            if failedIndex != nil {
                me._assets.remove(at: failedIndex!)
            }
        }
    }

    private func _createFragment(_ asset:AVAsset, rate:Float=1.0,
        startTime:CMTime=kCMTimeZero, endTime:CMTime=kCMTimePositiveInfinity)
        -> AssetReaderFragment?
    {
        // アセットを読むタイミングによっては、track情報が取得できないことがある。
        // この問題はAVAssetを作り直すところからやり直せば解消できるため、
        // 最大retry回数まで再作成を試みる
        var retry = 3
        var target = asset
        repeat {
            if let assetreader = AssetReaderFragment(asset:target,
                rate:rate, startTime:startTime, endTime:endTime)
            {
                return assetreader
            } else {
                // URLから作成したアセットのみ、失敗したときに再作成を試みる
                if let oldAsset = target as? AVURLAsset {
                    let index = _assets.index{ $0.asset == oldAsset }!
                    _assets.remove(at: index)
                    let newAsset = AVAsset(url: oldAsset.url)
                    let holder = AssetHolder(newAsset) { duration in
                        self._amountDuration += duration
                        return
                    }
                    _assets.insert(holder, at: index)
                    target = newAsset
                } else {
                    // URL以外のアセット(コンポジションなど)は諦める
                    break
                }
            }
            retry -= 1
        } while retry > 0
        NSLog("Failed to create an asset reader fragment for \(asset)")
        return nil
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
    func _getAssetPosition(of position: Float) -> AssetPosition? {
        if _assets.isEmpty { return nil }

        // 1) 1.0のアセット位置を算出する
        if let one = _getWindowEnd() {

            // 再生位置を1.0位置からのオフセット時間に変換する
            let offset = ( window * (1.0 - position) ) * -1.0

            // 2) 算出した1.0位置からのオフセットを引いたアセット位置を探す
            if let result = _findAsset(_assets, from: one, offset: offset) {

                // 算出した値なので端数が出ないよう、なおかつアセット末尾近くも
                // 余裕を持たせるよう、1/30秒で丸めて返す
                let time = CMTimeConvertScale(result.time, 30, .roundTowardZero)
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
    func _getPosition(of index:Int, time:CMTime) -> Float? {
        let target = AssetPosition(index, time)

        /*
        「offset = window * position」であることを利用して位置を求める

        offset = window * position
        → position = offset/window
        (※ offset = t(target) - t0 なので)
        → position = (t(target) - t0)/window
        (※ t0 = t1 - window なので)
        → position = (t(target) - t1 + window)/window
        ∴ position = (window - t(target〜t1) / window
        */
        if let t1 = _getWindowEnd() {
            let numer = window - _getDurationBetweenAssets(from:target, to:t1)
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

        switch playbackMode {
        case .Streaming:
            // 現在の再生場所を起点にしてposition=1.0地点を探索する
            if let i_t1 = self._assets.index(where: {$0.asset == _readers.first!.asset}) {

                let t1 = AssetPosition(i_t1, _currentPresentationTimestamp)
                let offset = window * (1.0 - position)

                if let windowEnd = _findAsset(_assets, from: t1, offset: offset) {
                    return windowEnd
                } else {
                    // 見つからなかった場合、全アセットの最後端を1.0として扱う
                    return AssetPosition(_assets.count-1, _assets.last!.duration)
                }
            }
        case .Playback:
            // 全アセットの最後端を1.0として扱う
            return AssetPosition(_assets.count-1, _assets.last!.duration)
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
    func _findAsset(_ assets:[AssetHolder], from:AssetPosition, offset:CMTime)
        -> AssetPosition?
    {
        if from.index < 0 || from.index >= assets.count { return nil }
        if offset.isZero { return from }

        let isSignMinus = offset.isSignMinus

        // アセット列のうち、どの範囲を探すか
        let targets = isSignMinus ?
            assets[0...from.index].reversed() : Array(assets[from.index..<assets.count])

        // 繰り返し処理を簡略化するためにゲタを履かせる
        var offset = isSignMinus ?
            (offset * -1.0 + assets[from.index].duration - from.time) :
            (offset + from.time)

        for (i, holder) in targets.enumerated() {

            if offset <= holder.duration {
                return isSignMinus ?
                    AssetPosition(from.index - i, holder.duration - offset) :
                    AssetPosition(from.index + i, offset)
            }
            offset -= holder.duration
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
            return rhs.time - lhs.time
        }

        // 中間のアセットのduration合計を求める
        let intermediates = (lhs.index < rhs.index) ?
            _assets[lhs.index+1 ..< rhs.index] : _assets[rhs.index+1 ..< lhs.index]
        sumTime = intermediates.reduce(sumTime) { $0 + $1.duration }

        // 両端のアセットを加算して、符号を付けて返す
        if lhs.index < rhs.index {
            // (lhsの残り時間 + rhs)の符号反転
            sumTime += (_assets[lhs.index].duration - lhs.time) + rhs.time
            return sumTime
        } else {
            // lhs + rhsの残り時間
            sumTime += lhs.time + (_assets[rhs.index].duration - rhs.time)
            return kCMTimeZero - sumTime
        }
    }

}

private extension StreamFrameProducer {
    func sync(handler: (StreamFrameProducer) -> Void) {
        dispatch_sync(_decodeQueue) {
//            [unowned self] in
            handler(self)
        }
    }

    func async(handler: @escaping (StreamFrameProducer) -> Void) {
        _decodeQueue.async() {
//            [unowned self] in
            handler(self)
        }
    }
}
