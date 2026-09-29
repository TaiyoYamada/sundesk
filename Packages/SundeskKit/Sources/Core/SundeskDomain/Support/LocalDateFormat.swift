//
//  LocalDateFormat.swift
//  SundeskDomain
//
//  Created by 山田大陽 on 2026/09/30.
//

import Foundation

extension FormatStyle where Self == Date.ISO8601FormatStyle {
    /// この Mac の時刻帯で書く ISO 8601。
    ///
    /// `.iso8601` は UTC で書くので、日本の朝 9 時より前は前の日の日付になってしまう。
    public static var localISO8601: Self { Date.ISO8601FormatStyle(timeZone: .current) }
}
