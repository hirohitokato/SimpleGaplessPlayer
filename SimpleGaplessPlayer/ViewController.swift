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
import HKLAVGaplessPlayer

class ViewController: UIViewController {

    @IBOutlet weak var playerView: HKLGLPixelBufferView!
    @IBOutlet weak var msgLabel: UILabel!
    private let _player = HKLAVGaplessPlayer()

    @IBOutlet weak var rateLabel: UILabel!
    private var _timer: NSTimer!

    @IBOutlet weak var positionSlider: UISlider!

    override func viewDidLoad() {
        super.viewDidLoad()

        _player.playerView = playerView
        loadVideoAssets()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    private var positionContext = 0
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)

        _timer = NSTimer.scheduledTimerWithTimeInterval(
            0.2, target: self, selector: "updateUI:",
            userInfo: nil, repeats: true)
        _player.addObserver(self, forKeyPath: "position", options: .New, context: &positionContext)
    }

    override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)

        _timer.invalidate()
        _player.removeObserver(self, forKeyPath: "position", context: &positionContext)
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
        _player.play(_player.rate, position: sender.value)
    }

    @IBAction func rateChanged(sender: UISlider) {
        rateLabel.text = "rate: \(sender.value)"
        _player.play(sender.value)
    }

    @objc func updateUI(timer: NSTimer) {
        msgLabel.text = "cpu: \(cpu_usage_in_percent())% pos:\(_player.position)"
    }

    override func observeValueForKeyPath(keyPath: String,
        ofObject object: AnyObject, change: [NSObject: AnyObject],
        context: UnsafeMutablePointer<Void>)
    {
        if context == &positionContext {
               positionSlider.value = _player.position
        } else {
            super.observeValueForKeyPath(keyPath, ofObject: object, change: change, context: context)
        }
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
                        // プレーヤー内部で読み込んでいるdurationを先読みして
                        // おくことで、再生順序が日付順になるよう試みる
                        avasset.loadValuesAsynchronouslyForKeys(["duration"]) {
                            dispatch_async(queue) {
                                avassets.append((index,avasset))
                                if avassets.count == assets.count {
                                    println("Finished gathering video assets.")
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
}
