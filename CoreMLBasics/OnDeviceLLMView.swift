// OnDeviceLLMView.swift
// Task 5: On-device LLM — Foundation Models Framework (iOS 26+)
// LanguageModelSession / streamResponse / @Generable 구조화 출력

import SwiftUI
import Combine
import FoundationModels

// MARK: - @Generable: 구조화 출력 타입
// LLM이 이 스키마에 맞게 constrained decoding으로 직접 생성
// JSON 파싱 없이 Swift 타입으로 바로 받음 — OpenAI JSON mode와의 핵심 차이
@Generable
struct TextInsight {
    @Guide(description: "감정 톤: positive, negative, neutral 중 하나")
    var sentiment: String
    @Guide(description: "핵심 키워드 최대 3개")
    var keywords: [String]
    @Guide(description: "한 문장으로 요약")
    var summary: String
}

// MARK: - View
struct OnDeviceLLMView: View {
    @StateObject private var vm = ViewModel()
    @State private var selectedTab = 0

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("모드", selection: $selectedTab) {
                    Text("스트리밍 채팅").tag(0)
                    Text("구조화 분석").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                if vm.modelUnavailable {
                    unavailableView
                } else if selectedTab == 0 {
                    chatView
                } else {
                    insightView
                }
            }
            .navigationTitle("온디바이스 LLM")
        }
    }

    // MARK: - 가용 불가
    private var unavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain.slash")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("Apple Intelligence를 사용할 수 없습니다.")
                .font(.headline)
            Text("iPhone 설정 → Apple Intelligence & Siri에서 활성화하세요.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 채팅 (스트리밍)
    private var chatView: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(vm.messages) { msg in
                            messageBubble(msg)
                        }
                        if vm.isStreaming {
                            streamingBubble
                        }
                    }
                    .padding()
                    .id("bottom")
                }
                .onChange(of: vm.streamingText) { _ in
                    withAnimation { proxy.scrollTo("bottom") }
                }
            }

            Divider()
            inputBar
        }
    }

    private func messageBubble(_ msg: ViewModel.Message) -> some View {
        HStack {
            if msg.role == .user { Spacer(minLength: 60) }
            Text(msg.content)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(msg.role == .user ? Color.accentColor : Color(.secondarySystemBackground))
                .foregroundColor(msg.role == .user ? .white : .primary)
                .cornerRadius(16)
            if msg.role == .assistant { Spacer(minLength: 60) }
        }
    }

    private var streamingBubble: some View {
        HStack {
            Text(vm.streamingText.isEmpty ? "…" : vm.streamingText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(16)
            Spacer(minLength: 60)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("메시지 입력...", text: $vm.input)
                .textFieldStyle(.roundedBorder)
            Button {
                Task { await vm.send() }
            } label: {
                Image(systemName: vm.isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(vm.isStreaming ? .red : .accentColor)
            }
            .disabled(vm.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !vm.isStreaming)
        }
        .padding()
    }

    // MARK: - 구조화 분석 (@Generable)
    private var insightView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("분석할 텍스트").font(.headline)
                    TextEditor(text: $vm.analysisInput)
                        .frame(height: 100)
                        .padding(6)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                    Button {
                        Task { await vm.analyzeText() }
                    } label: {
                        Label("구조화 분석", systemImage: "wand.and.sparkles")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .disabled(vm.isStreaming)
                }

                if vm.isStreaming {
                    ProgressView("분석 중…").frame(maxWidth: .infinity)
                }

                if let insight = vm.insight {
                    insightCard(insight)
                }

                // OpenAI JSON mode와 비교 설명
                VStack(alignment: .leading, spacing: 6) {
                    Text("vs OpenAI JSON mode").font(.caption.bold()).foregroundColor(.secondary)
                    Text("Foundation Models의 @Generable은 constrained decoding으로 모델이 토큰 생성 시점에 스키마를 강제 적용합니다. OpenAI JSON mode는 사후 파싱이라 유효하지 않은 JSON이 나올 수 있지만, @Generable은 컴파일 타임에 타입 안전성이 보장됩니다.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(10)
            }
            .padding()
        }
    }

    private func insightCard(_ insight: TextInsight) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("분석 결과").font(.headline)
            HStack {
                Text("감정").foregroundColor(.secondary)
                Spacer()
                Text(insight.sentiment)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(sentimentColor(insight.sentiment).opacity(0.2))
                    .foregroundColor(sentimentColor(insight.sentiment))
                    .cornerRadius(8)
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("키워드").foregroundColor(.secondary)
                HStack {
                    ForEach(insight.keywords, id: \.self) { kw in
                        Text(kw)
                            .font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.15))
                            .cornerRadius(8)
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("요약").foregroundColor(.secondary)
                Text(insight.summary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func sentimentColor(_ sentiment: String) -> Color {
        switch sentiment.lowercased() {
        case "positive": return .green
        case "negative": return .red
        default: return .gray
        }
    }
}

// MARK: - ViewModel
extension OnDeviceLLMView {
    @MainActor
    class ViewModel: ObservableObject {
        @Published var messages: [Message] = []
        @Published var input = ""
        @Published var isStreaming = false
        @Published var streamingText = ""
        @Published var analysisInput = "오늘 새로 나온 아이폰이 정말 마음에 들어. 카메라도 훨씬 좋아지고 배터리도 오래가서 너무 만족스럽다!"
        @Published var insight: TextInsight?
        @Published var modelUnavailable = false

        private var session: LanguageModelSession?

        struct Message: Identifiable {
            let id = UUID()
            let role: Role
            let content: String
            enum Role { case user, assistant }
        }

        init() {
            setupSession()
        }

        // MARK: - 세션 초기화
        // SystemLanguageModel.default.availability로 Apple Intelligence 가용 여부 확인
        private func setupSession() {
            let model = SystemLanguageModel.default
            guard case .available = model.availability else {
                modelUnavailable = true
                return
            }
            // trailing closure = system instructions (서버 없이 온디바이스)
            session = LanguageModelSession {
                "당신은 iOS 개발과 AI를 잘 아는 친절한 어시스턴트입니다. 간결하게 한국어로 답하세요."
            }
        }

        // MARK: - 스트리밍 응답
        // streamResponse: OpenAI streaming과 동일한 UX, 하지만 완전 온디바이스
        func send() async {
            guard let session,
                  !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

            let userText = input
            input = ""
            messages.append(Message(role: .user, content: userText))
            isStreaming = true
            streamingText = ""

            do {
                let stream = session.streamResponse(to: userText)
                for try await partial in stream {
                    streamingText = partial.content
                }
                messages.append(Message(role: .assistant, content: streamingText))
            } catch {
                messages.append(Message(role: .assistant, content: "오류: \(error.localizedDescription)"))
            }
            streamingText = ""
            isStreaming = false
        }

        // MARK: - @Generable 구조화 출력
        // respond(to:generating:): JSON 파싱 없이 Swift 타입으로 직접 수신
        func analyzeText() async {
            guard let session, !analysisInput.isEmpty else { return }
            isStreaming = true
            insight = nil
            do {
                let response = try await session.respond(
                    to: "다음 텍스트를 분석해주세요: \(analysisInput)",
                    generating: TextInsight.self
                )
                insight = response.content
            } catch {
                print("❌ 분석 실패: \(error)")
            }
            isStreaming = false
        }
    }
}

#Preview {
    OnDeviceLLMView()
}
