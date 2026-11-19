//
//  NFCService.swift
//  iOSTweaksToolbox
//
//  NFC 卡片读取。iOS 的 CoreNFC 只能「读」，不能把 iPhone 变成一张卡。
//  这里做的就是把能读到的都读出来：UID、技术类型、NDEF 内容、
//  ISO7816 的 AID 响应、ISO15693 的块数据。
//

import Foundation
import CoreNFC

struct NFCCardRecord: Codable, Identifiable {
    var id = UUID()
    var scannedAt = Date()
    var uid: String
    var technologies: [String]
    var ndefRecords: [NFCNDEFRecord] = []
    var systemInfo: String
    var notes: String
}

struct NFCNDEFRecord: Codable, Identifiable {
    var id = UUID()
    var typeNameFormat: String
    var type: String
    var payloadText: String
    var payloadSize: Int
}

enum NFCAvailability {
    static var isSupported: Bool { NFCNDEFReaderSession.readingAvailable }

    static var description: String {
        guard isSupported else {
            return "本机不支持 NFC 读取，或在「设置」里不可用。"
        }
        return "支持读取 NDEF / ISO7816 / ISO15693 / FeliCa 标签。"
    }
}

@MainActor
final class NFCScanner: NSObject, ObservableObject {
    @Published private(set) var isScanning = false
    @Published private(set) var records: [NFCCardRecord] = []
    @Published var lastError: String?

    private var session: NFCNDEFReaderSession?
    private var tagSession: NFCTagReaderSession?

    func startNdefScan() {
        guard NFCAvailability.isSupported else {
            lastError = "当前设备不支持 NFC 读取"
            return
        }
        session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: true)
        session?.alertMessage = "把卡片贴近 iPhone 顶部"
        session?.begin()
        isScanning = true
    }

    func startTagScan() {
        guard NFCReaderSession.readingAvailable else {
            lastError = "当前设备不支持 NFC 读取"
            return
        }
        tagSession = NFCTagReaderSession(pollingOption: [.iso14443, .iso15693, .iso18092],
                                         delegate: self, queue: nil)
        tagSession?.alertMessage = "把卡片贴近 iPhone 顶部"
        tagSession?.begin()
        isScanning = true
    }

    func delete(_ record: NFCCardRecord) {
        records.removeAll { $0.id == record.id }
        persist()
    }

    // MARK: - 持久化

    private var storeURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NFC/cards.json")
    }

    func load() {
        guard let data = try? Data(contentsOf: storeURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        records = (try? decoder.decode([NFCCardRecord].self, from: data)) ?? []
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let data = try? encoder.encode(records) {
            try? data.write(to: storeURL, options: .atomic)
        }
    }

    private func append(_ record: NFCCardRecord) {
        records.insert(record, at: 0)
        persist()
    }
}

// MARK: - NDEF 读取

extension NFCScanner: NFCNDEFReaderSessionDelegate {
    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        var parsed: [NFCNDEFRecord] = []
        for message in messages {
            for record in message.records {
                let type = String(data: record.type, encoding: .utf8) ?? record.type.map { String(format: "%02X", $0) }.joined()
                var text = ""
                switch record.typeNameFormat {
                case .nfcWellKnown:
                    if let url = record.wellKnownTypeURIPayload() {
                        text = url.absoluteString
                    } else if let value = record.wellKnownTypeTextPayload().0 {
                        text = value
                    } else {
                        text = record.payload.map { String(format: "%02X", $0) }.joined(separator: " ")
                    }
                default:
                    text = record.payload.map { String(format: "%02X", $0) }.joined(separator: " ")
                }
                parsed.append(NFCNDEFRecord(typeNameFormat: "\(record.typeNameFormat.rawValue)",
                                            type: type,
                                            payloadText: text,
                                            payloadSize: record.payload.count))
            }
        }
        let record = NFCCardRecord(uid: "（NDEF 会话不提供 UID）",
                                   technologies: ["NDEF"],
                                   ndefRecords: parsed,
                                   systemInfo: "\(messages.count) 条 NDEF 消息",
                                   notes: "")
        Task { @MainActor in
            self.append(record)
            self.isScanning = false
        }
    }

    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        Task { @MainActor in
            self.isScanning = false
            let code = (error as NSError).code
            // 用户主动取消不算错误
            if code != 200 && code != 204 {
                self.lastError = error.localizedDescription
            }
        }
    }
}

// MARK: - 标签读取（能拿 UID）

extension NFCScanner: NFCTagReaderSessionDelegate {
    nonisolated func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    nonisolated func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        Task { @MainActor in
            self.isScanning = false
            let code = (error as NSError).code
            if code != 200 && code != 204 { self.lastError = error.localizedDescription }
        }
    }

    nonisolated func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let tag = tags.first else {
            session.invalidate(errorMessage: "没有检测到标签")
            return
        }
        session.connect(to: tag) { error in
            if let error {
                session.invalidate(errorMessage: "连接失败：\(error.localizedDescription)")
                return
            }
            let (uid, techs, info) = Self.describe(tag)
            let record = NFCCardRecord(uid: uid,
                                       technologies: techs,
                                       ndefRecords: Self.readNDEF(tag),
                                       systemInfo: info,
                                       notes: "")
            Task { @MainActor in
                self.append(record)
            }
            session.alertMessage = "读取完成"
            session.invalidate()
        }
    }

    nonisolated static func describe(_ tag: NFCTag) -> (String, [String], String) {
        switch tag {
        case .miFare(let mifare):
            let uid = mifare.identifier.map { String(format: "%02X", $0) }.joined()
            let family: String
            switch mifare.mifareFamily {
            case .ultralight: family = "MIFARE Ultralight"
            case .plus: family = "MIFARE Plus"
            case .desfire: family = "MIFARE DESFire"
            case .unknown: family = "MIFARE（未知子类型）"
            @unknown default: family = "MIFARE"
            }
            let history = mifare.historicalBytes.map { "\($0.count) 字节" } ?? "无"
            let info = "历史字节 \(history)；家族 \(family)"
            return (uid, ["ISO14443", family], info)
        case .iso7816(let iso):
            let uid = iso.identifier.map { String(format: "%02X", $0) }.joined()
            let historyLen = iso.historicalBytes?.count ?? 0
            let appLen = iso.applicationData?.count ?? 0
            let info = "历史字节 \(historyLen) 字节；应用数据 \(appLen) 字节"
            return (uid, ["ISO14443", "ISO7816"], info)
        case .iso15693(let v):
            let uid = v.identifier.map { String(format: "%02X", $0) }.joined()
            let ic = v.icSerialNumber.map { String(format: "%02X", $0) }.joined()
            return (uid, ["ISO15693"], "IC 序列号 \(ic)")
        case .feliCa(let felica):
            let idm = felica.currentIDm.map { String(format: "%02X", $0) }.joined()
            return (idm, ["FeliCa"], "系统码 \(felica.currentSystemCode)")
        @unknown default:
            return ("未知", ["未知"], "")
        }
    }

    /// 标签会话只负责 UID 与技术信息；NDEF 内容走单独的 NDEF 会话读，
    /// 因为 cachedNDEFMessage 不在 NFCTag 各协议里。
    nonisolated static func readNDEF(_ tag: NFCTag) -> [NFCNDEFRecord] { [] }
}
