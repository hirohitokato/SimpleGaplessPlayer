//
//  HKLStdLibUtils.swift
//
//  Created by Hirohito Kato on 2015/01/12.
//  Copyright (c) 2015年 Hirohito Kato. All rights reserved.
//

import Foundation


extension Array {
    /**
    Returns the lowest index whose corresponding array value matches a given condition.

    :discussion: Starting at index 0, each element of the array is passed as the 1st parameter of condition closure until a match is found or the end of the array is reached. Objects are considered equal if the closure returns true.
    
    - parameter condition: A closure for finding the target object in the array

    - returns: The lowest index whose corresponding array value matches a given condition. If none of the objects in the array matches the condition, returns nil.

    :refer: http://stackoverflow.com/a/24105493
    */
    func indexOf(@noescape condition: Array.Element -> Bool) -> Array.Index? {
        for idx in self.indices {
            if condition(self[idx]) {
                return idx
            }
        }
        return nil
    }
}

/**
Returns the first index where condition matches in domain or nil if it does not matched.

- parameter domain:    CollectionType object
- parameter condition: Condition closure which returns true if it find the target.

- returns: The first found index matches the condition.

:refer: https://github.com/norio-nomura/SwiftBenchmark-indexOf
- Author: norio_nomura
*/
func index_of<C : CollectionType where C.Generator.Element : Equatable>
    (domain: C, condition: C.Generator.Element -> Bool) -> C.Index?
{
    // faster than  find(lazy(domain).map(condition), true)
    for idx in domain.indices {
        if condition(domain[idx]) {
            return idx
        }
    }
    return nil
}
