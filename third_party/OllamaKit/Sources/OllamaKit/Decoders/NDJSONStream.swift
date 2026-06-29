//
//  NDJSONStream.swift
//
//
//  Created by Augustinas Malinauskas on 24/02/2024.
//

import Foundation

class NDJSONStream<T: Decodable>: IteratorProtocol, Sequence {
    private let data: Data
    private let decoder = JSONDecoder()
    private var lines: [String]
    private var currentIndex = 0

    init(data: Data) {
        self.data = data
        let content = String(decoding: data, as: UTF8.self)
        self.lines = content.split(separator: "\n").map(String.init)
    }
    
    func next() -> T? {
        guard currentIndex < lines.count else { return nil }
        
        let line = lines[currentIndex]
        currentIndex += 1
        
        do {
            let lineData = Data(line.utf8)
            return try decoder.decode(T.self, from: lineData)
        } catch {
            print("Error decoding JSON line: \(error)")
            return nil
        }
    }
}
