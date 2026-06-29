//
//  OKCompletionData.swift
//
//
//  Created by Kevin Hermawan on 02/01/24.
//

import Foundation

/// A structure that encapsulates options for controlling the behavior of content generation in the Ollama API.
public struct OKCompletionOptions: Encodable {
    
    public init(mirostat: Int? = nil, mirostatEta: Float? = nil, mirostatTau: Float? = nil, numCtx: Int? = nil, numGqa: Int? = nil, numGpu: Int? = nil, numThread: Int? = nil, repeatLastN: Int? = nil, repeatPenalty: Float? = nil, temperature: Float? = nil, seed: Int? = nil, stop: String? = nil, tfsZ: Float? = nil, numPredict: Int? = nil, topK: Int? = nil, topP: Float? = nil) {
        self.mirostat = mirostat
        self.mirostatEta = mirostatEta
        self.mirostatTau = mirostatTau
        self.numCtx = numCtx
        self.numGqa = numGqa
        self.numGpu = numGpu
        self.numThread = numThread
        self.repeatLastN = repeatLastN
        self.repeatPenalty = repeatPenalty
        self.temperature = temperature
        self.seed = seed
        self.stop = stop
        self.tfsZ = tfsZ
        self.numPredict = numPredict
        self.topK = topK
        self.topP = topP
    }

    /// Optional integer to enable Mirostat sampling for controlling perplexity. (0 = disabled, 1 = Mirostat, 2 = Mirostat 2.0)
    public var mirostat: Int?
    
    /// Optional float influencing the adjustment speed of the Mirostat algorithm. (Lower = slower adjustment)
    public var mirostatEta: Float?
    
    /// Optional float controlling the balance between coherence and diversity. (Lower = more focused text)
    public var mirostatTau: Float?
    
    /// Optional integer setting thae size of the context window for token generation.
    public var numCtx: Int?
    
    /// Optional integer for the number of GQA groups in the transformer layer, specific to some models.
    public var numGqa: Int?
    
    /// Optional integer indicating the number of layers to send to the GPU(s).
    public var numGpu: Int?
    
    /// Optional integer for the number of threads used in computation, recommended to match physical CPU cores.
    public var numThread: Int?
    
    /// Optional integer setting how far back the model checks to prevent repetition.
    public var repeatLastN: Int?
    
    /// Optional float setting the penalty strength for repetitions.
    public var repeatPenalty: Float?
    
    /// Optional float to control the model's creativity (higher = more creative).
    public var temperature: Float?
    
    /// Optional integer for setting a random number seed for generation consistency.
    public var seed: Int?
    
    /// Optional string defining stop sequences for the model to cease generation.
    public var stop: String?
    
    /// Optional float for tail free sampling, reducing impact of less probable tokens.
    public var tfsZ: Float?
    
    /// Optional integer for the maximum number of tokens to predict.
    public var numPredict: Int?
    
    /// Optional integer to limit nonsense generation and control answer diversity.
    public var topK: Int?
    
    /// Optional float working with top-k to balance text diversity and focus.
    public var topP: Float?
}
