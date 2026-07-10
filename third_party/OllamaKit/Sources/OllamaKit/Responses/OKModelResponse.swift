//
//  OKModelResponse.swift
//
//
//  Created by Kevin Hermawan on 10/11/23.
//

import Foundation

/// A structure that represents the available models from the Ollama API.
public struct OKModelResponse: Decodable {
    /// An array of ``Model`` instances, each representing a specific model available in the Ollama API.
    public let models: [Model]
    
    public struct ModelDetails: Decodable {
        public let parentModel: String
        public let format: String
        public let families: [String]?
        public let parameterSize: String?
        public let quantizationLevel: String?
    }
    
    /// A structure that details individual models.
    public struct Model: Decodable {
        /// A string representing the name of the model.
        public let name: String
        
        /// A string representing the model
        public let model: String
        
        /// A string containing a digest or hash of the model, typically used for verification or identification.
        public let digest: String
        
        /// An integer indicating the size of the model, often in bytes.
        public let size: Int
        
        /// A `Date` representing the last modification date of the model.
        public let modifiedAt: Date
        
        /// A structure representing model details
        public let details: ModelDetails
    }
}
