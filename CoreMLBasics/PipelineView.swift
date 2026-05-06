// PipelineView.swift
// Phase 2 마무리: 온디바이스 AI 파이프라인
//
// Task 2/3 (Vision OCR) → Task 4 (NL 언어감지) → Task 5 (Foundation Models 요약)
// 서버 호출 없이 기기 안에서 전체 파이프라인 실행

import SwiftUI
import PhotosUI
import Combine
import NaturalLanguage
import FoundationModels

struct PipelineView: View {
    @StateObject private var vm = ViewModel()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    imagePickerSection
                    if vm.hasImage {
                        pipelineSteps
                    }
                }
                .padding()
            }
            .navigationTitle("온디바이스 파이프라인")
        }
    }

    // MARK: - 이미지 선택
    private var imagePickerSection: some View {
        VStack(spacing: 12) {
            if let image = vm.selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .cornerRadius(12)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
                    .frame(height: 160)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "doc.text.viewfinder")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text("텍스트가 포함된 이미지를 선택하세요")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
            }

            HStack(spacing: 12) {
                PhotosPicker(selection: $vm.pickerItem, matching: .images) {
                    Label("사진 선택", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                }

                if vm.hasImage {
                    Button {
                        Task { await vm.runPipeline() }
                    } label: {
                        Label("파이프라인 실행", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(vm.isRunning ? Color.gray : Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .disabled(vm.isRunning)
                }
            }
        }
    }

    // MARK: - 파이프라인 단계
    private var pipelineSteps: some View {
        VStack(spacing: 12) {
            stepCard(
                step: 1,
                title: "Vision OCR",
                subtitle: "VNDetectDocumentSegmentationRequest → VNRecognizeTextRequest",
                state: vm.step1State,
                result: vm.ocrText.isEmpty ? nil : vm.ocrText
            )

            connector

            stepCard(
                step: 2,
                title: "언어 감지",
                subtitle: "NLLanguageRecognizer",
                state: vm.step2State,
                result: vm.languageResult
            )

            connector

            stepCard(
                step: 3,
                title: "온디바이스 요약",
                subtitle: "LanguageModelSession (Foundation Models)",
                state: vm.step3State,
                result: vm.summary.isEmpty ? nil : vm.summary,
                isStreaming: vm.isStreaming
            )
        }
    }

    private var connector: some View {
        Image(systemName: "arrow.down")
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
    }

    private func stepCard(step: Int, title: String, subtitle: String,
                          state: StepState, result: String?, isStreaming: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                stepBadge(step: step, state: state)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                stateIcon(state)
            }

            if state == .running {
                ProgressView().frame(maxWidth: .infinity)
            }

            if let result {
                Divider()
                Text(result)
                    .font(.caption)
                    .foregroundColor(state == .done ? .primary : .secondary)
                    .lineLimit(isStreaming ? nil : 6)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor(state), lineWidth: state == .done ? 1.5 : 0)
        )
    }

    private func stepBadge(step: Int, state: StepState) -> some View {
        Text("\(step)")
            .font(.caption.bold())
            .frame(width: 26, height: 26)
            .background(badgeColor(state))
            .foregroundColor(.white)
            .clipShape(Circle())
    }

    @ViewBuilder
    private func stateIcon(_ state: StepState) -> some View {
        switch state {
        case .waiting: Image(systemName: "circle").foregroundColor(.secondary)
        case .running: EmptyView()
        case .done:    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        case .failed:  Image(systemName: "xmark.circle.fill").foregroundColor(.red)
        }
    }

    private func badgeColor(_ state: StepState) -> Color {
        switch state {
        case .waiting: return .gray
        case .running: return .accentColor
        case .done:    return .green
        case .failed:  return .red
        }
    }

    private func borderColor(_ state: StepState) -> Color {
        state == .done ? .green.opacity(0.4) : .clear
    }
}

// MARK: - Step State
enum StepState { case waiting, running, done, failed }

// MARK: - ViewModel
extension PipelineView {
    @MainActor
    class ViewModel: ObservableObject {
        @Published var pickerItem: PhotosPickerItem? {
            didSet { Task { await loadImage() } }
        }
        @Published var selectedImage: UIImage?
        @Published var isRunning = false
        @Published var isStreaming = false

        // 단계별 상태
        @Published var step1State: StepState = .waiting
        @Published var step2State: StepState = .waiting
        @Published var step3State: StepState = .waiting

        // 단계별 결과
        @Published var ocrText = ""
        @Published var languageResult = ""
        @Published var summary = ""

        var hasImage: Bool { selectedImage != nil }

        private let docService = DocumentScanService()
        private let nlService = NLService()

        // MARK: - 이미지 로드
        private func loadImage() async {
            guard let item = pickerItem,
                  let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }
            selectedImage = image
            resetSteps()
        }

        private func resetSteps() {
            step1State = .waiting; step2State = .waiting; step3State = .waiting
            ocrText = ""; languageResult = ""; summary = ""
        }

        // MARK: - 파이프라인 실행
        func runPipeline() async {
            guard let image = selectedImage else { return }
            isRunning = true
            resetSteps()

            // Step 1: Vision OCR
            step1State = .running
            do {
                let result = try await docService.scan(image: image)
                ocrText = result.rawText.isEmpty ? "텍스트를 찾지 못했습니다." : result.rawText
                step1State = .done
            } catch {
                ocrText = "OCR 실패: \(error.localizedDescription)"
                step1State = .failed
                isRunning = false
                return
            }

            // Step 2: NL 언어 감지
            step2State = .running
            let langs = nlService.detectLanguage(ocrText)
            if let top = langs.first {
                let name = Locale.current.localizedString(forLanguageCode: top.language.rawValue)
                            ?? top.language.rawValue
                languageResult = "\(name) (\(String(format: "%.0f%%", top.confidence * 100)))"
            } else {
                languageResult = "감지 실패"
            }
            step2State = .done

            // Step 3: Foundation Models 온디바이스 요약
            step3State = .running
            let model = SystemLanguageModel.default
            guard case .available = model.availability else {
                summary = "Apple Intelligence를 사용할 수 없습니다.\n설정 → Apple Intelligence & Siri에서 활성화하세요."
                step3State = .failed
                isRunning = false
                return
            }

            let session = LanguageModelSession {
                "주어진 텍스트를 3문장 이내로 간결하게 요약하세요. 텍스트가 짧으면 핵심 내용만 한 문장으로 정리하세요."
            }

            do {
                isStreaming = true
                let stream = session.streamResponse(to: "다음 텍스트를 요약해주세요:\n\(ocrText)")
                for try await partial in stream {
                    summary = partial.content
                }
                step3State = .done
            } catch {
                summary = "요약 실패: \(error.localizedDescription)"
                step3State = .failed
            }
            isStreaming = false
            isRunning = false
        }
    }
}

#Preview {
    PipelineView()
}
