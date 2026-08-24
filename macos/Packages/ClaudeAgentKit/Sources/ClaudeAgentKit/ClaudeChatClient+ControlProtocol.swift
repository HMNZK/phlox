import Foundation
import StructuredChatKit

extension ClaudeChatClient {
    func handleControlRequest(_ event: [String: Any], generation: Int) async -> Bool {
        guard generation == spawnGeneration,
              interruptingControlGeneration != generation,
              let requestId = event["request_id"] as? String,
              let request = event["request"] as? [String: Any],
              request["subtype"] as? String == "can_use_tool",
              let toolName = request["tool_name"] as? String
        else { return false }

        guard toolName == "AskUserQuestion" else {
            guard pendingUserQuestions[requestId] == nil else { return true }
            let input = request["input"] as? [String: Any] ?? [:]

            if shouldAutoAllowToolPermission(for: toolName) {
                await sendToolPermissionAllow(
                    requestId: requestId,
                    updatedInput: input,
                    generation: generation
                )
                return true
            }

            let question = Self.makeToolPermissionQuestion(toolName: toolName, input: input)
            pendingUserQuestions[requestId] = PendingUserQuestion(
                input: input,
                questions: [question],
                generation: generation,
                permission: PendingToolPermission(toolName: toolName)
            )
            eventContinuation.yield(.userQuestionRequested(requestId: requestId, questions: [question]))
            return true
        }

        guard pendingUserQuestions[requestId] == nil,
              let input = request["input"] as? [String: Any],
              let questions = parseUserQuestions(from: input)
        else { return true }

        pendingUserQuestions[requestId] = PendingUserQuestion(
            input: input,
            questions: questions,
            generation: generation,
            permission: nil
        )
        eventContinuation.yield(.userQuestionRequested(requestId: requestId, questions: questions))
        return true
    }

    public func respondToUserQuestion(
        requestId: String,
        answers: [String: [String]]
    ) async {
        guard var pending = pendingUserQuestions[requestId],
              pending.generation == spawnGeneration,
              !pending.isResponding,
              !expiringUserQuestionIDs.contains(requestId),
              let transport
        else { return }

        let generation = pending.generation
        pending.isResponding = true
        pendingUserQuestions[requestId] = pending

        let line: Data
        do {
            let response: [String: Any]
            if pending.permission != nil {
                let answerKey = pending.questions.first?.answerKey
                let selectedLabel = answerKey.flatMap { answers[$0]?.first }
                if selectedLabel == "Allow" {
                    response = [
                        "behavior": "allow",
                        "updatedInput": pending.input,
                    ]
                } else {
                    response = [
                        "behavior": "deny",
                        "message": "Denied by user in Phlox",
                    ]
                }
            } else {
                var updatedInput = pending.input
                updatedInput["answers"] = projectAnswers(answers, for: pending.questions)
                response = [
                    "behavior": "allow",
                    "updatedInput": updatedInput,
                ]
            }
            line = try controlResponseLine(
                requestId: requestId,
                response: response
            )
        } catch {
            markUserQuestionResponseFailed(requestId: requestId, generation: generation)
            eventContinuation.yield(.error(message: "Failed to encode Claude user-question response: \(error)"))
            return
        }

        do {
            guard generation == spawnGeneration else { return }
            try await transport.send(line)
        } catch {
            guard markUserQuestionResponseFailed(requestId: requestId, generation: generation) else {
                return
            }
            eventContinuation.yield(.error(message: "Failed to send Claude user-question response: \(error)"))
            return
        }

        guard generation == spawnGeneration,
              let current = pendingUserQuestions[requestId],
              current.generation == generation,
              current.isResponding
        else { return }

        pendingUserQuestions.removeValue(forKey: requestId)
        eventContinuation.yield(.userQuestionResolved(
            requestId: requestId,
            outcome: .answered(answers: answers)
        ))
    }

    func expirePendingUserQuestions(
        generation: Int? = nil,
        sendDeny: Bool = true
    ) async {
        let pendingQuestions: [(String, PendingUserQuestion)] = pendingUserQuestions.compactMap {
            requestId, pending in
            guard (generation == nil || pending.generation == generation),
                  !expiringUserQuestionIDs.contains(requestId)
            else { return nil }
            expiringUserQuestionIDs.insert(requestId)
            return (requestId, pending)
        }
        for (requestId, pending) in pendingQuestions {
            defer { expiringUserQuestionIDs.remove(requestId) }
            if sendDeny,
               let permission = pending.permission,
               !pending.isResponding,
               pending.generation == spawnGeneration,
               let transport {
                do {
                    try await sendControlDeny(
                        requestId: requestId,
                        message: "Denied by user in Phlox",
                        using: transport,
                        generation: pending.generation
                    )
                } catch {
                    eventContinuation.yield(.error(
                        message: "Failed to deny expired Claude tool permission request for \(permission.toolName): \(error)"
                    ))
                }
            }
            pendingUserQuestions.removeValue(forKey: requestId)
            eventContinuation.yield(.userQuestionResolved(requestId: requestId, outcome: .expired))
        }
    }

    func sendControlDeny(
        requestId: String,
        message: String,
        using transport: any LineDelimitedTransport,
        generation: Int
    ) async throws {
        guard generation == spawnGeneration else { return }
        let line = try controlResponseLine(
            requestId: requestId,
            response: [
                "behavior": "deny",
                "message": message,
            ]
        )
        try await transport.send(line)
    }

    private func parseUserQuestions(from input: [String: Any]) -> [ChatUserQuestion]? {
        guard let rawQuestions = input["questions"] as? [[String: Any]] else { return nil }
        var questions: [ChatUserQuestion] = []
        questions.reserveCapacity(rawQuestions.count)

        for rawQuestion in rawQuestions {
            guard let question = rawQuestion["question"] as? String,
                  let header = rawQuestion["header"] as? String,
                  let rawOptions = rawQuestion["options"] as? [[String: Any]]
            else { return nil }

            var options: [ChatUserQuestionOption] = []
            options.reserveCapacity(rawOptions.count)
            for rawOption in rawOptions {
                guard let label = rawOption["label"] as? String else { return nil }
                options.append(ChatUserQuestionOption(
                    label: label,
                    description: rawOption["description"] as? String
                ))
            }
            questions.append(ChatUserQuestion(
                question: question,
                header: header,
                options: options,
                multiSelect: rawQuestion["multiSelect"] as? Bool ?? false
            ))
        }
        return questions
    }

    static func makeToolPermissionQuestion(toolName: String, input: [String: Any]) -> ChatUserQuestion {
        let safeToolName = Self.sanitizeToolPermissionText(toolName)
        let summary = Self.sanitizeToolPermissionText(
            Self.toolPermissionInputSummary(toolName: toolName, input: input)
        )
        let limitedSummary = Self.truncatedToolPermissionSummary(summary)
        let question = limitedSummary.isEmpty
            ? "Allow \(safeToolName)?"
            : "Allow \(safeToolName)? \(limitedSummary)"
        return ChatUserQuestion(
            question: question,
            header: safeToolName,
            options: [
                ChatUserQuestionOption(label: "Allow"),
                ChatUserQuestionOption(label: "Deny"),
            ],
            multiSelect: false
        )
    }

    static func truncatedToolPermissionSummary(_ summary: String, limit: Int = 200) -> String {
        guard summary.count > limit else { return summary }
        let notice = "…（全 \(summary.count) 文字）"
        return String(summary.prefix(max(0, limit - notice.count))) + notice
    }

    static func sanitizeToolPermissionText(_ text: String) -> String {
        var sanitized = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x09, 0x0A, 0x0D:
                sanitized.append(UnicodeScalar(0x20)!)
            case 0x00...0x08, 0x0B...0x0C, 0x0E...0x1F,
                 0x7F, 0x80...0x9F,
                 0x200B...0x200F,
                 0x061C,
                 0x2028...0x2029,
                 0x202A...0x202E,
                 0x2066...0x2069:
                continue
            default:
                sanitized.append(scalar)
            }
        }
        return String(sanitized)
    }

    private static func toolPermissionInputSummary(
        toolName: String,
        input: [String: Any]
    ) -> String {
        let preferredKey: String?
        switch toolName {
        case "Bash":
            preferredKey = "command"
        case "Edit", "Write", "Read", "NotebookEdit":
            preferredKey = "file_path"
        case "WebFetch":
            preferredKey = "url"
        default:
            preferredKey = nil
        }

        if let preferredKey, let value = input[preferredKey] as? String {
            return value
        }

        guard let data = try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]) else {
            return String(describing: input)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func shouldAutoAllowToolPermission(for toolName: String) -> Bool {
        // bypassPermissions と allowedTools は CLI 側で既に承認済みなので再確認しない。
        // preApprovalPolicy は turn 単位の結果だけを返し、ツール単位の判断を保持しないため、
        // approve をここでツール単位の許可へ拡張しない。
        currentPermissionMode == "bypassPermissions" || allowedTools.contains(toolName)
    }

    private func sendToolPermissionAllow(
        requestId: String,
        updatedInput: [String: Any],
        generation: Int
    ) async {
        guard let transport else { return }
        do {
            let line = try controlResponseLine(
                requestId: requestId,
                response: [
                    "behavior": "allow",
                    "updatedInput": updatedInput,
                ]
            )
            guard generation == spawnGeneration else { return }
            try await transport.send(line)
        } catch {
            eventContinuation.yield(.error(message: "Failed to send Claude tool permission response: \(error)"))
        }
    }

    private func projectAnswers(
        _ answers: [String: [String]],
        for questions: [ChatUserQuestion]
    ) -> [String: Any] {
        var projected: [String: Any] = [:]
        for question in questions {
            guard let selections = answers[question.question] else { continue }
            if question.multiSelect {
                projected[question.question] = selections
            } else if let first = selections.first {
                projected[question.question] = first
            }
        }
        return projected
    }

    private func controlResponseLine(
        requestId: String,
        response: [String: Any]
    ) throws -> Data {
        let object: [String: Any] = [
            "type": "control_response",
            "response": [
                "subtype": "success",
                "request_id": requestId,
                "response": response,
            ],
        ]
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        return data
    }

    @discardableResult
    private func markUserQuestionResponseFailed(requestId: String, generation: Int) -> Bool {
        guard var pending = pendingUserQuestions[requestId],
              pending.generation == generation,
              pending.isResponding
        else { return false }
        pending.isResponding = false
        pendingUserQuestions[requestId] = pending
        return true
    }
}
