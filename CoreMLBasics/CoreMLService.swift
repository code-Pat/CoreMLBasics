//
//  CoreMLService.swift
//  CoreMLBasics
//
//  Created by Donggeun Lee on 5/6/26.
//

import CoreML
import Vision
import UIKit
 
// MARK: - 결과 모델
struct ClassificationResult: Identifiable {
    let id = UUID()
    let label: String       // 예: "cat", "golden retriever"
    let confidence: Float   // 0.0 ~ 1.0
 
    var confidencePercent: String {
        String(format: "%.1f%%", confidence * 100)
    }
}
 
// MARK: - Core ML 서비스
class CoreMLService {
 
    // lazy: 처음 사용할 때만 로드 (앱 시작 시 불필요한 메모리 사용 방지)
    // ⚠️ 학습 포인트: 모델을 앱 번들에 추가해야 이 코드가 작동함
    //    Xcode > 프로젝트 타겟 > Build Phases > Copy Bundle Resources에 .mlmodel 추가
    private lazy var visionModel: VNCoreMLModel? = {
        do {
            // Step 1: Core ML 모델 설정
            let config = MLModelConfiguration()
            config.computeUnits = .all  // CPU + GPU + Neural Engine 자동 선택
 
            // Step 2: 모델 인스턴스 생성
            // MobileNetV2는 Apple 공식 모델 페이지에서 다운로드
            // https://developer.apple.com/machine-learning/models/
            let coreMLModel = try MobileNetV2(configuration: config)
 
            // Step 3: Vision이 쓸 수 있게 VNCoreMLModel로 래핑
            return try VNCoreMLModel(for: coreMLModel.model)
 
        } catch {
            print("❌ 모델 로드 실패: \(error)")
            return nil
        }
    }()
 
    // MARK: - 이미지 분류 (메인 함수)
    // async throws: 추론은 시간이 걸리고 실패할 수 있으므로 비동기 + 에러 처리
    func classify(image: UIImage) async throws -> [ClassificationResult] {
        guard let visionModel = visionModel else {
            throw CoreMLError.modelNotLoaded
        }
 
        // UIImage → CGImage 변환 (Vision은 CGImage를 입력으로 받음)
        guard let cgImage = image.cgImage else {
            throw CoreMLError.invalidImage
        }
 
        // withCheckedThrowingContinuation: 콜백 기반 API를 async/await로 변환하는 패턴
        // Vision의 completion handler를 async 함수처럼 쓸 수 있게 해줌
        return try await withCheckedThrowingContinuation { continuation in
 
            // Step 4: VNCoreMLRequest 생성 — 추론 완료 시 호출될 클로저 설정
            let request = VNCoreMLRequest(model: visionModel) { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
 
                // 결과를 VNClassificationObservation 배열로 캐스팅
                // VNClassificationObservation: identifier(레이블) + confidence(신뢰도)
                let observations = request.results as? [VNClassificationObservation] ?? []
 
                // 상위 5개 결과만 추출 (confidence 기준 내림차순 정렬은 Vision이 자동으로 해줌)
                let results = observations.prefix(5).map {
                    ClassificationResult(label: $0.identifier, confidence: $0.confidence)
                }
 
                continuation.resume(returning: Array(results))
            }
 
            // 이미지 크롭 방식: centerCrop은 이미지 중앙을 정사각형으로 자름
            // 모델 학습 데이터와 입력 형식을 맞추는 것이 핵심
            request.imageCropAndScaleOption = .centerCrop
 
            // Step 5: VNImageRequestHandler — 이미지 + 요청을 묶어서 실행
            // 실제 추론은 여기서 일어남 (perform 호출 시)
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
 
            do {
                // ⚠️ perform은 동기 함수지만 내부적으로 GPU/Neural Engine에서 비동기 처리
                // 메인 스레드에서 호출하면 UI가 잠깐 멈출 수 있음 → 뒤에서 Task { } 안에서 호출
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
 
    // MARK: - 에러 타입
    enum CoreMLError: LocalizedError {
        case modelNotLoaded
        case invalidImage
 
        var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "모델을 로드할 수 없어요. MobileNetV2.mlmodel 파일이 프로젝트에 추가되어 있는지 확인하세요."
            case .invalidImage:
                return "이미지를 처리할 수 없어요."
            }
        }
    }
}
