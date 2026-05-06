// DocumentScanService.swift
// Task 3: 신분증 문서 감지 → OCR → LLM 파싱
//
// Task 3에서 새로 추가된 것:
// - VNDetectDocumentSegmentationRequest (iOS 15+): 문서 외곽 4개 꼭짓점 감지
// OCR과 LLM 연동은 Task 2 + Phase 1 패턴 재사용

import Vision
import UIKit

struct DocumentScanResult {
    let croppedImage: UIImage?   // 문서 영역 크롭 이미지 (감지 성공 시)
    let rawText: String          // OCR 원문
}

class DocumentScanService {

    // ── Task 3 핵심: VNDetectDocumentSegmentationRequest ──
    // 이전까지 쓴 VNDetectBarcodesRequest, VNRecognizeTextRequest와 사용법은 동일
    // 결과 타입만 다름: VNRectangleObservation (4개 꼭짓점 좌표)
    func scan(image: UIImage) async throws -> DocumentScanResult {
        guard let cgImage = image.cgImage else { throw DocumentScanError.invalidImage }

        // Step 1: 문서 영역 감지 후 크롭
        let cropped = try await detectAndCrop(cgImage: cgImage, original: image)
        let target = cropped ?? image   // 감지 실패 시 원본 전체 OCR

        // Step 2: OCR — Task 2의 VNRecognizeTextRequest 재사용, .accurate 모드만 다름
        let text = try await recognizeText(in: target)

        return DocumentScanResult(croppedImage: cropped, rawText: text)
    }

    @available(iOS 15.0, *)
    private func detectAndCrop(cgImage: CGImage, original: UIImage) async throws -> UIImage? {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectDocumentSegmentationRequest { request, error in
                guard let obs = (request.results as? [VNRectangleObservation])?.first else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: self.crop(original, to: obs))
            }
            let handler = VNImageRequestHandler(cgImage: cgImage,
                                                orientation: original.cgImageOrientation,
                                                options: [:])
            try? handler.perform([request])
        }
    }

    private func recognizeText(in image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else { return "" }
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
                    .compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ko-KR", "en-US"]
            let handler = VNImageRequestHandler(cgImage: cgImage,
                                                orientation: image.cgImageOrientation,
                                                options: [:])
            try? handler.perform([request])
        }
    }

    // Vision boundingBox → CGImage 좌표 변환 후 크롭 (Task 2 좌표 변환과 동일 원리)
    private func crop(_ image: UIImage, to obs: VNRectangleObservation) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let rect = CGRect(x: obs.boundingBox.minX * w,
                          y: (1 - obs.boundingBox.maxY) * h,
                          width: obs.boundingBox.width * w,
                          height: obs.boundingBox.height * h)
        return cg.cropping(to: rect).map { UIImage(cgImage: $0) }
    }

    // OCR 원문을 Phase 1 OpenAIService.askStructured()에 넘길 프롬프트
    func parsingPrompt(for text: String) -> String {
        """
        아래는 신분증 OCR 텍스트입니다. 다음 JSON 형식으로만 응답하세요. 없는 항목은 null.
        {"name": "이름", "birth_date": "YYYY-MM-DD", "id_number_front": "앞 6자리만", "address": "주소"}

        OCR 텍스트:
        \(text)
        """
    }

    enum DocumentScanError: LocalizedError {
        case invalidImage
        var errorDescription: String? { "이미지를 처리할 수 없어요." }
    }
}
