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
    
    :param: condition A closure for finding the target object in the array

    :returns: The lowest index whose corresponding array value matches a given condition. If none of the objects in the array matches the condition, returns nil.

    :refer: http://stackoverflow.com/a/24105493
    */
    func indexOf(condition: T -> Bool) -> Int? {
        for (idx, element) in enumerate(self) {
            if condition(element) {
                return idx
            }
        }
        return nil
    }
}

