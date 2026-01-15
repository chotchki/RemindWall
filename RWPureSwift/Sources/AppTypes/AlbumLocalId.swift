//
//  AlbumId.swift
//  RWPureSwift
//
//  Created by Christopher Hotchkiss on 10/13/25.
//

import Tagged
import SQLiteData

public enum AlbumLocalIdTag {}
public typealias AlbumLocalId = Tagged<AlbumLocalIdTag, String>
