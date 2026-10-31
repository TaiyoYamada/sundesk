//
//  SwiftDataReferenceRepository.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation
import SundeskDomain
import SwiftData

/// 文献、コレクション、注釈を SwiftData に保存する。
@ModelActor
public actor SwiftDataReferenceRepository: ReferenceRepository {
    private var observers: [UUID: AsyncStream<Void>.Continuation] = [:]

    /// - Parameter url: 保存するファイル。nil ならメモリの上だけに置く（テスト用）。
    public static func open(at url: URL?) throws -> SwiftDataReferenceRepository {
        let schema = Schema([ReferenceRecord.self, CollectionRecord.self, AnnotationRecord.self])
        let configuration =
            if let url {
                ModelConfiguration(schema: schema, url: url)
            } else {
                ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            }
        let container = try ModelContainer(for: schema, configurations: configuration)
        return SwiftDataReferenceRepository(modelContainer: container)
    }

    // MARK: - 文献

    public func references() throws(LibraryError) -> [Reference] {
        try fetch(FetchDescriptor<ReferenceRecord>()).map(RecordMapper.reference)
    }

    public func reference(_ id: UUID) throws(LibraryError) -> Reference? {
        try referenceRecord(id).map(RecordMapper.reference)
    }

    public func save(_ reference: Reference) throws(LibraryError) {
        let record = try referenceRecord(reference.id) ?? insert(ReferenceRecord(id: reference.id))
        let collections = try fetch(FetchDescriptor<CollectionRecord>())
            .filter { reference.collectionIDs.contains($0.id) }
        RecordMapper.apply(reference, to: record, collections: collections)
        try persist()
    }

    public func deleteReferences(_ ids: [UUID]) throws(LibraryError) {
        for id in ids {
            if let record = try referenceRecord(id) { modelContext.delete(record) }
        }
        try persist()
    }

    // MARK: - コレクション

    public func collections() throws(LibraryError) -> [ReferenceCollection] {
        try fetch(FetchDescriptor<CollectionRecord>(sortBy: [SortDescriptor(\.name)]))
            .map(RecordMapper.collection)
    }

    public func save(_ collection: ReferenceCollection) throws(LibraryError) {
        let record = try collectionRecord(collection.id) ?? insert(CollectionRecord(id: collection.id, name: ""))
        record.name = collection.name
        record.parent = try collection.parentID.flatMap(collectionRecord)
        try persist()
    }

    public func deleteCollection(_ id: UUID) throws(LibraryError) {
        if let record = try collectionRecord(id) { modelContext.delete(record) }
        try persist()
    }

    // MARK: - 注釈

    public func annotations(of referenceID: UUID) throws(LibraryError) -> [Annotation] {
        guard let record = try referenceRecord(referenceID) else { return [] }
        return record.annotations.map { RecordMapper.annotation(from: $0, referenceID: referenceID) }
            .sorted { ($0.pageIndex, $0.dateAdded) < ($1.pageIndex, $1.dateAdded) }
    }

    public func save(_ annotation: Annotation) throws(LibraryError) {
        let id = annotation.id
        let existing = try fetch(FetchDescriptor<AnnotationRecord>(predicate: #Predicate { $0.id == id })).first
        let record = existing ?? insert(AnnotationRecord(id: id))
        RecordMapper.apply(annotation, to: record)
        record.reference = try referenceRecord(annotation.referenceID)
        try persist()
    }

    public func deleteAnnotation(_ id: UUID) throws(LibraryError) {
        for record in try fetch(FetchDescriptor<AnnotationRecord>(predicate: #Predicate { $0.id == id })) {
            modelContext.delete(record)
        }
        try persist()
    }

    // MARK: - 変更の知らせ

    public func changes() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        let key = UUID()
        observers[key] = continuation
        continuation.onTermination = { _ in
            Task { await self.removeObserver(key) }
        }
        return stream
    }

    private func removeObserver(_ key: UUID) {
        observers[key] = nil
    }

    // MARK: - SwiftData

    private func referenceRecord(_ id: UUID) throws(LibraryError) -> ReferenceRecord? {
        try fetch(FetchDescriptor<ReferenceRecord>(predicate: #Predicate { $0.id == id })).first
    }

    private func collectionRecord(_ id: UUID) throws(LibraryError) -> CollectionRecord? {
        try fetch(FetchDescriptor<CollectionRecord>(predicate: #Predicate { $0.id == id })).first
    }

    private func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws(LibraryError) -> [T] {
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            throw .storage(error.localizedDescription)
        }
    }

    private func insert<T: PersistentModel>(_ model: T) -> T {
        modelContext.insert(model)
        return model
    }

    private func persist() throws(LibraryError) {
        do {
            try modelContext.save()
        } catch {
            throw .storage(error.localizedDescription)
        }
        for observer in observers.values { observer.yield() }
    }
}
