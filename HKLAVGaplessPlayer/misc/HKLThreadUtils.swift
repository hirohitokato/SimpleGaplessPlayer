//
//  HKLThreadUtils.swift
//
//  Created by Hirohito Kato on 2014/12/20.
//  Copyright (c) 2014年 Hirohito Kato. All rights reserved.
//

import Foundation

/**
Objective-Cにおける@synchronized(object){…}を実現する。インスタンスのスコープが有効の間、イニシャライザに渡したオブジェクトを使って@synchronizedを実現する。スコープから外れたときに、デイニシャライザでobjectのロックを解放する

:usage: 「var lock = ScopedLock(self)」という文を、スコープの先頭で記述する。
*/
class ScopedLock {
    let object: AnyObject

    /**
    イニシャライザ。
    - parameter obj: ロック対象のオブジェクト
    */
    init(_ obj : AnyObject) { object = obj; objc_sync_enter(object) }
    deinit { objc_sync_exit(object) }
}
