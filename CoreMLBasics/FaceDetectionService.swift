// FaceDetectionService.swift
// Task 3: 얼굴 인식 + 랜드마크 추출
//
// Task 1~2와 다른 점:
// - VNDetectFaceLandmarksRequest: 랜드마크 좌표는 이미지 전체 기준이 아닌
//   얼굴 boundingBox 기준 로컬 좌표 → 변환을 두 단계로 해야 함

import Vision
import UIKit

struct FaceResult: Identifiable {
    let id = UUID()
    let boundingBox: CGRect
    let landmarks: FaceLandmarkPoints?
}

struct FaceLandmarkPoints {
    let leftEye: [CGPoint]
    let rightEye: [CGPoint]
    let nose: [CGPoint]
    let outerLips: [CGPoint]
    let leftEyebrow: [CGPoint]
    let rightEyebrow: [CGPoint]
    let faceContour: [CGPoint]
}

class FaceDetectionService {

    // Task 2의 CameraService.captureOutput()에 추가해서 실시간으로도 사용 가능
    func makeRequest(onResult: @escaping ([FaceResult]) -> Void) -> VNDetectFaceLandmarksRequest {
        VNDetectFaceLandmarksRequest { request, _ in
            let observations = request.results as? [VNFaceObservation] ?? []
            let results = observations.map { FaceResult(boundingBox: $0.boundingBox,
                                                        landmarks: self.extractLandmarks(from: $0)) }
            DispatchQueue.main.async { onResult(results) }
        }
    }

    // 정지 이미지용 (Task 1의 CoreMLService와 동일한 async/await 패턴)
    enum DetectionError: Error { case invalidImage }

    func detect(in image: UIImage) async throws -> [FaceResult] {
        guard let cgImage = image.cgImage else { throw DetectionError.invalidImage }
        return try await withCheckedThrowingContinuation { continuation in
            let handler = VNImageRequestHandler(cgImage: cgImage,
                                                orientation: image.cgImageOrientation,
                                                options: [:])
            let request = makeRequest { continuation.resume(returning: $0) }
            try? handler.perform([request])
        }
    }

    // ── Task 3의 핵심: 로컬 좌표 → Vision 전체 좌표 변환 ──
    // Task 2의 좌표 변환과 다른 점:
    //   Task 2: Vision 좌표 → SwiftUI 좌표 (1단계)
    //   Task 3: 로컬 좌표 → Vision 좌표 → SwiftUI 좌표 (2단계)
    private func extractLandmarks(from obs: VNFaceObservation) -> FaceLandmarkPoints? {
        guard let lm = obs.landmarks else { return nil }
        let box = obs.boundingBox

        func toVisionCoords(_ region: VNFaceLandmarkRegion2D?) -> [CGPoint] {
            region?.normalizedPoints.map {
                CGPoint(x: box.minX + $0.x * box.width,   // 로컬 → Vision 전체 좌표
                        y: box.minY + $0.y * box.height)
            } ?? []
        }

        return FaceLandmarkPoints(
            leftEye:     toVisionCoords(lm.leftEye),
            rightEye:    toVisionCoords(lm.rightEye),
            nose:        toVisionCoords(lm.nose),
            outerLips:   toVisionCoords(lm.outerLips),
            leftEyebrow: toVisionCoords(lm.leftEyebrow),
            rightEyebrow:toVisionCoords(lm.rightEyebrow),
            faceContour: toVisionCoords(lm.faceContour)
        )
    }
}

extension UIImage {
    var cgImageOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
