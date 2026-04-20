import Foundation
import os

enum PFLog {
    static let tap    = Logger(subsystem: "com.avb.pointfocus", category: "tap")
    static let router = Logger(subsystem: "com.avb.pointfocus", category: "router")
    static let warp   = Logger(subsystem: "com.avb.pointfocus", category: "warp")
}
