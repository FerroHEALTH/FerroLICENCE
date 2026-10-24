import Foundation
import Register

// register-check <base> <head>: compare the pull request's checkout with
// main's, print what it does, and exit 1 if it breaks a rule.

let args = CommandLine.arguments.dropFirst()
guard args.count == 2 else {
    FileHandle.standardError.write(Data("usage: register-check <base-folder> <head-folder>\n".utf8))
    exit(2)
}
let base: Snapshot
let head: Snapshot
do {
    base = try Snapshot.read(folder: URL(filePath: args[args.startIndex]))
    head = try Snapshot.read(folder: URL(filePath: args[args.startIndex + 1]))
} catch {
    FileHandle.standardError.write(Data("cannot read: \(error)\n".utf8))
    exit(2)
}
// Who opened the pull request and who pushed what this run checks, from the
// workflow. Without them nothing passes; a push by anyone but the author
// does not pass either, so a holder's pull request carries only their work.
let env = ProcessInfo.processInfo.environment
var outcome = RegisterCheck.run(base: base, head: head)
if let author = env["REGISTER_CHECK_AUTHOR"], !author.isEmpty, let actor = env["REGISTER_CHECK_ACTOR"], !actor.isEmpty {
    if actor.caseInsensitiveCompare(author) != .orderedSame {
        outcome.problems.append("`\(actor)` pushed to a pull request `\(author)` opened; only its author may change it")
    }
    outcome.problems += RegisterCheck.authorProblems(author, base: base, outcome: outcome)
} else {
    outcome.problems.append("the check was not told who opened the pull request (REGISTER_CHECK_AUTHOR, REGISTER_CHECK_ACTOR)")
}
let summary = outcome.summary(keys: (try? Keys(head)) ?? Keys())
print(summary, terminator: "")
if let path = ProcessInfo.processInfo.environment["GITHUB_STEP_SUMMARY"], let file = FileHandle(forWritingAtPath: path) {
    _ = try? file.seekToEnd()
    try? file.write(contentsOf: Data("## Register check\n\n\(summary)".utf8))
}
exit(outcome.passed ? 0 : 1)
