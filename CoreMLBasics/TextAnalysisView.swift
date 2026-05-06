// TextAnalysisView.swift
// Task 4: Natural Language Framework UI

import SwiftUI
import Combine
import NaturalLanguage

struct TextAnalysisView: View {
    @StateObject private var vm = ViewModel()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    inputSection
                    if vm.hasResult {
                        languageSection
                        tokenSection
                        entitySection
                        similaritySection
                    }
                }
                .padding()
            }
            .navigationTitle("텍스트 분석")
        }
    }

    // MARK: - 입력
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("분석할 텍스트").font(.headline)
            TextEditor(text: $vm.inputText)
                .frame(height: 120)
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
            Button(action: vm.analyze) {
                Label("분석", systemImage: "text.magnifyingglass")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
    }

    // MARK: - 언어 감지
    private var languageSection: some View {
        resultCard(title: "언어 감지") {
            ForEach(vm.languages, id: \.language) { item in
                HStack {
                    Text(Locale.current.localizedString(forLanguageCode: item.language.rawValue) ?? item.language.rawValue)
                    Spacer()
                    ProgressView(value: item.confidence)
                        .frame(width: 80)
                    Text(String(format: "%.0f%%", item.confidence * 100))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - 토큰 통계
    private var tokenSection: some View {
        resultCard(title: "토큰 통계") {
            if let s = vm.stats {
                HStack(spacing: 0) {
                    statCell(label: "단어", value: s.wordCount)
                    Divider().frame(height: 40)
                    statCell(label: "문장", value: s.sentenceCount)
                    Divider().frame(height: 40)
                    statCell(label: "문단", value: s.paragraphCount)
                }
            }
        }
    }

    // MARK: - 개체명 인식
    private var entitySection: some View {
        resultCard(title: "개체명 인식 (NER)") {
            if vm.entities.isEmpty {
                Text("감지된 개체 없음").foregroundColor(.secondary).font(.caption)
            } else {
                FlowLayout(items: vm.entities) { entity in
                    entityChip(entity)
                }
            }
        }
    }

    // MARK: - 유사도
    private var similaritySection: some View {
        resultCard(title: "텍스트 유사도") {
            VStack(alignment: .leading, spacing: 8) {
                Text("비교 텍스트").font(.caption).foregroundColor(.secondary)
                TextField("비교할 문장 입력...", text: $vm.compareText)
                    .textFieldStyle(.roundedBorder)
                Button("유사도 계산") { vm.computeSimilarity() }
                    .buttonStyle(.bordered)
                if let score = vm.similarityScore {
                    HStack {
                        Text("유사도")
                        Spacer()
                        Text(String(format: "%.3f", score))
                            .font(.title3.bold())
                            .foregroundColor(score > 0.7 ? .green : score > 0.4 ? .orange : .red)
                    }
                    ProgressView(value: max(0, score))
                } else if vm.similarityUnavailable {
                    Text("현재 언어의 임베딩 모델을 불러올 수 없습니다.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - 헬퍼 뷰
    private func resultCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func statCell(label: String, value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.title2.bold())
            Text(label).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func entityChip(_ entity: EntityResult) -> some View {
        HStack(spacing: 4) {
            Text(entity.text).font(.caption)
            Text(entity.tag.displayName)
                .font(.caption2)
                .padding(.horizontal, 4)
                .background(tagColor(entity.tag).opacity(0.2))
                .cornerRadius(4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tagColor(entity.tag).opacity(0.1))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(tagColor(entity.tag).opacity(0.4), lineWidth: 1))
    }

    private func tagColor(_ tag: NLTag) -> Color {
        switch tag {
        case .personalName:    return .blue
        case .placeName:       return .green
        case .organizationName: return .orange
        default:               return .gray
        }
    }
}

// MARK: - ViewModel
extension TextAnalysisView {
    @MainActor
    class ViewModel: ObservableObject {
        @Published var inputText = "Apple은 캘리포니아 쿠퍼티노에 본사를 둔 기술 기업으로, 팀 쿡이 CEO를 맡고 있습니다."
        @Published var compareText = ""
        @Published var languages: [(language: NLLanguage, confidence: Double)] = []
        @Published var stats: TokenStats?
        @Published var entities: [EntityResult] = []
        @Published var similarityScore: Double?
        @Published var similarityUnavailable = false

        var hasResult: Bool { !languages.isEmpty }

        private let nlService = NLService()

        func analyze() {
            guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            languages = nlService.detectLanguage(inputText)
            stats = nlService.tokenStats(inputText)
            entities = nlService.extractEntities(inputText)
            similarityScore = nil
            similarityUnavailable = false
        }

        func computeSimilarity() {
            guard !compareText.isEmpty else { return }
            let lang = languages.first?.language ?? .english
            if let score = nlService.similarity(between: inputText, and: compareText, language: lang) {
                similarityScore = score
                similarityUnavailable = false
            } else {
                similarityUnavailable = true
            }
        }
    }
}

// MARK: - FlowLayout (칩 레이아웃)
struct FlowLayout<Item: Identifiable, Content: View>: View where Item.ID: Equatable {
    let items: [Item]
    let content: (Item) -> Content
    @State private var totalHeight = CGFloat.zero

    var body: some View {
        GeometryReader { geo in
            self.generateContent(in: geo)
        }
        .frame(height: totalHeight)
    }

    private func generateContent(in geo: GeometryProxy) -> some View {
        var width = CGFloat.zero
        var height = CGFloat.zero
        return ZStack(alignment: .topLeading) {
            ForEach(items) { item in
                content(item)
                    .alignmentGuide(.leading) { d in
                        if abs(width - d.width) > geo.size.width {
                            width = 0; height -= d.height + 6
                        }
                        let result = width
                        if item.id == items.last?.id { width = 0 } else { width -= d.width + 6 }
                        return result
                    }
                    .alignmentGuide(.top) { _ in
                        let result = height
                        if item.id == items.last?.id { height = 0 }
                        return result
                    }
            }
        }
        .background(viewHeightReader($totalHeight))
    }

    private func viewHeightReader(_ binding: Binding<CGFloat>) -> some View {
        GeometryReader { geo in
            Color.clear.preference(key: HeightPreferenceKey.self, value: geo.size.height)
        }
        .onPreferenceChange(HeightPreferenceKey.self) { binding.wrappedValue = $0 }
    }
}

private struct HeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#Preview {
    TextAnalysisView()
}
