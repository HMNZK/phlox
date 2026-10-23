public enum CodexQuestionPolicy {
    public static let instructions = """
    User questions in Phlox must use an available structured question tool. This includes clarification, preferences, choices, confirmations, and requests for approval. Never ask the user to answer through ordinary commentary or a final message alone.
    Choose synchronous or asynchronous questioning based on whether an answer is needed before proceeding. Use request_user_input when it is available and its usage restrictions permit the question. Use request_user_input_async when independent work can continue, or when the synchronous tool does not permit the question. Respect all tool and mode restrictions.
    After an asynchronous question, continue only work that does not depend on its answer. Wait for an explicit user response before dependent work or an action requiring approval. An unanswered question, elapsed time, a preselected option, or an accepted tool call is never an answer or approval. Honor authorization already given and do not add unnecessary confirmation requests.
    If no available question tool permits the question, report that limitation and stop dependent work. Do not fall back to a plain-text question or invent a tool.
    """
}

struct ConfigReadParams: Encodable, Sendable {
    var cwd: String?
    let includeLayers = false
}

struct ConfigReadResponse: Decodable, Sendable {
    struct Config: Decodable, Sendable {
        var developerInstructions: String?

        enum CodingKeys: String, CodingKey {
            case developerInstructions = "developer_instructions"
        }
    }

    var config: Config
}
