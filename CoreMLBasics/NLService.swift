// NLService.swift
// Task 4: Natural Language Framework
// NLLanguageRecognizer / NLTagger(NER) / NLEmbedding

import NaturalLanguage

struct EntityResult: Identifiable {
    let id = UUID()
    let text: String
    let tag: NLTag
}

struct TokenStats {
    let wordCount: Int
    let sentenceCount: Int
    let paragraphCount: Int
}

class NLService {

    // MARK: - 언어 감지
    // NLLanguageRecognizer: 텍스트를 분석해 언어와 확신도 반환
    func detectLanguage(_ text: String) -> [(language: NLLanguage, confidence: Double)] {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.languageHypotheses(withMaximum: 3)
            .sorted { $0.value > $1.value }
            .map { (language: $0.key, confidence: $0.value) }
    }

    // MARK: - 토큰 통계
    // NLTokenizer: 텍스트를 단어/문장/문단 단위로 분리
    func tokenStats(_ text: String) -> TokenStats {
        func count(_ unit: NLTokenUnit) -> Int {
            let tokenizer = NLTokenizer(unit: unit)
            tokenizer.string = text
            var n = 0
            tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { _, _ in
                n += 1
                return true
            }
            return n
        }
        return TokenStats(
            wordCount: count(.word),
            sentenceCount: count(.sentence),
            paragraphCount: count(.paragraph)
        )
    }

    // MARK: - 개체명 인식 (NER)
    // NLTagger: 텍스트에서 인명/지명/기관명 등 개체 추출
    // .nameType 스킴은 .personalName / .placeName / .organizationName 태그 반환
    func extractEntities(_ text: String) -> [EntityResult] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text

        // 언어 힌트 제공 — 자동 감지가 짧은 텍스트에서 실패하는 경우 방어
        if let dominant = detectLanguage(text).first {
            tagger.setLanguage(dominant.language, range: text.startIndex..<text.endIndex)
        }

        var results: [EntityResult] = []
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
        let targetTags: [NLTag] = [.personalName, .placeName, .organizationName]

        tagger.enumerateTags(in: text.startIndex..<text.endIndex,
                             unit: .word,
                             scheme: .nameType,
                             options: options) { tag, range in
            if let tag, targetTags.contains(tag) {
                results.append(EntityResult(text: String(text[range]), tag: tag))
            }
            return true
        }
        return results
    }

    // MARK: - 텍스트 유사도
    // NLEmbedding: 단어/문장을 벡터로 변환해 코사인 유사도 계산
    // sentenceEmbedding은 iOS 14+ / 영어·중국어·스페인어 지원
    // 한국어는 wordEmbedding으로 폴백
    func similarity(between a: String, and b: String, language: NLLanguage = .korean) -> Double? {
        // 문장 임베딩 우선 시도
        // distance(between:and:distanceType:) 는 NLDistance(= Double) 반환 — optional 아님
        if let embedding = NLEmbedding.sentenceEmbedding(for: language) {
            return 1 - embedding.distance(between: a, and: b, distanceType: .cosine)
        }
        // 단어 임베딩 폴백: 각 텍스트의 첫 토큰으로 단순 비교
        if let embedding = NLEmbedding.wordEmbedding(for: language) {
            let tokenA = firstWord(a), tokenB = firstWord(b)
            return 1 - embedding.distance(between: tokenA, and: tokenB, distanceType: .cosine)
        }
        return nil
    }

    private func firstWord(_ text: String) -> String {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var word = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            word = String(text[range])
            return false // 첫 토큰만
        }
        return word
    }
}

// MARK: - NLTag 표시 이름
extension NLTag {
    var displayName: String {
        switch self {
        case .personalName:    return "인물"
        case .placeName:       return "장소"
        case .organizationName: return "기관"
        default:               return rawValue
        }
    }

    var color: String {   // SwiftUI Color name
        switch self {
        case .personalName:    return "blue"
        case .placeName:       return "green"
        case .organizationName: return "orange"
        default:               return "gray"
        }
    }
}
