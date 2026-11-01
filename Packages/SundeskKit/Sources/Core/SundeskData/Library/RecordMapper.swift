//
//  RecordMapper.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/11/01.
//

import Foundation
import SundeskDomain

/// SwiftData の形と Domain の値を行き来する。
enum RecordMapper {
    static func reference(from record: ReferenceRecord) -> Reference {
        Reference(
            id: record.id,
            metadata: ReferenceMetadata(
                type: ReferenceType(rawValue: record.type) ?? .document,
                title: record.title,
                authors: (try? JSONDecoder().decode([Creator].self, from: record.authors)) ?? [],
                issued: PartialDate(parsing: record.issued),
                containerTitle: record.containerTitle,
                volume: record.volume,
                issue: record.issue,
                pages: record.pages,
                publisher: record.publisher,
                doi: record.doi,
                arxiv: record.arxiv,
                isbn: record.isbn,
                url: record.url,
                abstract: record.abstract),
            citationKey: record.citationKey,
            tags: record.tags,
            collectionIDs: Set(record.collections.map(\.id)),
            readingStatus: ReadingStatus(rawValue: record.readingStatus) ?? .unread,
            note: record.note,
            attachment: record.attachment,
            summary: record.summary.flatMap { try? JSONDecoder().decode(PaperSummary.self, from: $0) },
            dateAdded: record.dateAdded,
            dateModified: record.dateModified)
    }

    /// `collections` は、`reference.collectionIDs` に当たるコレクション。
    static func apply(_ reference: Reference, to record: ReferenceRecord, collections: [CollectionRecord]) {
        let metadata = reference.metadata
        record.type = metadata.type.rawValue
        record.title = metadata.title
        record.authors = (try? JSONEncoder().encode(metadata.authors)) ?? Data()
        record.issued = metadata.issued?.text ?? ""
        record.containerTitle = metadata.containerTitle
        record.volume = metadata.volume
        record.issue = metadata.issue
        record.pages = metadata.pages
        record.publisher = metadata.publisher
        record.doi = metadata.doi
        record.arxiv = metadata.arxiv
        record.isbn = metadata.isbn
        record.url = metadata.url
        record.abstract = metadata.abstract
        record.citationKey = reference.citationKey
        record.tags = reference.tags
        record.readingStatus = reference.readingStatus.rawValue
        record.note = reference.note
        record.attachment = reference.attachment
        record.summary = reference.summary.flatMap { try? JSONEncoder().encode($0) }
        record.dateAdded = reference.dateAdded
        record.dateModified = reference.dateModified
        record.collections = collections
    }

    static func collection(from record: CollectionRecord) -> ReferenceCollection {
        ReferenceCollection(id: record.id, name: record.name, parentID: record.parent?.id)
    }

    static func annotation(from record: AnnotationRecord, referenceID: UUID) -> Annotation {
        Annotation(
            id: record.id,
            referenceID: referenceID,
            color: AnnotationColor(rawValue: record.color) ?? .yellow,
            text: record.text,
            comment: record.comment,
            rects: (try? JSONDecoder().decode([AnnotationRect].self, from: record.rects)) ?? [],
            dateAdded: record.dateAdded)
    }

    static func apply(_ annotation: Annotation, to record: AnnotationRecord) {
        record.color = annotation.color.rawValue
        record.text = annotation.text
        record.comment = annotation.comment
        record.rects = (try? JSONEncoder().encode(annotation.rects)) ?? Data()
        record.dateAdded = annotation.dateAdded
    }
}
