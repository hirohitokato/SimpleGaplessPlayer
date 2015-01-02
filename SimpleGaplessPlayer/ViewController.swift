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

/// フレームレート
public let kFrameRate: Int = 60

class ViewController: UIViewController {

    @IBOutlet weak var playerView: HKLGLPixelBufferView!
    @IBOutlet weak var msgLabel: UILabel!
    private let _player = HKLAVGaplessPlayer()

    @IBOutlet weak var rateLabel: UILabel!
    private var _timer: NSTimer!

    override func viewDidLoad() {
        super.viewDidLoad()

        _player.playerView = playerView
        loadVideoAssets()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)

        _timer = NSTimer.scheduledTimerWithTimeInterval(
            0.2, target: self, selector: "updateCpuInfo:",
            userInfo: nil, repeats: true)
    }

    override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)

        _timer.invalidate()
    }

    @IBAction func tapped(sender: AnyObject) {
        if _player.isPlaying {
            _player.pause()
        } else {
            _player.play()
        }
    }

    @IBAction func swipedToLeft(sender: AnyObject) {
        _player.advanceToNextAsset()
    }

    @IBAction func sliderUpdated(sender: UISlider) {
        let result = _player._producer.playerInfoForPosition(sender.value)
        println("position:\(sender.value) -> \(result)")
    }

    @IBAction func rateChanged(sender: UISlider) {
        rateLabel.text = "rate: \(sender.value)"
        _player.play(rate: sender.value)
    }

    @objc func updateCpuInfo(timer: NSTimer) {
        msgLabel.text = "cpu: \(cpu_usage_in_percent())%"
    }

    /**
    カメラロールから古い順で10個のビデオを取り出し、リーダーをセットアップする
    */
    private func loadVideoAssets() {

        let queue = dispatch_queue_create("buildingqueue", DISPATCH_QUEUE_SERIAL)

        // 収集したアセットをいったん格納する（最終的にindex順でソートして格納）
        var avassets = [(Int, AVAsset)]()

        // 「ビデオ」のスマートアルバムから収集
        let collections = PHAssetCollection.fetchAssetCollectionsWithType(.SmartAlbum, subtype:.SmartAlbumVideos, options: nil)
        collections.enumerateObjectsUsingBlock {
            [unowned self]  collection, index, stop  in
            let collection = collection as PHAssetCollection

            // 日付の古い順に取得
            var options = PHFetchOptions()
            options.sortDescriptors = [ NSSortDescriptor(key: "creationDate", ascending: true) ]

            let assets = PHAsset.fetchAssetsInAssetCollection(collection, options: options)
            assets.enumerateObjectsUsingBlock {
                phAsset, index, stop in
                let phAsset = phAsset as PHAsset

                // この処理は非同期で行われるので注意
                _ = PHImageManager.defaultManager().requestAVAssetForVideo(phAsset, options:nil) {
                    avasset, audioMix, info in

                    if let avasset = avasset {
                        avassets.append((index,avasset))
                        if avassets.count == assets.count {
                            dispatch_async(queue) {
                                // プロデューサーにアセットを追加
                                sort(&avassets) { $0.0 < $1.0 }
                                for (_, a) in avassets {
                                    self._player.appendAsset(a)
                                }
                            }
                        }

                    }
                }
            }
        }
    }
}
