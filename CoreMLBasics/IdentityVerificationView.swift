// IdentityVerificationView.swift
// Task 3: 얼굴 인식 + 신분증 스캔 통합 UI

import SwiftUI
import PhotosUI
import Combine

// MARK: - ViewModel

@MainActor
class IdentityVerificationViewModel: ObservableObject {
    @Published var faceImage: UIImage?
    @Published var faceResults: [FaceResult] = []

    @Published var documentImage: UIImage?
    @Published var scanResult: DocumentScanResult?
    @Published var parsedFields: [String: String] = [:]   // LLM JSON 파싱 결과

    @Published var isLoading = false
    @Published var loadingMessage = ""
    @Published var errorMessage: String?

    private let faceService = FaceDetectionService()
    private let documentService = DocumentScanService()
    private let openAIService = OpenAIService()

    func detectFaces(from image: UIImage) {
        faceImage = image
        faceResults = []
        errorMessage = nil
        Task {
            isLoading = true
            loadingMessage = "얼굴 인식 중..."
            faceResults = (try? await faceService.detect(in: image)) ?? []
            if faceResults.isEmpty { errorMessage = "얼굴을 감지하지 못했어요." }
            isLoading = false
        }
    }

    func scanDocument(from image: UIImage) {
        documentImage = image
        scanResult = nil
        parsedFields = [:]
        errorMessage = nil
        Task {
            isLoading = true
            do {
                // Step 1: Vision — 문서 감지 + OCR
                loadingMessage = "문서 인식 중..."
                let result = try await documentService.scan(image: image)
                scanResult = result
                guard !result.rawText.isEmpty else {
                    errorMessage = "텍스트를 인식하지 못했어요."
                    isLoading = false
                    return
                }

                // Step 2: Phase 1 LLM — OCR 원문 → JSON 구조화
                loadingMessage = "AI가 정보 분석 중..."
                let json = try await openAIService.askStructured(documentService.parsingPrompt(for: result.rawText))
                parsedFields = parseJSON(json)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func parseJSON(_ string: String) -> [String: String] {
        guard let data = string.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return dict.compactMapValues { $0 as? String }
    }
}

// MARK: - 메인 뷰

struct IdentityVerificationView: View {
    @StateObject private var viewModel = IdentityVerificationViewModel()
    @State private var selectedTab = 0
    @State private var facePhoto: PhotosPickerItem?
    @State private var docPhoto: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("모드", selection: $selectedTab) {
                    Text("얼굴 인식").tag(0)
                    Text("신분증 스캔").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                ScrollView {
                    if selectedTab == 0 { faceSection }
                    else { documentSection }
                }
            }
            .navigationTitle("인증 보조")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: facePhoto) { loadImage($0) { viewModel.detectFaces(from: $0) } }
        .onChange(of: docPhoto)  { loadImage($0) { viewModel.scanDocument(from: $0) } }
    }

    // MARK: - 얼굴 인식 섹션

    private var faceSection: some View {
        VStack(spacing: 16) {
            // 이미지 + 랜드마크 오버레이
            GeometryReader { geo in
                ZStack {
                    if let img = viewModel.faceImage {
                        Image(uiImage: img).resizable().scaledToFit()
                        FaceOverlayView(faces: viewModel.faceResults, frameSize: geo.size)
                    } else {
                        placeholder(icon: "person.crop.rectangle", message: "얼굴 사진을 선택하세요")
                    }
                }
            }
            .frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            photoPicker(item: $facePhoto, label: "사진 선택")

            if viewModel.isLoading { loadingRow }

            if !viewModel.faceResults.isEmpty {
                infoCard(title: "\(viewModel.faceResults.count)개 얼굴 감지됨", color: .green) {
                    ForEach(Array(viewModel.faceResults.enumerated()), id: \.offset) { i, face in
                        Text("얼굴 #\(i + 1) — 랜드마크 \((face.landmarks?.leftEye.count ?? 0) + (face.landmarks?.rightEye.count ?? 0))pt")
                            .font(.caption)
                    }
                }
            }

            if let err = viewModel.errorMessage { errorRow(err) }
        }
        .padding()
    }

    // MARK: - 신분증 스캔 섹션

    private var documentSection: some View {
        VStack(spacing: 16) {
            // 크롭된 문서 또는 플레이스홀더
            if let img = viewModel.scanResult?.croppedImage {
                Image(uiImage: img)
                    .resizable().scaledToFit().frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .topLeading) {
                        Label("문서 감지됨", systemImage: "checkmark.circle.fill")
                            .font(.caption2).padding(6)
                            .background(.green).foregroundStyle(.white)
                            .clipShape(Capsule()).padding(8)
                    }
            } else {
                placeholder(icon: "creditcard.viewfinder", message: "신분증 사진을 선택하세요")
                    .frame(height: 140)
            }

            photoPicker(item: $docPhoto, label: "신분증 사진 선택")

            if viewModel.isLoading { loadingRow }

            // OCR 원문
            if let text = viewModel.scanResult?.rawText, !text.isEmpty {
                infoCard(title: "OCR 원문", color: .gray) {
                    Text(text).font(.caption).foregroundStyle(.secondary)
                }
            }

            // LLM 파싱 결과
            if !viewModel.parsedFields.isEmpty {
                let labels = ["name": "이름", "birth_date": "생년월일",
                              "id_number_front": "주민번호 앞자리", "address": "주소"]
                infoCard(title: "AI 파싱 결과", color: .purple) {
                    ForEach(labels.sorted(by: { $0.key < $1.key }), id: \.key) { key, label in
                        HStack {
                            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                            Text(viewModel.parsedFields[key] ?? "—").font(.caption).fontWeight(.medium)
                        }
                    }
                }
            }

            if let err = viewModel.errorMessage { errorRow(err) }
        }
        .padding()
    }

    // MARK: - 공통 컴포넌트

    private var loadingRow: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text(viewModel.loadingMessage).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding()
    }

    private func errorRow(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange).font(.caption)
            .padding().background(Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func photoPicker(item: Binding<PhotosPickerItem?>, label: String) -> some View {
        PhotosPicker(selection: item, matching: .images) {
            Label(label, systemImage: "photo")
                .frame(maxWidth: .infinity).padding()
                .background(Color.blue.opacity(0.1)).foregroundStyle(.blue)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func placeholder(icon: String, message: String) -> some View {
        RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.08))
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: icon).font(.system(size: 36)).foregroundStyle(.secondary)
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
    }

    @ViewBuilder
    private func infoCard<Content: View>(title: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).fontWeight(.semibold).foregroundStyle(color)
            content()
        }
        .padding().frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func loadImage(_ item: PhotosPickerItem?, handler: @escaping (UIImage) -> Void) {
        Task {
            if let data = try? await item?.loadTransferable(type: Data.self),
               let image = UIImage(data: data) { handler(image) }
        }
    }
}

// MARK: - 얼굴 오버레이

struct FaceOverlayView: View {
    let faces: [FaceResult]
    let frameSize: CGSize

    var body: some View {
        ForEach(faces) { face in
            let rect = convertVisionRect(face.boundingBox, to: frameSize)
            ZStack {
                Rectangle().stroke(Color.green, lineWidth: 2)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)

                if let lm = face.landmarks {
                    let allPoints = lm.leftEye + lm.rightEye + lm.nose + lm.outerLips + lm.leftEyebrow + lm.rightEyebrow
                    ForEach(Array(allPoints.enumerated()), id: \.offset) { _, pt in
                        Circle().fill(Color.yellow).frame(width: 3, height: 3)
                            .position(x: pt.x * frameSize.width,
                                      y: (1 - pt.y) * frameSize.height)
                    }
                }
            }
        }
    }
}

#Preview {
    IdentityVerificationView()
}
