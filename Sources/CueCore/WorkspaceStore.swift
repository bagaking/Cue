import Foundation

public final class WorkspaceStore {
    private typealias TransactionHook = (WorkspaceTransactionFailpoint, WorkspaceTransactionContext) throws -> Void

    private struct DirectoryIdentity: Equatable {
        var volume: UInt64
        var file: UInt64
    }

    private let fileManager: FileManager
    private let backupLimit: Int
    private let transactionHook: TransactionHook?

    public init(fileManager: FileManager = .default, backupLimit: Int = 10) {
        self.fileManager = fileManager
        self.backupLimit = max(backupLimit, 10)
        transactionHook = nil
    }

    @_spi(Testing) public init(
        fileManager: FileManager = .default,
        backupLimit: Int = 10,
        transactionHook: @escaping (
            WorkspaceTransactionFailpoint,
            WorkspaceTransactionContext
        ) throws -> Void
    ) {
        self.fileManager = fileManager
        self.backupLimit = max(backupLimit, 10)
        self.transactionHook = transactionHook
    }

    public func loadSnapshot(from url: URL) throws -> WorkspaceSnapshot {
        try validatePackageURL(url)
        let requestedURL = url.standardizedFileURL
        let inspection = try coordinatedInspection(at: requestedURL)
        return makeSnapshot(url: requestedURL, inspection: inspection)
    }

    public func createSnapshot(
        document: WorkspaceDocument,
        at url: URL
    ) throws -> WorkspaceCommitReceipt {
        try validatePackageURL(url)
        let requestedURL = url.standardizedFileURL
        try fileManager.createDirectory(
            at: requestedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard !fileManager.fileExists(atPath: requestedURL.path) else {
            throw WorkspaceStoreError.externalModification
        }
        let plan = try CuePackagePlanner.planSchema3Creation(for: document)
        let stageURL = try prepareStage(plan: plan, nextTo: requestedURL)
        return try publishCreation(plan: plan, stageURL: stageURL, requestedURL: requestedURL)
    }

    public func commit(
        document: WorkspaceDocument,
        basedOn snapshot: WorkspaceSnapshot
    ) throws -> WorkspaceCommitReceipt {
        switch snapshot.writeCapability {
        case .writableSchema3, .requiresVerifiedSchema2Migration:
            break
        case let .readOnly(reason):
            throw WorkspaceStoreError.readOnly(reason)
        }
        guard snapshot.conflicts.isEmpty else {
            throw WorkspaceStoreError.invalidDocument("workspace has unresolved storage conflicts")
        }
        let plan = try CuePackagePlanner.planSchema3Write(
            from: snapshot.inspection,
            document: document
        )
        guard plan.sourcePackageRevision == snapshot.revision else {
            throw WorkspaceStoreError.invalidDocument("write plan is not bound to the supplied snapshot")
        }
        let stageURL = try prepareStage(plan: plan, nextTo: snapshot.packageURL)
        return try publishReplacement(
            plan: plan,
            stageURL: stageURL,
            snapshot: snapshot
        )
    }

    public func create(document: WorkspaceDocument, at url: URL) throws -> FileFingerprint {
        fingerprint(for: try createSnapshot(document: document, at: url).snapshot)
    }

    public func load(from url: URL) throws -> (WorkspaceDocument, FileFingerprint) {
        let snapshot = try loadSnapshot(from: url)
        guard let document = snapshot.document else {
            if case let .readOnly(reason) = snapshot.writeCapability {
                throw WorkspaceStoreError.readOnly(reason)
            }
            throw WorkspaceStoreError.invalidDocument("workspace did not produce a document")
        }
        return (document, fingerprint(for: snapshot))
    }

    @discardableResult
    public func write(
        document: WorkspaceDocument,
        to url: URL,
        expectedFingerprint: FileFingerprint?
    ) throws -> FileFingerprint {
        if !fileManager.fileExists(atPath: url.path) {
            guard expectedFingerprint == nil else { throw WorkspaceStoreError.missingFile }
            return try create(document: document, at: url)
        }
        guard let expectedFingerprint else {
            throw WorkspaceStoreError.externalModification
        }
        let snapshot = try loadSnapshot(from: url)
        guard fingerprint(for: snapshot) == expectedFingerprint else {
            throw WorkspaceStoreError.externalModification
        }
        let receipt = try commit(document: document, basedOn: snapshot)
        guard sameLogicalURL(receipt.publishedURL, url.standardizedFileURL) else {
            throw WorkspaceStoreError.publicationRecoveryRequired(recoveryEvidence(
                sourceRevision: snapshot.revision,
                targetRevision: receipt.snapshot.revision,
                urls: [url, receipt.publishedURL, receipt.retainedBackupURL]
            ))
        }
        return fingerprint(for: receipt.snapshot)
    }

    public func saveConflictCopy(document: WorkspaceDocument, nextTo url: URL) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stem = url.deletingPathExtension().lastPathComponent
        let parent = url.deletingLastPathComponent()
        var copy = parent.appendingPathComponent(
            "\(stem).cue-conflict-\(formatter.string(from: Date())).cue",
            isDirectory: true
        )
        var suffix = 2
        while fileManager.fileExists(atPath: copy.path) {
            copy = parent.appendingPathComponent(
                "\(stem).cue-conflict-\(formatter.string(from: Date()))-\(suffix).cue",
                isDirectory: true
            )
            suffix += 1
        }
        _ = try createSnapshot(document: document, at: copy)
        return copy
    }

    public func fingerprint(for url: URL) throws -> FileFingerprint {
        fingerprint(for: try loadSnapshot(from: url))
    }

    private func coordinatedInspection(at url: URL) throws -> CuePackageInspection {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<CuePackageInspection, Error>?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { accessorURL in
            result = Result {
                try CuePackagePlanner.inspect(atCoordinatedAccessorURL: accessorURL, fileManager: fileManager)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else {
            throw WorkspaceStoreError.writeFailure("coordinated read accessor did not run")
        }
        return try result.get()
    }

    private func makeSnapshot(url: URL, inspection: CuePackageInspection) -> WorkspaceSnapshot {
        var document = inspection.document
        if document != nil {
            document!.schemaVersion = WorkspaceDocument.currentSchema
            document!.layout = []
            document!.ensureInbox()
            document!.normalizeOrder()
        }
        return WorkspaceSnapshot(packageURL: url, document: document, inspection: inspection)
    }

    private func fingerprint(for snapshot: WorkspaceSnapshot) -> FileFingerprint {
        FileFingerprint(
            size: UInt64(snapshot.inspection.rawFiles.values.reduce(0) { $0 + $1.count }),
            modifiedAt: .distantPast,
            digest: snapshot.revision.rawValue
        )
    }

    private func prepareStage(plan: CueSchema3PackagePlan, nextTo requestedURL: URL) throws -> URL {
        let parent = requestedURL.deletingLastPathComponent()
        let stageURL = parent.appendingPathComponent(
            ".\(requestedURL.deletingPathExtension().lastPathComponent).cue-stage-\(UUID().uuidString).cue",
            isDirectory: true
        )
        var keepStage = false
        defer {
            if !keepStage, fileManager.fileExists(atPath: stageURL.path) {
                try? fileManager.removeItem(at: stageURL)
            }
        }
        try fileManager.createDirectory(at: stageURL, withIntermediateDirectories: false)
        for directory in plan.directories.sorted(by: directoryOrder) {
            try fileManager.createDirectory(
                at: stageURL.appendingPathComponent(directory, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        for file in plan.files {
            let destination = stageURL.appendingPathComponent(file.path)
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try file.data.write(to: destination, options: [])
            let handle = try FileHandle(forWritingTo: destination)
            try handle.synchronize()
            try handle.close()
        }
        try invoke(.afterStageSynchronized, requestedURL: requestedURL, stageURL: stageURL)
        let staged = try CuePackagePlanner.inspect(
            atCoordinatedAccessorURL: stageURL,
            fileManager: fileManager
        )
        guard staged.packageRevision == plan.targetPackageRevision,
              staged.writeCapability == .writableSchema3 else {
            throw WorkspaceStoreError.invalidDocument("staged package did not reopen as the exact target")
        }
        try invoke(.afterStageValidated, requestedURL: requestedURL, stageURL: stageURL)
        keepStage = true
        return stageURL
    }

    private func publishCreation(
        plan: CueSchema3PackagePlan,
        stageURL: URL,
        requestedURL: URL
    ) throws -> WorkspaceCommitReceipt {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<WorkspaceCommitReceipt, Error>?
        var publicationInvoked = false
        let requestedParent = requestedURL.deletingLastPathComponent()
        coordinator.coordinate(writingItemAt: requestedParent, options: [], error: &coordinationError) { accessorParent in
            let accessorURL = accessorParent.appendingPathComponent(
                requestedURL.lastPathComponent,
                isDirectory: true
            )
            do {
                guard !fileManager.fileExists(atPath: accessorURL.path) else {
                    throw WorkspaceStoreError.externalModification
                }
                try requireStageBesideAccessor(stageURL: stageURL, accessorURL: accessorURL)
                try invoke(.afterRevisionConfirmed, requestedURL: requestedURL, stageURL: stageURL)
                publicationInvoked = true
                try fileManager.moveItem(at: stageURL, to: accessorURL)
                try invoke(
                    .afterReplacement,
                    requestedURL: requestedURL,
                    stageURL: stageURL,
                    publishedURL: accessorURL
                )
                let published = try CuePackagePlanner.inspect(
                    atCoordinatedAccessorURL: accessorURL,
                    fileManager: fileManager
                )
                guard published.packageRevision == plan.targetPackageRevision else {
                    throw WorkspaceStoreError.invalidDocument("created package does not match the exact target")
                }
                try invoke(
                    .afterPublishedValidation,
                    requestedURL: requestedURL,
                    stageURL: stageURL,
                    publishedURL: accessorURL
                )
                result = .success(WorkspaceCommitReceipt(
                    snapshot: makeSnapshot(url: accessorURL, inspection: published),
                    publishedURL: accessorURL,
                    retainedBackupURL: nil
                ))
            } catch {
                if publicationInvoked {
                    result = .failure(WorkspaceStoreError.publicationRecoveryRequired(recoveryEvidence(
                        sourceRevision: nil,
                        targetRevision: plan.targetPackageRevision,
                        urls: [requestedURL, accessorURL, stageURL]
                    )))
                } else {
                    result = .failure(error)
                }
            }
        }
        if let coordinationError {
            if publicationInvoked {
                throw WorkspaceStoreError.publicationRecoveryRequired(recoveryEvidence(
                    sourceRevision: nil,
                    targetRevision: plan.targetPackageRevision,
                    urls: [requestedURL, stageURL]
                ))
            }
            cleanupStage(stageURL)
            throw coordinationError
        }
        guard let result else {
            cleanupStage(stageURL)
            throw WorkspaceStoreError.writeFailure("coordinated create accessor did not run")
        }
        do {
            return try result.get()
        } catch {
            if !publicationInvoked { cleanupStage(stageURL) }
            throw error
        }
    }

    private func publishReplacement(
        plan: CueSchema3PackagePlan,
        stageURL: URL,
        snapshot: WorkspaceSnapshot
    ) throws -> WorkspaceCommitReceipt {
        let requestedURL = snapshot.packageURL
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<WorkspaceCommitReceipt, Error>?
        var publicationInvoked = false
        var recoveryURLs: [URL?] = [requestedURL, stageURL]

        coordinator.coordinate(writingItemAt: requestedURL, options: [], error: &coordinationError) { accessorURL in
            let backupName = ".\(requestedURL.deletingPathExtension().lastPathComponent).cue-prior-\(UUID().uuidString).cue"
            let adjacentBackupURL = accessorURL.deletingLastPathComponent()
                .appendingPathComponent(backupName, isDirectory: true)
            recoveryURLs.append(accessorURL)
            recoveryURLs.append(adjacentBackupURL)
            do {
                try requireStageBesideAccessor(stageURL: stageURL, accessorURL: accessorURL)
                let live = try CuePackagePlanner.inspect(
                    atCoordinatedAccessorURL: accessorURL,
                    fileManager: fileManager
                )
                guard live.packageRevision == snapshot.revision else {
                    throw WorkspaceStoreError.externalModification
                }
                try invoke(
                    .afterRevisionConfirmed,
                    requestedURL: requestedURL,
                    stageURL: stageURL,
                    adjacentBackupURL: adjacentBackupURL
                )

                publicationInvoked = true
                let returnedURL: URL?
                do {
                    returnedURL = try fileManager.replaceItemAt(
                        accessorURL,
                        withItemAt: stageURL,
                        backupItemName: backupName,
                        options: [.withoutDeletingBackupItem]
                    )
                } catch {
                    recoveryURLs.append(
                        (error as NSError).userInfo["NSFileOriginalItemLocationKey"] as? URL
                    )
                    throw error
                }
                recoveryURLs.append(returnedURL)
                guard let returnedURL, sameLogicalURL(returnedURL, accessorURL) else {
                    throw WorkspaceStoreError.writeFailure("safe replacement returned an ambiguous package URL")
                }
                try invoke(
                    .afterReplacement,
                    requestedURL: requestedURL,
                    stageURL: stageURL,
                    adjacentBackupURL: adjacentBackupURL,
                    publishedURL: returnedURL
                )

                let published = try CuePackagePlanner.inspect(
                    atCoordinatedAccessorURL: returnedURL,
                    fileManager: fileManager
                )
                let displaced = try CuePackagePlanner.inspect(
                    atCoordinatedAccessorURL: adjacentBackupURL,
                    fileManager: fileManager
                )
                guard published.packageRevision == plan.targetPackageRevision,
                      displaced.packageRevision == snapshot.revision else {
                    throw WorkspaceStoreError.invalidDocument("replacement did not preserve exact old and new packages")
                }
                let archivedBackup = try archiveBackup(
                    adjacentBackupURL,
                    sourceRevision: snapshot.revision,
                    nextTo: returnedURL
                )
                recoveryURLs.append(archivedBackup)
                try invoke(
                    .afterPublishedValidation,
                    requestedURL: requestedURL,
                    stageURL: stageURL,
                    adjacentBackupURL: archivedBackup,
                    publishedURL: returnedURL
                )
                result = .success(WorkspaceCommitReceipt(
                    snapshot: makeSnapshot(url: returnedURL, inspection: published),
                    publishedURL: returnedURL,
                    retainedBackupURL: archivedBackup
                ))
            } catch {
                if publicationInvoked {
                    result = .failure(WorkspaceStoreError.publicationRecoveryRequired(recoveryEvidence(
                        sourceRevision: snapshot.revision,
                        targetRevision: plan.targetPackageRevision,
                        urls: recoveryURLs
                    )))
                } else {
                    result = .failure(error)
                }
            }
        }
        if let coordinationError {
            if publicationInvoked {
                throw WorkspaceStoreError.publicationRecoveryRequired(recoveryEvidence(
                    sourceRevision: snapshot.revision,
                    targetRevision: plan.targetPackageRevision,
                    urls: recoveryURLs
                ))
            }
            cleanupStage(stageURL)
            throw coordinationError
        }
        guard let result else {
            cleanupStage(stageURL)
            throw WorkspaceStoreError.writeFailure("coordinated write accessor did not run")
        }
        do {
            return try result.get()
        } catch {
            if !publicationInvoked { cleanupStage(stageURL) }
            throw error
        }
    }

    private func archiveBackup(
        _ adjacentBackupURL: URL,
        sourceRevision: CuePackageRevision,
        nextTo publishedURL: URL
    ) throws -> URL {
        let directory = publishedURL.deletingLastPathComponent()
            .appendingPathComponent(".cue-backups", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let finalURL = directory.appendingPathComponent(
            "\(publishedURL.deletingPathExtension().lastPathComponent)-\(timestamp())-\(UUID().uuidString).cue",
            isDirectory: true
        )
        let archiveStage = directory.appendingPathComponent(
            ".archive-stage-\(UUID().uuidString).cue",
            isDirectory: true
        )
        do {
            try fileManager.copyItem(at: adjacentBackupURL, to: archiveStage)
            guard try CuePackagePlanner.inspect(
                atCoordinatedAccessorURL: archiveStage,
                fileManager: fileManager
            ).packageRevision == sourceRevision else {
                throw WorkspaceStoreError.invalidDocument("backup archive stage changed the prior package")
            }
            try fileManager.moveItem(at: archiveStage, to: finalURL)
            guard try CuePackagePlanner.inspect(
                atCoordinatedAccessorURL: finalURL,
                fileManager: fileManager
            ).packageRevision == sourceRevision else {
                throw WorkspaceStoreError.invalidDocument("retained backup does not match the prior package")
            }
            try fileManager.removeItem(at: adjacentBackupURL)
            pruneBackups(in: directory, preserving: finalURL)
            return finalURL
        } catch {
            if fileManager.fileExists(atPath: archiveStage.path) {
                try? fileManager.removeItem(at: archiveStage)
            }
            throw error
        }
    }

    private func pruneBackups(in directory: URL, preserving: URL) {
        guard let backups = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ).filter({ $0.pathExtension.lowercased() == "cue" }).sorted(by: {
            let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhs > rhs
        }) else { return }
        for old in backups.dropFirst(backupLimit) where old != preserving {
            try? fileManager.removeItem(at: old)
        }
    }

    private func requireStageBesideAccessor(stageURL: URL, accessorURL: URL) throws {
        let stageParent = stageURL.deletingLastPathComponent()
        let accessorParent = accessorURL.deletingLastPathComponent()
        guard try directoryIdentity(stageParent) == directoryIdentity(accessorParent) else {
            throw WorkspaceStoreError.externalModification
        }
    }

    private func directoryIdentity(_ url: URL) throws -> DirectoryIdentity {
        let values = try fileManager.attributesOfItem(atPath: url.path)
        guard let volume = (values[.systemNumber] as? NSNumber)?.uint64Value,
              let file = (values[.systemFileNumber] as? NSNumber)?.uint64Value else {
            throw WorkspaceStoreError.writeFailure("package parent identity is unavailable")
        }
        return DirectoryIdentity(volume: volume, file: file)
    }

    private func recoveryEvidence(
        sourceRevision: CuePackageRevision?,
        targetRevision: CuePackageRevision,
        urls: [URL?]
    ) -> WorkspacePublicationRecovery {
        var seen = Set<String>()
        let candidates = urls.compactMap { value -> WorkspaceRecoveryCandidate? in
            guard let value else { return nil }
            let url = value.standardizedFileURL
            guard seen.insert(url.path).inserted else { return nil }
            guard fileManager.fileExists(atPath: url.path) else {
                return WorkspaceRecoveryCandidate(url: url, state: .missing)
            }
            do {
                let revision = try CuePackagePlanner.inspect(
                    atCoordinatedAccessorURL: url,
                    fileManager: fileManager
                ).packageRevision
                if revision == targetRevision {
                    return WorkspaceRecoveryCandidate(url: url, state: .target)
                }
                if revision == sourceRevision {
                    return WorkspaceRecoveryCandidate(url: url, state: .source)
                }
                return WorkspaceRecoveryCandidate(url: url, state: .other(revision))
            } catch {
                return WorkspaceRecoveryCandidate(url: url, state: .unreadable)
            }
        }
        return WorkspacePublicationRecovery(
            sourceRevision: sourceRevision,
            targetRevision: targetRevision,
            candidates: candidates
        )
    }

    private func invoke(
        _ failpoint: WorkspaceTransactionFailpoint,
        requestedURL: URL,
        stageURL: URL,
        adjacentBackupURL: URL? = nil,
        publishedURL: URL? = nil
    ) throws {
        try transactionHook?(failpoint, WorkspaceTransactionContext(
            requestedURL: requestedURL,
            stageURL: stageURL,
            adjacentBackupURL: adjacentBackupURL,
            publishedURL: publishedURL
        ))
    }

    private func cleanupStage(_ stageURL: URL) {
        if fileManager.fileExists(atPath: stageURL.path) {
            try? fileManager.removeItem(at: stageURL)
        }
    }

    private func sameLogicalURL(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.resolvingSymlinksInPath() ==
            rhs.standardizedFileURL.resolvingSymlinksInPath()
    }

    private func validatePackageURL(_ url: URL) throws {
        guard url.pathExtension.lowercased() == "cue" else {
            throw WorkspaceStoreError.invalidDocument("workspace packages must use the .cue extension")
        }
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.string(from: Date())
    }

    private func directoryOrder(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.split(separator: "/").count
        let right = rhs.split(separator: "/").count
        return left == right ? lhs < rhs : left < right
    }
}
