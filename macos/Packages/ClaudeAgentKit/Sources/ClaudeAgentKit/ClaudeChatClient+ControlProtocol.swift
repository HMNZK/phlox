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
            guard let transport else { return true }
            do {
                try await sendControlDeny(
                    requestId: requestId,
                    message: "Phlox: per-tool permission prompts are not supported",
                    using: transport,
                    generation: generation
                )
            } catch {
                eventContinuation.yield(.error(message: "Failed to deny Claude tool permission request: \(error)"))
            }
            return true
        }

        guard pendingUserQuestions[requestId] == nil,
              let input = request["input"] as? [String: Any],
              let questions = parseUserQuestions(from: input)
        else { return true }

        pendingUserQuestions[requestId] = PendingUserQuestion(
            input: input,
            questions: questions,
            generation: generation
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
              let transport
        else { return }

        let generation = pending.generation
        pending.isResponding = true
        pendingUserQuestions[requestId] = pending

        let line: Data
        do {
            var updatedInput = pending.input
            updatedInput["answers"] = projectAnswers(answers, for: pending.questions)
            line = try controlResponseLine(
                requestId: requestId,
                response: [
                    "behavior": "allow",
                    "updatedInput": updatedInput,
                ]
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

    func expirePendingUserQuestions(generation: Int? = nil) {
        let requestIds = pendingUserQuestions.compactMap { requestId, pending in
            generation == nil || pending.generation == generation ? requestId : nil
        }
        for requestId in requestIds {
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
