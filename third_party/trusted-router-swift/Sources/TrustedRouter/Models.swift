import Foundation

// MARK: - Generic Wrappers

public struct DataList<T: Codable & Sendable>: Codable, Sendable {
    public var data: [T]
}

// MARK: - Metadata Models

public struct ModelInfo: Codable, Sendable {
    public var id: String
    public var object: String?
    public var created: Int?
    public var ownedBy: String?
    
    enum CodingKeys: String, CodingKey {
        case id, object, created
        case ownedBy = "owned_by"
    }
}

public struct ProviderInfo: Codable, Sendable {
    public var id: String
    public var name: String?
}

public struct RegionInfo: Codable, Sendable {
    public var id: String
    public var name: String?
}

public struct CreditsResponse: Codable, Sendable {
    public var balance: Double
    public var currency: String?
}

// MARK: - Chat Models

public struct ChatCompletionChunk: Codable, Sendable {
    public var id: String?
    public var object: String?
    public var created: Int?
    public var model: String?
    public var choices: [Choice]
    
    public struct Choice: Codable, Sendable {
        public var index: Int?
        public var delta: Delta?
        public var finishReason: String?
        
        enum CodingKeys: String, CodingKey {
            case index, delta
            case finishReason = "finish_reason"
        }
        
        public struct Delta: Codable, Sendable {
            public var role: String?
            public var content: String?
        }
    }
}

public struct ChatCompletion: Codable, Sendable {
    public var id: String
    public var object: String
    public var created: Int?
    public var model: String?
    public var choices: [Choice]
    public var usage: Usage?
    
    public struct Choice: Codable, Sendable {
        public var index: Int
        public var message: Message
        public var finishReason: String?
        
        enum CodingKeys: String, CodingKey {
            case index, message
            case finishReason = "finish_reason"
        }
        
        public struct Message: Codable, Sendable {
            public var role: String
            public var content: String?
        }
    }
    
    public struct Usage: Codable, Sendable {
        public var promptTokens: Int
        public var completionTokens: Int
        public var totalTokens: Int
        
        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
}

// MARK: - Other API Models

public struct EmbeddingResponse: Codable, Sendable {
    public var object: String?
    public var data: [Embedding]
    public var model: String
    public var usage: ChatCompletion.Usage?
    
    public struct Embedding: Codable, Sendable {
        public var index: Int
        public var object: String?
        public var embedding: [Double]
    }
}

public struct MessageResponse: Codable, Sendable {
    public var id: String
    public var type: String?
    public var role: String
    public var content: [Content]
    public var model: String
    public var stopReason: String?
    public var usage: Usage?
    
    enum CodingKeys: String, CodingKey {
        case id, type, role, content, model
        case stopReason = "stop_reason"
        case usage
    }
    
    public struct Content: Codable, Sendable {
        public var type: String
        public var text: String?
    }
    
    public struct Usage: Codable, Sendable {
        public var inputTokens: Int
        public var outputTokens: Int
        
        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }
}

public struct ResponseObject: Codable, Sendable {
    public var id: String
    public var object: String
    public var createdAt: Int?
    public var status: String?
    public var model: String?
    
    enum CodingKeys: String, CodingKey {
        case id, object, status, model
        case createdAt = "created_at"
    }
}

public struct ResponseInputTokens: Codable, Sendable {
    public var inputTokens: Int
    public var totalTokens: Int?
    
    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case totalTokens = "total_tokens"
    }
}

public struct BroadcastDestination: Codable, Sendable {
    public var id: String
    public var type: String
    public var name: String?
    public var endpoint: String?
    public var enabled: Bool?
    public var includeContent: Bool?
    public var method: String?
    
    enum CodingKeys: String, CodingKey {
        case id, type, name, endpoint, enabled, method
        case includeContent = "include_content"
    }
}

public struct CheckoutResponse: Codable, Sendable {
    public var url: String?
    public var status: String?
}

public struct EmptyResponse: Codable, Sendable {}

public struct AuthSessionResponse: Codable, Sendable {
    public var authenticated: Bool
    public var user: UserInfo?
    
    public struct UserInfo: Codable, Sendable {
        public var id: String
        public var email: String?
    }
}

public struct ActivityResponse: Codable, Sendable {
    public var activities: [Activity]
    
    public struct Activity: Codable, Sendable {
        public var id: String
        public var createdAt: Int?
        public var type: String?
        public var metadata: [String: String]?
        
        enum CodingKeys: String, CodingKey {
            case id, type, metadata
            case createdAt = "created_at"
        }
    }
}
