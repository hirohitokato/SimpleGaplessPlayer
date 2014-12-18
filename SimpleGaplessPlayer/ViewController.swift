//
//  ViewController.swift
//  LearningVideoComposition
//
//  Created by Hirohito Kato on 2014/12/17.
//  Copyright (c) 2014年 Hirohito Kato. All rights reserved.
//

import UIKit
import Photos
import AVFoundation


class ViewController: UIViewController {

    @IBOutlet weak var playerView: HKLGLPixelBufferView!
    private var readers = [AVAssetReader]()
    private var displayLink: CADisplayLink!

    override func viewDidLoad() {
        super.viewDidLoad()

        // DisplayLinkを作成
        displayLink = CADisplayLink(target: self, selector: "displayLinkCallback:")
        displayLink.frameInterval = 2 // 30fps
        displayLink.paused = true
        displayLink.addToRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0)) {
            self.setupAssets()
        }
    }

    @IBAction func tapped(sender: AnyObject) {
        displayLink.paused = displayLink.paused ? false : true
    }

    /**
    カメラロールから古い順で10個のビデオを取り出し、リーダーをセットアップする
    */
    func setupAssets() {
        weak var weakSelf = self
        let collections = PHAssetCollection.fetchAssetCollectionsWithType(.SmartAlbum, subtype:.SmartAlbumVideos, options: nil)
        collections.enumerateObjectsUsingBlock { (collection, index, stop)  in

            let assets = PHAsset.fetchAssetsInAssetCollection(collection as PHAssetCollection, options: nil)

            NSLog("assets count:\(assets.count)")
            assets.enumerateObjectsUsingBlock({ (asset, index, stop) in

                _ = PHImageManager.defaultManager().requestAVAssetForVideo(asset as PHAsset,
                    options:nil, resultHandler: { (avasset:AVAsset!, audioMix:AVAudioMix!, info) -> Void in
                        dispatch_async(dispatch_get_main_queue()) {
                            if weakSelf?.readers.count < 10 {
                                let reader = weakSelf?.buildAssetReader(avasset)
                                weakSelf?.readers.append(reader!)
                                reader!.startReading()
                                NSLog("[\(index)] start reading")
                            } else {
                                stop.initialize(true)
                                NSLog("Ignored an asset")
                            }
                        }
                })
            })
        }
    }

    /**
    アセットの指定範囲をフレーム単位で取り出すためのリーダーを作成する。
    具体的には再生時間帯を限定したコンポジションを作成し、そのフレームを取り出すための
    アウトプットを作成している

    :param: asset     読み出し元となるアセット
    :param: startTime アセットの読み出し開始位置（デフォルト：先頭）
    :param: endTime   アセットの読み出し終了位置（デフォルト：末尾）

    :returns: アセットリーダー
    */
    func buildAssetReader(asset:AVAsset,
        startTime:CMTime=kCMTimeZero, var endTime:CMTime=kCMTimePositiveInfinity) -> AVAssetReader!
    {
        var error: NSError? = nil

        let videoTrack = asset.tracksWithMediaType(AVMediaTypeVideo)[0] as AVAssetTrack

        // 引数で指定した再生範囲を「いつから何秒間」の形式に変換
        if endTime > videoTrack.timeRange.duration {
            endTime = videoTrack.timeRange.duration
        }
        let duration = endTime - startTime
        let timeRange = CMTimeRangeMake(startTime, duration)

        /* 作成するコンポジションとリーダーの構造
         *
         * [AVAssetReaderVideoCompositionOutput]: ビデオフレーム取り出し口
         * │└ [AVAssetReader] ↑[videoTracks] : コンポジション上のvideoTrackを読み出し元に指定
         * │    └ [AVMutableComposition]      : 再生時間帯の指定
         * │        └ [videoTrack in AVAsset] : ソースに使うビデオトラック
         * └ [AVVideoComposition]              : フレームレート指定
         */

        // アセットのビデオトラックを配置するためのコンポジションを作成
        let composition = AVMutableComposition()
        let compoVideoTrack = composition.addMutableTrackWithMediaType(AVMediaTypeVideo,
            preferredTrackID: Int32(kCMPersistentTrackID_Invalid))

        // アセットのうち指定範囲をコンポジションのトラック上に配置する。
        compoVideoTrack.insertTimeRange(timeRange, ofTrack: videoTrack, atTime: kCMTimeZero, error: &error)
        if error != nil {
            NSLog("Failed to insert a video track to composition:\(error)")
            return nil
        }

        // フレームレート指定のためにビデオコンポジションを作成・利用(30fps)
        let videoComposition = AVMutableVideoComposition(propertiesOfAsset: asset)
        videoComposition.frameDuration = CMTime(value:1, 30)

        // アセットリーダーに接続するアウトプット(出力口)として、
        // ビデオコンポジションを指定できるAVAssetReaderVideoCompositionOutputを作成
        // 注意点：
        // - このビデオトラックにはコンポジション上のビデオトラックを指定すること
        // - IOSurfaceで作成しなくても再生できるが、念のため付けておく
        let videoTracks = composition.tracksWithMediaType(AVMediaTypeVideo)
        var output = AVAssetReaderVideoCompositionOutput(videoTracks: videoTracks,
            videoSettings: [kCVPixelBufferPixelFormatTypeKey : kCVPixelFormatType_32BGRA,
                kCVPixelBufferIOSurfacePropertiesKey : [:]])
        output.videoComposition = videoComposition

        // サンプルバッファを取り出すときにデータをコピーしない（負荷軽減）
        output.alwaysCopiesSampleData = false

        // コンポジションからアセットリーダーを作成し、アウトプットを接続
        if let reader = AVAssetReader(asset: composition, error: &error) {
            if reader.canAddOutput(output) {
                reader.addOutput(output)
            }
            return reader
        } else {
            NSLog("Failed to instantiate a reader for a composition:\(error)")
        }

        return nil
    }

    //MARK: … CADisplayLink callback function
    @objc func displayLinkCallback(displayLink: CADisplayLink) {
        // 表示対象の時刻を計算
        let nextOutputHostTime = displayLink.timestamp + displayLink.duration

        if let reader = readers.first {
            switch reader.status {
            case .Reading:
                let out = reader.outputs[0] as AVAssetReaderOutput
                if let sbuf = out.copyNextSampleBuffer() {
                    if let imgbuf = CMSampleBufferGetImageBuffer(sbuf) {
                        playerView.displayPixelBuffer(imgbuf)
                    }
                } else {
                    println("move to next")
                    readers.removeAtIndex(0)
                }
            case .Completed:
                println("move to next(Completed).error:[\(reader.error)]")
                readers.removeAtIndex(0)
            default:
                println("Something is wrong.")
            }
        }

        if readers.isEmpty {
            println("finished.")
            displayLink.paused = true
        }
    }
}

