//
//  HKLStdLibUtils.swift
//
//  Created by Hirohito Kato on 2015/01/12.
//  Copyright (c) 2015年 Hirohito Kato. All rights reserved.
//

import Foundation


/**
Returns the first index where condition matches in domain or nil if it does not matched.

:param: domain    CollectionType object
:param: condition Condition closure which returns true if it find the target.

:returns: The first found index matches the condition.

:refer: https://github.com/norio-nomura/SwiftBenchmark-indexOf
:author: norio_nomura
*/
func index_of<C : Collection>
    (domain: C, condition: (C.Iterator.Element) -> Bool) -> C.Index? where C.Iterator.Element : Equatable
{
    // faster than  find(lazy(domain).map(condition), true)
    for idx in domain.indices {
        if condition(domain[idx]) {
            return idx
        }
    }
    return nil
}

/**
 Returns a clipped value between lower & upper bounds.

 :param: value to be clipped.
 :param: lower bounds
 :param: upper bounds

 :returns: value clipped between lower<= value <= upper.
 */
func clip<T: Comparable>(_ value: T?, lower: T, upper: T) -> T? {
    guard let value = value else {
        return nil
    }
    if value < lower {
        return lower
    } else if value > upper {
        return upper
    } else {
        return value
    }
}
