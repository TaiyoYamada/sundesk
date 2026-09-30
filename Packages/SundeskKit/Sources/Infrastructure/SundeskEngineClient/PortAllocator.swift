//
//  PortAllocator.swift
//  SundeskEngineClient
//
//  Created by 山田大陽 on 2026/09/29.
//

import Darwin

/// 127.0.0.1 の空いている TCP ポートを探す。
enum PortAllocator {
    /// ポート 0 で bind して OS に空きポートを選ばせ、その番号を返す。
    ///
    /// ソケットはすぐ閉じるので、エンジンが bind するまでの間に他のプロセスに取られる
    /// 可能性はわずかに残る。その場合はエンジンの起動が失敗し、再起動で解消する。
    static func freeLoopbackPort() -> Int? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { return nil }

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        guard named == 0 else { return nil }
        return Int(UInt16(bigEndian: address.sin_port))
    }
}
