//
//  ImageClassifierView.swift
//  CoreMLBasics
//
//  Created by Donggeun Lee on 5/6/26.
//

import SwiftUI
import PhotosUI
import CoreML
import Combine
 
// MARK: - ViewModel
@MainActor  // 이 클래스의 모든 메서드는 메인 스레드에서 실행
class ImageClassifierViewModel: ObservableObject {
    @Published var selectedImage: UIImage?
    @Published var results: [ClassificationResult] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
 
    // 추론 시간 측정 (학습용 — 실제 앱에선 필요 없음)
    @Published var inferenceTime: Double = 0
 
    private let coreMLService = CoreMLService()
 
    func classify() {
        guard let image = selectedImage else { return }
 
        // Task { }: 비동기 작업 시작
        // @MainActor 클래스 안이므로 UI 업데이트 안전
        Task {
            isLoading = true
            errorMessage = nil
            results = []
 
            let start = Date()
 
            do {
                // CoreMLService.classify()는 async throws
                // → await으로 결과 기다림, try로 에러 처리
                results = try await coreMLService.classify(image: image)
                inferenceTime = Date().timeIntervalSince(start) * 1000 // ms
            } catch {
                errorMessage = error.localizedDescription
            }
 
            isLoading = false
        }
    }
}
 
// MARK: - 메인 뷰
struct ImageClassifierView: View {
    @StateObject private var viewModel = ImageClassifierViewModel()
    @State private var photoItem: PhotosPickerItem?
 
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
 
                    // 1. 이미지 선택 영역
                    imagePickerSection
 
                    // 2. 분류 버튼
                    if viewModel.selectedImage != nil {
                        classifyButton
                    }
 
                    // 3. 로딩 인디케이터
                    if viewModel.isLoading {
                        loadingView
                    }
 
                    // 4. 결과 표시
                    if !viewModel.results.isEmpty {
                        resultsSection
                    }
 
                    // 5. 에러 표시
                    if let error = viewModel.errorMessage {
                        errorView(error)
                    }
 
                    // 6. 학습 노트
                    learningNotes
                }
                .padding()
            }
            .navigationTitle("Core ML 이미지 분류")
            .navigationBarTitleDisplayMode(.large)
        }
        // PhotosPickerItem이 바뀌면 UIImage로 변환
        .onChange(of: photoItem) { newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    viewModel.selectedImage = image
                    viewModel.results = []
                }
            }
        }
    }
 
    // MARK: - 서브뷰들
 
    private var imagePickerSection: some View {
        VStack(spacing: 12) {
            // 선택된 이미지 또는 플레이스홀더
            Group {
                if let image = viewModel.selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.1))
                        .frame(height: 200)
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.secondary)
                                Text("이미지를 선택하세요")
                                    .foregroundStyle(.secondary)
                            }
                        }
                }
            }
 
            // 사진 피커 버튼
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("사진 선택", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .foregroundStyle(.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
 
    private var classifyButton: some View {
        Button {
            viewModel.classify()
        } label: {
            HStack {
                Image(systemName: "brain.filled.head.profile")
                Text("Core ML로 분류하기")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(viewModel.isLoading)
    }
 
    private var loadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("추론 중...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
 
    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("분류 결과")
                    .font(.headline)
                Spacer()
                // 추론 시간 표시 (학습용)
                Text(String(format: "%.1fms", viewModel.inferenceTime))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())
            }
 
            ForEach(viewModel.results) { result in
                ResultRow(result: result)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
 
    private func errorView(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
 
    // 학습 포인트 설명 (학습용 UI)
    private var learningNotes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("📚 이번 주 학습 포인트")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
 
            ForEach([
                "VNCoreMLModel: .mlmodel을 Vision이 쓸 수 있게 래핑",
                "VNCoreMLRequest: 추론 요청 + 결과 콜백",
                "VNImageRequestHandler: 이미지 + 요청 실행",
                "async/await: 추론을 비동기로 처리"
            ], id: \.self) { note in
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color.blue.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
 
// MARK: - 결과 행 컴포넌트
struct ResultRow: View {
    let result: ClassificationResult
 
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(result.label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
                Text(result.confidencePercent)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(confidenceColor)
            }
 
            // 신뢰도 바
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.15))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(confidenceColor)
                        .frame(width: geo.size.width * CGFloat(result.confidence), height: 6)
                        .animation(.easeOut(duration: 0.5), value: result.confidence)
                }
            }
            .frame(height: 6)
        }
    }
 
    private var confidenceColor: Color {
        switch result.confidence {
        case 0.7...1.0: return .green
        case 0.4..<0.7: return .orange
        default: return .red
        }
    }
}
 
#Preview {
    ImageClassifierView()
}
 
