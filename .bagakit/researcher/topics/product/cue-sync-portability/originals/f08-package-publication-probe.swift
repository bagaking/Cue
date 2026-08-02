import Foundation

private enum ProbeError: Error, CustomStringConvertible {
    case conflict
    case invalid(String)
    case coordination(String)

    var description: String {
        switch self {
        case .conflict:
            return "expected revision changed"
        case let .invalid(message), let .coordination(message):
            return message
        }
    }
}

private let manager = FileManager.default

private func describe(_ error: Error) -> String {
    let value = error as NSError
    return "\(String(describing: error)); \(value.domain)(\(value.code)): \(value.localizedDescription); userInfo=\(value.userInfo)"
}

private func syncedWrite(_ value: String, to url: URL) throws {
    try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(value.utf8).write(to: url, options: [])
    let handle = try FileHandle(forWritingTo: url)
    try handle.synchronize()
    try handle.close()
}

private func writePackage(_ url: URL, generation: String) throws {
    try manager.createDirectory(at: url, withIntermediateDirectories: false)
    try syncedWrite(generation, to: url.appendingPathComponent("generation.txt"))
    try syncedWrite("a:\(generation)", to: url.appendingPathComponent("records/a.txt"))
    try syncedWrite("b:\(generation)", to: url.appendingPathComponent("records/b.txt"))
}

@discardableResult
private func validatePackage(_ url: URL) throws -> String {
    let generation = try String(contentsOf: url.appendingPathComponent("generation.txt"), encoding: .utf8)
    let a = try String(contentsOf: url.appendingPathComponent("records/a.txt"), encoding: .utf8)
    let b = try String(contentsOf: url.appendingPathComponent("records/b.txt"), encoding: .utf8)
    guard a == "a:\(generation)", b == "b:\(generation)" else {
        throw ProbeError.invalid("hybrid package at \(url.lastPathComponent)")
    }
    return generation
}

private func commit(
    live: URL,
    stage: URL,
    expected: String,
    backupName: String,
    holdMilliseconds: UInt64,
    terminateBeforePublish: Bool,
    terminateAfterPublish: Bool
) throws {
    let coordinator = NSFileCoordinator(filePresenter: nil)
    var coordinationError: NSError?
    var accessorResult: Result<Void, Error>?
    coordinator.coordinate(writingItemAt: live, options: [], error: &coordinationError) { coordinatedLive in
        do {
            guard try validatePackage(coordinatedLive) == expected else {
                throw ProbeError.conflict
            }
            if holdMilliseconds > 0 {
                Thread.sleep(forTimeInterval: Double(holdMilliseconds) / 1_000)
            }
            if terminateBeforePublish {
                fflush(nil)
                abort()
            }
            _ = try manager.replaceItemAt(
                coordinatedLive,
                withItemAt: stage,
                backupItemName: backupName,
                options: [.withoutDeletingBackupItem]
            )
            if terminateAfterPublish {
                fflush(nil)
                abort()
            }
            accessorResult = .success(())
        } catch {
            accessorResult = .failure(error)
        }
    }
    if let coordinationError {
        throw coordinationError
    }
    guard let accessorResult else {
        throw ProbeError.coordination("coordinator accessor did not run")
    }
    try accessorResult.get()
}

private func makeRoot(_ label: String) throws -> URL {
    let url = manager.temporaryDirectory.appendingPathComponent("cue-publication-\(label)-\(UUID().uuidString)")
    try manager.createDirectory(at: url, withIntermediateDirectories: false)
    return url
}

private func runChild() -> Never {
    let arguments = CommandLine.arguments
    guard arguments.count == 9 else {
        fputs("invalid child arguments\n", stderr)
        exit(64)
    }
    do {
        try commit(
            live: URL(fileURLWithPath: arguments[2]),
            stage: URL(fileURLWithPath: arguments[3]),
            expected: arguments[4],
            backupName: arguments[5],
            holdMilliseconds: UInt64(arguments[6]) ?? 0,
            terminateBeforePublish: arguments[7] == "before",
            terminateAfterPublish: arguments[7] == "after"
        )
        print("success \(arguments[8])")
        exit(0)
    } catch ProbeError.conflict {
        print("conflict \(arguments[8])")
        exit(73)
    } catch {
        fputs("error \(arguments[8]): \(describe(error))\n", stderr)
        exit(74)
    }
}

private func childProcess(
    executable: URL,
    live: URL,
    stage: URL,
    expected: String,
    backupName: String,
    holdMilliseconds: UInt64,
    terminationPoint: String,
    label: String
) -> Process {
    let process = Process()
    process.executableURL = executable
    process.arguments = [
        "--child",
        live.path,
        stage.path,
        expected,
        backupName,
        String(holdMilliseconds),
        terminationPoint,
        label,
    ]
    return process
}

private func runProbe() throws {
    let executable = URL(fileURLWithPath: CommandLine.arguments[0])

    let successRoot = try makeRoot("success")
    defer { try? manager.removeItem(at: successRoot) }
    let successLive = successRoot.appendingPathComponent("Workspace.cue")
    let successStage = successRoot.appendingPathComponent(".stage.cue")
    try writePackage(successLive, generation: "old")
    try writePackage(successStage, generation: "new")
    try commit(
        live: successLive,
        stage: successStage,
        expected: "old",
        backupName: "prior.cue",
        holdMilliseconds: 0,
        terminateBeforePublish: false,
        terminateAfterPublish: false
    )
    guard try validatePackage(successLive) == "new",
          try validatePackage(successRoot.appendingPathComponent("prior.cue")) == "old" else {
        throw ProbeError.invalid("successful replacement did not retain complete old and new packages")
    }
    print("PASS success: live=new backup=old")

    let preRoot = try makeRoot("pre")
    defer { try? manager.removeItem(at: preRoot) }
    let preLive = preRoot.appendingPathComponent("Workspace.cue")
    let preStage = preRoot.appendingPathComponent(".stage.cue")
    try writePackage(preLive, generation: "old")
    try writePackage(preStage, generation: "new")
    let preKilled = childProcess(
        executable: executable,
        live: preLive,
        stage: preStage,
        expected: "old",
        backupName: "prior-pre.cue",
        holdMilliseconds: 0,
        terminationPoint: "before",
        label: "pre-killed"
    )
    try preKilled.run()
    preKilled.waitUntilExit()
    guard preKilled.terminationReason == .uncaughtSignal,
          try validatePackage(preLive) == "old",
          try validatePackage(preStage) == "new",
          !manager.fileExists(atPath: preRoot.appendingPathComponent("prior-pre.cue").path) else {
        throw ProbeError.invalid("pre-publication process death changed the live package")
    }
    print("PASS pre-publication stop: live=old stage=new")

    let killedRoot = try makeRoot("killed")
    defer { try? manager.removeItem(at: killedRoot) }
    let killedLive = killedRoot.appendingPathComponent("Workspace.cue")
    let killedStage = killedRoot.appendingPathComponent(".stage.cue")
    try writePackage(killedLive, generation: "old")
    try writePackage(killedStage, generation: "new")
    let killed = childProcess(
        executable: executable,
        live: killedLive,
        stage: killedStage,
        expected: "old",
        backupName: "prior-killed.cue",
        holdMilliseconds: 0,
        terminationPoint: "after",
        label: "killed"
    )
    try killed.run()
    killed.waitUntilExit()
    guard killed.terminationReason == .uncaughtSignal,
          try validatePackage(killedLive) == "new",
          try validatePackage(killedRoot.appendingPathComponent("prior-killed.cue")) == "old" else {
        throw ProbeError.invalid("post-publication process death lost a complete package")
    }
    print("PASS post-publication abort: live=new backup=old")

    let raceRoot = try makeRoot("race")
    defer { try? manager.removeItem(at: raceRoot) }
    let raceLive = raceRoot.appendingPathComponent("Workspace.cue")
    let stageA = raceRoot.appendingPathComponent(".stage-a.cue")
    let stageB = raceRoot.appendingPathComponent(".stage-b.cue")
    try writePackage(raceLive, generation: "base")
    try writePackage(stageA, generation: "writer-a")
    try writePackage(stageB, generation: "writer-b")
    let writerA = childProcess(
        executable: executable,
        live: raceLive,
        stage: stageA,
        expected: "base",
        backupName: "prior-a.cue",
        holdMilliseconds: 350,
        terminationPoint: "return",
        label: "a"
    )
    let writerB = childProcess(
        executable: executable,
        live: raceLive,
        stage: stageB,
        expected: "base",
        backupName: "prior-b.cue",
        holdMilliseconds: 0,
        terminationPoint: "return",
        label: "b"
    )
    try writerA.run()
    Thread.sleep(forTimeInterval: 0.05)
    try writerB.run()
    writerA.waitUntilExit()
    writerB.waitUntilExit()
    let statuses = [writerA.terminationStatus, writerB.terminationStatus].sorted()
    guard statuses == [0, 73],
          ["writer-a", "writer-b"].contains(try validatePackage(raceLive)) else {
        throw ProbeError.invalid("same-revision writers did not produce exactly one winner")
    }
    print("PASS two processes: exactly one success and one conflict; live is complete")
}

if CommandLine.arguments.dropFirst().first == "--child" {
    runChild()
}

do {
    try runProbe()
} catch {
    fputs("FAIL: \(describe(error))\n", stderr)
    exit(1)
}
